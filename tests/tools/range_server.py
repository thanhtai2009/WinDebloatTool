# Minimal HTTP server with Range support for the optional aria2 integration test (Linux/macOS/Windows).
# usage: python3 range_server.py <dir> <port> [rate_kib_per_conn] [mode]   mode: ok | 403 | norange
import http.server, os, re, sys, time
root, port = sys.argv[1], int(sys.argv[2])
rate = int(sys.argv[3]) if len(sys.argv) > 3 else 0
mode = sys.argv[4] if len(sys.argv) > 4 else 'ok'
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *a): pass
    def do_HEAD(self): self.handle_req(False)
    def do_GET(self): self.handle_req(True)
    def handle_req(self, body):
        if mode == '403':
            self.send_response(403); self.send_header('Content-Length', '0'); self.end_headers(); return
        p = os.path.join(root, os.path.basename(self.path.split('?')[0]))
        if not os.path.isfile(p):
            self.send_response(404); self.send_header('Content-Length', '0'); self.end_headers(); return
        size = os.path.getsize(p); start, end = 0, size - 1
        m = re.match(r'bytes=(\d+)-(\d*)', self.headers.get('Range', '') or '')
        if m and mode != 'norange':
            start = int(m.group(1)); end = int(m.group(2)) if m.group(2) else size - 1
            self.send_response(206); self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, size))
        else:
            self.send_response(200)
        if mode != 'norange': self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(end - start + 1)); self.end_headers()
        if not body: return
        with open(p, 'rb') as f:
            f.seek(start); left = end - start + 1
            while left > 0:
                chunk = f.read(min(65536, left))
                if not chunk: break
                try: self.wfile.write(chunk)
                except Exception: return
                left -= len(chunk)
                if rate: time.sleep(len(chunk) / (rate * 1024.0))
http.server.ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
