#include "library.h"
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <sys/stat.h>

/* Same natural-sort semantics as archive.c; kept local since it's a
   two-line static helper and not worth a shared-util header yet. */
static int natcmp(const char *a, const char *b) {
    while (*a && *b) {
        if (isdigit((unsigned char)*a) && isdigit((unsigned char)*b)) {
            const char *a0 = a, *b0 = b;
            while (*a == '0') a++;
            while (*b == '0') b++;
            const char *as = a, *bs = b;
            while (isdigit((unsigned char)*a)) a++;
            while (isdigit((unsigned char)*b)) b++;
            size_t alen = (size_t)(a - as), blen = (size_t)(b - bs);
            if (alen != blen) return alen < blen ? -1 : 1;
            int cmp = strncmp(as, bs, alen);
            if (cmp != 0) return cmp;
            size_t azeros = (size_t)(as - a0), bzeros = (size_t)(bs - b0);
            if (azeros != bzeros) return azeros > bzeros ? -1 : 1;
        } else {
            if (*a != *b) return (unsigned char)*a - (unsigned char)*b;
            a++; b++;
        }
    }
    return (unsigned char)*a - (unsigned char)*b;
}

static int natcmp_chapter(const void *pa, const void *pb) {
    const chapter_t *a = pa, *b = pb;
    return natcmp(a->name, b->name);
}

static int has_cbz_ext(const char *name) {
    size_t len = strlen(name);
    return len > 4 && strcasecmp(name + len - 4, ".cbz") == 0;
}

static int dir_has_any_regular_file(const char *path) {
    DIR *d = opendir(path);
    if (!d) return 0;
    struct dirent *ent;
    int found = 0;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        char full[4096];
        snprintf(full, sizeof(full), "%s/%s", path, ent->d_name);
        struct stat st;
        if (stat(full, &st) == 0 && S_ISREG(st.st_mode)) { found = 1; break; }
    }
    closedir(d);
    return found;
}

static void scan_series(series_t *s, const char *series_path) {
    DIR *d = opendir(series_path);
    chapter_t *chapters = NULL;
    size_t cap = 0, n = 0;
    if (d) {
        struct dirent *ent;
        while ((ent = readdir(d)) != NULL) {
            if (ent->d_name[0] == '.') continue;
            char full[4096];
            snprintf(full, sizeof(full), "%s/%s", series_path, ent->d_name);
            struct stat st;
            if (stat(full, &st) != 0) continue;

            int is_chapter = 0, is_dir = 0;
            if (S_ISREG(st.st_mode) && has_cbz_ext(ent->d_name)) {
                is_chapter = 1;
            } else if (S_ISDIR(st.st_mode) && dir_has_any_regular_file(full)) {
                is_chapter = 1;
                is_dir = 1;
            }
            if (!is_chapter) continue;

            if (n == cap) {
                cap = cap == 0 ? 8 : cap * 2;
                chapters = realloc(chapters, cap * sizeof(chapter_t));
            }
            chapters[n].name = strdup(ent->d_name);
            chapters[n].path = strdup(full);
            chapters[n].is_dir_chapter = is_dir;
            n++;
        }
        closedir(d);
    }
    qsort(chapters, n, sizeof(chapter_t), natcmp_chapter);
    s->chapters = chapters;
    s->n_chapters = n;
    s->cover_path = NULL;
}

int library_scan(library_t *lib, const char *root) {
    lib->series = NULL;
    lib->n_series = 0;

    DIR *d = opendir(root);
    if (!d) return 0; /* missing root: empty library, not an error */

    series_t *series = NULL;
    size_t cap = 0, n = 0;
    struct dirent *ent;
    while ((ent = readdir(d)) != NULL) {
        if (ent->d_name[0] == '.') continue;
        char full[4096];
        snprintf(full, sizeof(full), "%s/%s", root, ent->d_name);
        struct stat st;
        if (stat(full, &st) != 0 || !S_ISDIR(st.st_mode)) continue;

        series_t candidate;
        scan_series(&candidate, full);
        if (candidate.n_chapters == 0) {
            free(candidate.chapters);
            continue; /* e.g. Empty/: no chapters, not a series */
        }

        if (n == cap) {
            cap = cap == 0 ? 8 : cap * 2;
            series = realloc(series, cap * sizeof(series_t));
        }
        candidate.name = strdup(ent->d_name);
        candidate.path = strdup(full);
        series[n++] = candidate;
    }
    closedir(d);

    lib->series = series;
    lib->n_series = n;
    return 0;
}

void library_free(library_t *lib) {
    for (size_t i = 0; i < lib->n_series; i++) {
        series_t *s = &lib->series[i];
        for (size_t j = 0; j < s->n_chapters; j++) {
            free(s->chapters[j].name);
            free(s->chapters[j].path);
        }
        free(s->chapters);
        free(s->name);
        free(s->path);
        free(s->cover_path);
    }
    free(lib->series);
    lib->series = NULL;
    lib->n_series = 0;
}
