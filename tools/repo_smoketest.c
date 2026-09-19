/* tools/repo_smoketest.c -- live on-device check of repo.c's network
   path. Not a unit test: hits the real network. Usage:
   ./repo_smoketest <repo_url> */
#include "../src/repo.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <repo_url>\n", argv[0]); return 2; }

    char url[512];
    snprintf(url, sizeof(url), "%s/index.json", argv[1]);

    char *data = NULL;
    size_t len = 0;
    if (repo_http_get(url, 20, 1024 * 1024, &data, &len) != 0) {
        fprintf(stderr, "fetch failed for %s\n", url);
        return 1;
    }
    printf("fetched %zu bytes from %s\n", len, url);

    repo_index idx;
    if (repo_index_parse(data, len, &idx) != 0) {
        fprintf(stderr, "parse failed\n");
        free(data);
        return 1;
    }
    printf("repo_name=%s format_version=%d entries=%zu\n",
           idx.repo_name, idx.format_version, idx.count);
    for (size_t i = 0; i < idx.count; i++) {
        printf("  [%zu] id=%s name=%s lang=%s path=%s warn=%s\n",
               i, idx.entries[i].id, idx.entries[i].name,
               idx.entries[i].lang, idx.entries[i].path,
               idx.entries[i].content_warning);
    }
    repo_index_free(&idx);
    free(data);
    return 0;
}
