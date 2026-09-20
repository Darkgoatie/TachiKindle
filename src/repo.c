/* repo.c -- see repo.h */
#include "repo.h"
#include "../third_party/cjson/cJSON.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

/* Quotes a string for safe embedding in a single-quoted shell arg by
   ending the quote, escaping a literal quote, and reopening it:
   it's -> it'\''s . Writes into `out` (must be big enough: at most
   4x strlen(in)+3). Used only for URLs we build ourselves from
   repo_url + path, never for arbitrary user text. */
static void shell_quote(const char *in, char *out, size_t out_sz) {
    size_t o = 0;
    if (out_sz == 0) return;
    out[o++] = '\'';
    for (const char *p = in; *p && o + 5 < out_sz; p++) {
        if (*p == '\'') {
            out[o++] = '\''; out[o++] = '\\'; out[o++] = '\''; out[o++] = '\'';
        } else {
            out[o++] = *p;
        }
    }
    out[o++] = '\'';
    out[o] = '\0';
}

int repo_http_get(const char *url, long timeout_s, size_t max_bytes,
                   char **out, size_t *out_len) {
    char qurl[600];
    if (strlen(url) * 4 + 4 > sizeof(qurl)) return -1;
    shell_quote(url, qurl, sizeof(qurl));

    char cmd[700];
    int n = snprintf(cmd, sizeof(cmd),
        "curl -sS --max-time %ld -L %s 2>/tmp/tk_curl_err", timeout_s, qurl);
    if (n < 0 || (size_t)n >= sizeof(cmd)) return -1;

    FILE *p = popen(cmd, "r");
    if (!p) return -1;

    size_t cap = 65536, len = 0;
    char *buf = malloc(cap);
    if (!buf) { pclose(p); return -1; }

    for (;;) {
        if (len == cap) {
            if (max_bytes && cap >= max_bytes) { free(buf); pclose(p); return -1; }
            size_t ncap = cap * 2;
            if (max_bytes && ncap > max_bytes) ncap = max_bytes;
            char *nb = realloc(buf, ncap);
            if (!nb) { free(buf); pclose(p); return -1; }
            buf = nb; cap = ncap;
        }
        size_t rd = fread(buf + len, 1, cap - len, p);
        len += rd;
        if (rd == 0) break;
    }
    int rc = pclose(p);
    if (rc != 0 || len == 0) { free(buf); return -1; }

    *out = buf;
    *out_len = len;
    return 0;
}

static void copy_field_str(const cJSON *obj, const char *key, char *dst, size_t dst_sz) {
    const cJSON *v = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (cJSON_IsString(v) && v->valuestring) {
        snprintf(dst, dst_sz, "%s", v->valuestring);
    } else {
        dst[0] = '\0';
    }
}

int repo_index_parse(const char *json, size_t len, repo_index *out) {
    memset(out, 0, sizeof(*out));
    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!root) return -1;

    copy_field_str(root, "repo_name", out->repo_name, sizeof(out->repo_name));
    cJSON *fv = cJSON_GetObjectItemCaseSensitive(root, "repo_format_version");
    out->format_version = cJSON_IsNumber(fv) ? fv->valueint : 0;

    cJSON *exts = cJSON_GetObjectItemCaseSensitive(root, "extensions");
    if (!cJSON_IsArray(exts)) { cJSON_Delete(root); return -1; }

    size_t n = (size_t)cJSON_GetArraySize(exts);
    repo_ext_entry *entries = n ? calloc(n, sizeof(repo_ext_entry)) : NULL;
    if (n && !entries) { cJSON_Delete(root); return -1; }

    size_t i = 0;
    cJSON *item;
    cJSON_ArrayForEach(item, exts) {
        if (!cJSON_IsObject(item)) continue;
        repo_ext_entry *e = &entries[i];
        copy_field_str(item, "id", e->id, sizeof(e->id));
        copy_field_str(item, "name", e->name, sizeof(e->name));
        copy_field_str(item, "lang", e->lang, sizeof(e->lang));
        copy_field_str(item, "content_warning", e->content_warning, sizeof(e->content_warning));
        copy_field_str(item, "path", e->path, sizeof(e->path));
        if (e->content_warning[0] == '\0') snprintf(e->content_warning, sizeof(e->content_warning), "SAFE");
        cJSON *vc = cJSON_GetObjectItemCaseSensitive(item, "version_code");
        e->version_code = cJSON_IsNumber(vc) ? vc->valueint : 0;
        if (e->id[0] && e->path[0]) i++;
    }
    out->entries = entries;
    out->count = i;
    cJSON_Delete(root);
    return 0;
}

void repo_index_free(repo_index *idx) {
    if (!idx) return;
    free(idx->entries);
    idx->entries = NULL;
    idx->count = 0;
}

/* Minimal shape check: required top-level keys from
   extensions/format/schema-1.0.json. Not a full JSON Schema
   validator -- just enough to reject garbage before writing it to
   the extensions dir. */
static int looks_like_valid_extension(const char *json, size_t len) {
    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!root || !cJSON_IsObject(root)) { cJSON_Delete(root); return 0; }
    const char *required[] = {
        "id", "name", "lang", "base_url", "version_code",
        "source_script", "endpoints", "selectors"
    };
    int ok = 1;
    for (size_t i = 0; i < sizeof(required) / sizeof(required[0]); i++) {
        if (!cJSON_GetObjectItemCaseSensitive(root, required[i])) { ok = 0; break; }
    }
    cJSON_Delete(root);
    return ok;
}

static int mkdir_parents(const char *path) {
    char tmp[512];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0755); /* ignore EEXIST */
            *p = '/';
        }
    }
    return 0;
}

int repo_download_extension(const char *repo_url, const repo_ext_entry *entry,
                             const char *dest_path) {
    char full_url[900];
    int n = snprintf(full_url, sizeof(full_url), "%s/%s", repo_url, entry->path);
    if (n < 0 || (size_t)n >= sizeof(full_url)) return -1;

    char *data = NULL;
    size_t data_len = 0;
    if (repo_http_get(full_url, 30, 2 * 1024 * 1024, &data, &data_len) != 0) return -1;

    if (!looks_like_valid_extension(data, data_len)) { free(data); return -1; }

    mkdir_parents(dest_path);
    FILE *f = fopen(dest_path, "wb");
    if (!f) { free(data); return -1; }
    size_t written = fwrite(data, 1, data_len, f);
    fclose(f);
    free(data);
    return (written == data_len) ? 0 : -1;
}
