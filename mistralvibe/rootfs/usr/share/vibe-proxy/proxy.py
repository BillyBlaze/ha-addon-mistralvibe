import asyncio
import json
import os
import re

# Android UAs contain "Android" (and usually "Mobile"); iOS contains
# "iPhone"/"iPad". "Mobile" alone catches most other phones. Desktop
# browsers (incl. iPad in desktop-mode, which reports "Macintosh") miss all
# of these and correctly get the desktop terminal.
MOBILE_PATTERNS = [b'iPhone', b'iPad', b'Android', b'Mobile']

TASK_QUEUE = "/data/vibe/task-queue.jsonl"

def is_mobile(header_bytes):
    ua = re.search(b'User-Agent: ([^\r\n]+)', header_bytes, re.IGNORECASE)
    if ua:
        return any(p in ua.group(1) for p in MOBILE_PATTERNS)
    return False

async def pipe(reader, writer, is_response=False, port=None):
    # NOTE: only response HEADERS may be rewritten here. Injecting bytes into
    # the body breaks HTTP framing (Content-Length / chunked) and truncates
    # the document — that is why an injected <script> at the end of the page
    # never executed. Body patches belong in the built index.html, not here.
    headers_done = not is_response
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            if is_response and not headers_done:
                head, sep, rest = data.partition(b'\r\n\r\n')
                if sep and head.startswith(b'HTTP/') and b' 101 ' not in head.split(b'\r\n', 1)[0]:
                    # never let browsers cache the app shell: code updates must
                    # show up on next page load without cache-busting queries
                    head = re.sub(b'(?i)cache-control:[^\r\n]*\r\n', b'', head)
                    # head has no trailing CRLF (partition ate it) — add one
                    # or the new header glues onto the previous line
                    head += b'\r\nCache-Control: no-store'
                    data = head + sep + rest
                headers_done = True
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass

async def handle(client_r, client_w):
    header = b''
    try:
        while b'\r\n\r\n' not in header:
            chunk = await asyncio.wait_for(client_r.read(4096), timeout=10)
            if not chunk:
                client_w.close()
                return
            header += chunk
    except Exception:
        client_w.close()
        return

    request_line = header.split(b'\r\n', 1)[0].decode('utf-8', 'replace')
    if request_line.startswith('POST /task'):
        await handle_task(client_r, client_w, header)
        return

    port = 7683 if is_mobile(header) else 7682
    ua = re.search(b'User-Agent: ([^\r\n]+)', header, re.IGNORECASE)
    ua_str = ua.group(1).decode('utf-8', 'replace') if ua else '(none)'
    print(f"[proxy] {request_line} -> port {port} | UA: {ua_str}", flush=True)

    for attempt in range(5):
        try:
            srv_r, srv_w = await asyncio.open_connection('127.0.0.1', port)
            break
        except Exception:
            if attempt == 4:
                client_w.close()
                return
            await asyncio.sleep(0.5)

    srv_w.write(header)
    await srv_w.drain()
    await asyncio.gather(pipe(client_r, srv_w),
                         pipe(srv_r, client_w, is_response=True))

async def read_body(client_r, header):
    """Read the request body, handling both Content-Length and chunked
    transfer encoding. The first read in handle() may already have buffered
    part (or all) of the body after the header terminator."""
    head, _, buffered = header.partition(b"\r\n\r\n")
    if b"transfer-encoding: chunked" in head.lower():
        body = buffered
        out = b""
        while True:
            while b"\r\n" not in body:
                chunk = await asyncio.wait_for(client_r.read(4096), timeout=10)
                if not chunk:
                    return out
                body += chunk
            size_line, body = body.split(b"\r\n", 1)
            try:
                size = int(size_line.strip(), 16)
            except ValueError:
                return out
            if size == 0:
                return out
            while len(body) < size + 2:
                chunk = await asyncio.wait_for(client_r.read(4096), timeout=10)
                if not chunk:
                    return out
                body += chunk
            out += body[:size]
            body = body[size + 2:]
    length = 0
    for line in head.split(b"\r\n"):
        if line.lower().startswith(b"content-length:"):
            try:
                length = int(line.split(b":", 1)[1].strip())
            except ValueError:
                length = 0
    body = buffered
    while len(body) < length:
        chunk = await asyncio.wait_for(client_r.read(length - len(body)), timeout=10)
        if not chunk:
            break
        body += chunk
    return body[:length]

async def handle_task(client_r, client_w, header):
    """Headless task intake: POST /task with a JSON body (one task object).
    Appends the task to the queue file the vibe-stdin-runner tails.
    hassio.addon_stdin can't be used here: under our s6 init, PID 1's fd 0 is
    /dev/null, so container-stdin delivery has nowhere to land."""
    try:
        body = await read_body(client_r, header)
        task = json.loads(body.decode('utf-8'))
        assert isinstance(task, dict)
        os.makedirs(os.path.dirname(TASK_QUEUE), exist_ok=True)
        with open(TASK_QUEUE, 'a') as f:
            f.write(json.dumps(task) + '\n')
        ok = True
    except Exception:
        ok = False
    resp = json.dumps({'ok': ok}).encode()
    client_w.write(b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: '
                   + str(len(resp)).encode() + b'\r\nConnection: close\r\n\r\n' + resp)
    await client_w.drain()
    client_w.close()

async def main():
    srv = await asyncio.start_server(handle, '0.0.0.0', 7681)
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
