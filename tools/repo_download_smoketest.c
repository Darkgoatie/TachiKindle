/* tools/repo_download_smoketest.c -- live check of repo_download_extension.
   Usage: ./repo_download_smoketest <repo_url> <dest_path> */
#include "../src/repo.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s <repo_url> <dest_path>\n", argv[0]); return 2; }

    char idx_url[512];
    snprintf(idx_url, sizeof(idx_url), "%s/index.json", argv[1]);
    char *idx_data = NULL;
    size_t idx_len = 0;
    if (repo_http_get(idx_url, 20, 1024 * 1024, &idx_data, &idx_len) != 0) {
        fprintf(stderr, "index fetch failed\n");
        return 1;
    }
    repo_index idx;
    if (repo_index_parse(idx_data, idx_len, &idx) != 0 || idx.count == 0) {
        fprintf(stderr, "index parse failed or empty\n");
        free(idx_data);
        return 1;
    }
    free(idx_data);

    int rc = repo_download_extension(argv[1], &idx.entries[0], argv[2]);
    printf("download rc=%d for id=%s -> %s\n", rc, idx.entries[0].id, argv[2]);
    repo_index_free(&idx);
    return rc;
}
