#include "progress.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define INITIAL_CAP 16

void progress_init(progress_t *p) {
    p->entries = NULL;
    p->count = 0;
    p->cap = 0;
}

void progress_free(progress_t *p) {
    for (size_t i = 0; i < p->count; i++) {
        free(p->entries[i].series);
        free(p->entries[i].chapter);
    }
    free(p->entries);
    p->entries = NULL;
    p->count = 0;
    p->cap = 0;
}

static progress_entry_t *find_entry(const progress_t *p, const char *series, const char *chapter) {
    for (size_t i = 0; i < p->count; i++) {
        if (strcmp(p->entries[i].series, series) == 0 &&
            strcmp(p->entries[i].chapter, chapter) == 0) {
            return &p->entries[i];
        }
    }
    return NULL;
}

static int ensure_capacity(progress_t *p) {
    if (p->count < p->cap) return 0;
    size_t new_cap = p->cap == 0 ? INITIAL_CAP : p->cap * 2;
    progress_entry_t *new_entries = realloc(p->entries, new_cap * sizeof(progress_entry_t));
    if (!new_entries) return -1;
    p->entries = new_entries;
    p->cap = new_cap;
    return 0;
}

void progress_set(progress_t *p, const char *series, const char *chapter, int page) {
    progress_entry_t *e = find_entry(p, series, chapter);
    if (e) {
        e->page = page;
        e->mtime = (long)time(NULL);
        return;
    }
    if (ensure_capacity(p) != 0) return;
    progress_entry_t *ne = &p->entries[p->count];
    ne->series = strdup(series);
    ne->chapter = strdup(chapter);
    ne->page = page;
    ne->mtime = (long)time(NULL);
    p->count++;
}

int progress_get_page(const progress_t *p, const char *series, const char *chapter) {
    progress_entry_t *e = find_entry((progress_t *)p, series, chapter);
    return e ? e->page : 0;
}

size_t progress_count(const progress_t *p) {
    return p->count;
}

int progress_load(progress_t *p, const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return 0; /* missing file: not an error, empty set */

    char line[4096];
    while (fgets(line, sizeof(line), f)) {
        char *nl = strchr(line, '\n');
        if (nl) *nl = '\0';

        char *series = line;
        char *tab1 = strchr(series, '\t');
        if (!tab1) continue;
        *tab1 = '\0';
        char *chapter = tab1 + 1;

        char *tab2 = strchr(chapter, '\t');
        if (!tab2) continue;
        *tab2 = '\0';
        char *page_str = tab2 + 1;

        char *tab3 = strchr(page_str, '\t');
        if (!tab3) continue;
        *tab3 = '\0';
        char *mtime_str = tab3 + 1;

        char *endptr;
        long page = strtol(page_str, &endptr, 10);
        if (*endptr != '\0') continue;
        long mtime = strtol(mtime_str, &endptr, 10);
        if (*endptr != '\0') continue;

        progress_set(p, series, chapter, (int)page);
        progress_entry_t *e = find_entry(p, series, chapter);
        if (e) e->mtime = mtime;
    }
    fclose(f);
    return 0;
}

int progress_save(const progress_t *p, const char *path) {
    char tmp_path[4160];
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", path);

    FILE *f = fopen(tmp_path, "w");
    if (!f) return -1;

    for (size_t i = 0; i < p->count; i++) {
        progress_entry_t *e = &p->entries[i];
        fprintf(f, "%s\t%s\t%d\t%ld\n", e->series, e->chapter, e->page, e->mtime);
    }

    if (fclose(f) != 0) return -1;
    if (rename(tmp_path, path) != 0) return -1;
    return 0;
}
