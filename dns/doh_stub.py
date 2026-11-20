#!/usr/bin/env python3
"""DoH-stub: локальний DNS (127.0.0.1:53), що ходить у провайдерів по HTTPS.

Навіщо: провайдер (AS15377) бачить звичайні DNS-запити відкритим текстом — тобто куди ми
ходимо. ControlD лишається на маці для браузера; контейнер отримує власний шифрований шлях
і не залежить від резолвера хоста.

Провайдери йдуть по черзі; перший, що відповів, стає «основним» до кінця життя процесу.
Адреси DoH-серверів не резолвляться через DNS (інакше куряче-яйце): вони мають бути в
/etc/hosts (compose `extra_hosts`) — 1.1.1.1 one.one.one.one, 9.9.9.9 dns.quad9.net, 8.8.8.8 dns.google.

Запуск: python3 doh_stub.py [--port 53] [--verbose]
Стан: /opt/data/cache/doh.state (сюди пише успіх/провал — це читає сторож).
"""
import json, os, socket, ssl, struct, sys, threading, time
from pathlib import Path

STATE = Path("/opt/data/cache/doh.state")
LOG = Path("/opt/data/cache/doh.log")
PROVIDERS = [
    ("one.one.one.one", "/dns-query"),
    ("dns.quad9.net", "/dns-query"),
    ("dns.google", "/dns/resolve" if False else "/dns-query"),
]
# Bootstrap: якщо імені провайдера немає в /etc/hosts, беремо ці адреси (куряче-яйце: DoH не може
# резолвити сам себе через DNS, який ми ж і замінюємо).
BUILTIN = {"one.one.one.one": "1.1.1.1", "dns.quad9.net": "9.9.9.9", "dns.google": "8.8.8.8"}
CACHE_TTL = 300
TIMEOUT = 4.0

_cache = {}          # ключ: (qname, qtype) -> (до якого часу, wire-відповідь)
_lock = threading.Lock()
_primary = [0]       # індекс провайдера, який спрацював останнім


def log(msg):
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG, "a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n")
    except Exception:
        pass


def state(ok, provider="", err=""):
    try:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps({"ok": ok, "ts": time.time(), "provider": provider, "err": err}))
    except Exception:
        pass


def query_key(pkt):
    """(імʼя, тип) з питання — для кешу. Парсимо мінімально."""
    try:
        i = 12
        labels = []
        while pkt[i]:
            ln = pkt[i]
            labels.append(pkt[i + 1:i + 1 + ln].decode("latin-1"))
            i += 1 + ln
        qtype = struct.unpack("!H", pkt[i + 1:i + 3])[0]
        return (".".join(labels), qtype)
    except Exception:
        return None


def doh_request(pkt, host, path):
    """POST wire-запиту на DoH. TLS з SNI = ім'я провайдера, зʼєднання за адресою з /etc/hosts."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False           # адреса беремо з /etc/hosts, імʼя — для SNI
    ctx.verify_mode = ssl.CERT_REQUIRED
    addr = BUILTIN.get(host, host)
    raw = socket.create_connection((addr, 443), timeout=TIMEOUT)
    try:
        tls = ctx.wrap_socket(raw, server_hostname=host)
        head = (
            f"POST {path} HTTP/1.1\r\nHost: {host}\r\n"
            "Content-Type: application/dns-message\r\nAccept: application/dns-message\r\n"
            f"Content-Length: {len(pkt)}\r\nConnection: close\r\n\r\n"
        ).encode()
        tls.sendall(head + pkt)
        buf = b""
        while True:
            chunk = tls.recv(65535)
            if not chunk:
                break
            buf += chunk
        tls.close()
    finally:
        raw.close()
    if not buf.startswith(b"HTTP/1.1 200"):
        raise RuntimeError(buf[:60].decode("latin1", "replace"))
    _, _, body = buf.partition(b"\r\n\r\n")
    if len(body) < 12:
        raise RuntimeError("порожня відповідь")
    return body


def resolve(pkt):
    key = query_key(pkt)
    now = time.time()
    if key:
        with _lock:
            hit = _cache.get(key)
        if hit and hit[0] > now:
            resp = bytearray(hit[1])
            resp[0:2] = pkt[0:2]        # той самий transaction id
            return bytes(resp), "cache"
    order = list(range(len(PROVIDERS)))
    start = _primary[0]
    order = order[start:] + order[:start]
    errs = []
    for idx in order:
        host, path = PROVIDERS[idx]
        try:
            body = doh_request(pkt, host, path)
            _primary[0] = idx
            if key:
                with _lock:
                    _cache[key] = (time.time() + CACHE_TTL, body)
            state(True, host)
            return body, host
        except Exception as e:
            errs.append(f"{host}: {type(e).__name__}: {e}")
    state(False, err="; ".join(errs))
    log("усі провайдери відмовили: " + "; ".join(errs))
    raise RuntimeError(errs[-1] if errs else "no providers")


def serve_udp(sock, verbose):
    while True:
        try:
            pkt, peer = sock.recvfrom(4096)
        except Exception:
            continue
        try:
            resp, via = resolve(pkt)
            sock.sendto(resp, peer)
            if verbose:
                log(f"udp {query_key(pkt)} via {via}")
        except Exception as e:
            log(f"udp fail: {e}")


def serve_tcp(srv, verbose):
    while True:
        try:
            conn, _ = srv.accept()
        except Exception:
            continue
        try:
            conn.settimeout(TIMEOUT)
            ln = struct.unpack("!H", conn.recv(2))[0]
            pkt = b""
            while len(pkt) < ln:
                chunk = conn.recv(ln - len(pkt))
                if not chunk:
                    break
                pkt += chunk
            resp, via = resolve(pkt)
            conn.sendall(struct.pack("!H", len(resp)) + resp)
            if verbose:
                log(f"tcp {query_key(pkt)} via {via}")
        except Exception as e:
            log(f"tcp fail: {e}")
        finally:
            try:
                conn.close()
            except Exception:
                pass


def main():
    port = 53
    verbose = "--verbose" in sys.argv
    if "--port" in sys.argv:
        port = int(sys.argv[sys.argv.index("--port") + 1])
    u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    u.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    u.bind(("127.0.0.1", port))
    t = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    t.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    t.bind(("127.0.0.1", port))
    t.listen(32)
    log(f"старт на 127.0.0.1:{port}, провайдери: {[p[0] for p in PROVIDERS]}")
    threading.Thread(target=serve_tcp, args=(t, verbose), daemon=True).start()
    serve_udp(u, verbose)


if __name__ == "__main__":
    main()