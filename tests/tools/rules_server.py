# Local HTTP server for tests/Test-RulesUpdate.ps1.
# usage: python3 rules_server.py <dir> <hits-log>   prints the port; <dir>/.mode = ok | hang | trickle | 404
import http.server, os, socketserver, sys, time
root, hits = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'
    def log_message(self, *a): pass
    def do_GET(self):
        with open(hits, 'a') as f: f.write(self.path + '\n')
        mf = os.path.join(root, '.mode')
        mode = open(mf).read().strip() if os.path.isfile(mf) else 'ok'
        if mode == 'hang':
            time.sleep(60); return
        p = os.path.join(root, os.path.basename(self.path.split('?')[0]))
        if mode == '404' or not os.path.isfile(p):
            self.send_response(404); self.send_header('Content-Length', '0'); self.end_headers(); return
        data = open(p, 'rb').read()
        self.send_response(200); self.send_header('Content-Length', str(len(data))); self.end_headers()
        try:
            if mode == 'trickle':
                for i in range(len(data)):
                    self.wfile.write(data[i:i + 1]); self.wfile.flush(); time.sleep(0.2)
            else:
                self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True
srv = S(('127.0.0.1', 0), H)
print(srv.server_address[1], flush=True)
srv.serve_forever()
