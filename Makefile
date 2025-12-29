#
# MIT License
#
# Copyright (c) 2025 Ivan Nikolskiy
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

include make/Makefile.common

EXE = cwww
SRC = main.c
OPENSSL = openssl

all: setup mbedtls libz curl libev libeio exe

setup:
	$(QUIET) $(LOG) "[Creating workspace]"
	$(MKDIR) $(BUILD) $(BUILD_LIB) $(BUILD_INCLUDE)
	$(QUIET) $(LOG) "[Done creating workspace]"

clean:
	$(QUIET) $(LOG) "[Cleaning old build]"
	$(RM) $(BUILD) $(EXE)
	$(QUIET) $(LOG) "[Done cleaning old build]"

exe:
	$(QUIET) $(LOG) "[Building executable]"
	$(ENV) $(CC) -I$(BUILD)/include $(SRC) -o $(EXE) -L$(BUILD)/lib -lmbedtls -lmbedx509 -lmbedcrypto -lz -lcurl -lev -leio
	$(QUIET) $(LOG) "[Done building executable]"

cert:
	$(QUIET) $(LOG) "[Generating self-signed certificate]"
	$(QUIET) $(OPENSSL) req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes \
		-keyout server.key -out server.crt \
		-subj "/CN=localhost"
	$(QUIET) $(OPENSSL) x509 -in server.crt -pubkey -noout \
   		| $(OPENSSL) pkey -pubin -outform DER \
   		| $(OPENSSL) dgst -sha256 -binary \
		| base64
	$(QUIET) $(LOG) "[Done generating self-signed certificate]"

include make/Makefile.libz
include make/Makefile.curl
include make/Makefile.libev
include make/Makefile.libeio
include make/Makefile.mbedtls
