/* repo.h -- fetch and parse TachiKindle extension repositories.
   Network transport is the system `curl` binary (present on Kindle
   firmware, linked against real OpenSSL) invoked via popen -- no TLS
   stack is implemented in TachiKindle itself. See
   extensions/format/repo-protocol.md for the wire format. */
#ifndef TK_REPO_H
#define TK_REPO_H

#include <stddef.h>

typedef struct {
    char id[64];
    char name[128];
    char lang[8];
    int version_code;
    char content_warning[8]; /* SAFE/MIXED/NSFW */
    char path[256];
} repo_ext_entry;

typedef struct {
    char repo_name[128];
    int format_version;
    repo_ext_entry *entries;
    size_t count;
} repo_index;

/* Fetches raw bytes from `url` via system curl into a heap buffer.
   Returns 0 and sets *out/*out_len on success, -1 on failure -- curl
   missing, non-2xx exit, or timeout. max_bytes bounds the response
   size to guard against a malicious/broken server; 0 means no cap.
   Caller frees *out. */
int repo_http_get(const char *url, long timeout_s, size_t max_bytes,
                   char **out, size_t *out_len);

/* Parses repo index JSON bytes (as fetched by repo_http_get from
   "<repo_url>/index.json") into a repo_index. Returns 0 on success.
   Free with repo_index_free. */
int repo_index_parse(const char *json, size_t len, repo_index *out);
void repo_index_free(repo_index *idx);

/* Downloads one extension file at "<repo_url>/<entry.path>" and
   writes it verbatim to dest_path (creating parent dirs as needed).
   Does a minimal shape check (required top-level keys from
   schema-1.0.json) before writing -- rejects the file rather than
   installing something malformed. Returns 0 on success. */
int repo_download_extension(const char *repo_url, const repo_ext_entry *entry,
                             const char *dest_path);

#endif
