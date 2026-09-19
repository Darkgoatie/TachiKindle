/* repo_store.c -- see repo_store.h */
#include "repo_store.h"
#include "../third_party/cjson/cJSON.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int repo_store_load(repo_store_t *store, const char *path) {
    memset(store, 0, sizeof(*store));

    FILE *f = fopen(path, "rb");
    if (!f) return 0; /* no saved repos yet -- not an error */

    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz <= 0) { fclose(f); return 0; }

    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return -1; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[rd] = '\0';

    cJSON *root = cJSON_ParseWithLength(buf, rd);
    free(buf);
    if (!root) return -1;

    cJSON *urls = cJSON_GetObjectItemCaseSensitive(root, "repos");
    if (cJSON_IsArray(urls)) {
        cJSON *item;
        cJSON_ArrayForEach(item, urls) {
            if (store->count >= REPO_STORE_MAX) break;
            if (cJSON_IsString(item) && item->valuestring) {
                snprintf(store->urls[store->count], REPO_STORE_URL_LEN, "%s", item->valuestring);
                store->count++;
            }
        }
    }
    cJSON_Delete(root);
    return 0;
}

int repo_store_save(const repo_store_t *store, const char *path) {
    cJSON *root = cJSON_CreateObject();
    cJSON *urls = cJSON_CreateArray();
    for (int i = 0; i < store->count; i++) {
        cJSON_AddItemToArray(urls, cJSON_CreateString(store->urls[i]));
    }
    cJSON_AddItemToObject(root, "repos", urls);

    char *text = cJSON_Print(root);
    cJSON_Delete(root);
    if (!text) return -1;

    FILE *f = fopen(path, "wb");
    if (!f) { free(text); return -1; }
    size_t len = strlen(text);
    size_t written = fwrite(text, 1, len, f);
    fclose(f);
    free(text);
    return (written == len) ? 0 : -1;
}

int repo_store_add(repo_store_t *store, const char *url) {
    if (store->count >= REPO_STORE_MAX) return -1;
    for (int i = 0; i < store->count; i++) {
        if (strcmp(store->urls[i], url) == 0) return -1;
    }
    snprintf(store->urls[store->count], REPO_STORE_URL_LEN, "%s", url);
    store->count++;
    return 0;
}

int repo_store_remove(repo_store_t *store, int i) {
    if (i < 0 || i >= store->count) return -1;
    for (int j = i; j < store->count - 1; j++) {
        memcpy(store->urls[j], store->urls[j + 1], REPO_STORE_URL_LEN);
    }
    store->count--;
    return 0;
}
