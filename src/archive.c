#include "archive.h"
#include <zip.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static const char *IMAGE_EXTS[] = { ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", NULL };

static int has_image_ext(const char *name) {
    const char *dot = strrchr(name, '.');
    if (!dot) return 0;
    for (int i = 0; IMAGE_EXTS[i]; i++) {
        size_t elen = strlen(IMAGE_EXTS[i]);
        size_t dlen = strlen(dot);
        if (dlen != elen) continue;
        int match = 1;
        for (size_t j = 0; j < elen; j++) {
            if (tolower((unsigned char)dot[j]) != IMAGE_EXTS[i][j]) { match = 0; break; }
        }
        if (match) return 1;
    }
    return 0;
}

static int is_excluded(const char *name) {
    /* directory entries end in '/' */
    size_t len = strlen(name);
    if (len == 0 || name[len - 1] == '/') return 1;
    if (strstr(name, "__MACOSX/")) return 1;

    const char *base = strrchr(name, '/');
    base = base ? base + 1 : name;
    if (base[0] == '.') return 1; /* dotfiles, e.g. ._page001.png resource forks */
    if (strcmp(base, "Thumbs.db") == 0) return 1;
    if (strcmp(base, "ComicInfo.xml") == 0) return 1;

    return !has_image_ext(name);
}

/* Natural sort: compares runs of digits numerically, everything else by char. */
static int natcmp(const char *a, const char *b) {
    while (*a && *b) {
        if (isdigit((unsigned char)*a) && isdigit((unsigned char)*b)) {
            /* skip leading zeros, count numeric run length for tie-break */
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
            /* numerically equal; more leading zeros sorts first */
            size_t azeros = (size_t)(as - a0), bzeros = (size_t)(bs - b0);
            if (azeros != bzeros) return azeros > bzeros ? -1 : 1;
        } else {
            if (*a != *b) return (unsigned char)*a - (unsigned char)*b;
            a++; b++;
        }
    }
    return (unsigned char)*a - (unsigned char)*b;
}

static int natcmp_qsort(const void *pa, const void *pb) {
    const char *a = *(const char * const *)pa;
    const char *b = *(const char * const *)pb;
    return natcmp(a, b);
}

int archive_open(archive_t *a, const char *path) {
    int err = 0;
    zip_t *z = zip_open(path, ZIP_RDONLY, &err);
    if (!z) return -1;

    zip_int64_t n = zip_get_num_entries(z, 0);
    char **names = malloc(sizeof(char *) * (size_t)(n > 0 ? n : 1));
    int m = 0;
    for (zip_int64_t i = 0; i < n; i++) {
        const char *name = zip_get_name(z, (zip_uint64_t)i, 0);
        if (!name || is_excluded(name)) continue;
        names[m++] = strdup(name);
    }
    qsort(names, (size_t)m, sizeof(char *), natcmp_qsort);

    int *indices = malloc(sizeof(int) * (size_t)(m > 0 ? m : 1));
    for (int i = 0; i < m; i++) {
        indices[i] = (int)zip_name_locate(z, names[i], 0);
    }

    a->zip = z;
    a->names = names;
    a->indices = indices;
    a->count = m;
    return 0;
}

void archive_close(archive_t *a) {
    if (!a) return;
    for (int i = 0; i < a->count; i++) free(a->names[i]);
    free(a->names);
    free(a->indices);
    if (a->zip) zip_close((zip_t *)a->zip);
    a->zip = NULL;
    a->names = NULL;
    a->indices = NULL;
    a->count = 0;
}

int archive_page_count(const archive_t *a) {
    return a->count;
}

const char *archive_page_name(const archive_t *a, int page) {
    if (page < 0 || page >= a->count) return NULL;
    return a->names[page];
}

unsigned char *archive_read_page(archive_t *a, int page, size_t *out_size) {
    if (page < 0 || page >= a->count) return NULL;
    zip_t *z = (zip_t *)a->zip;

    struct zip_stat st;
    zip_stat_init(&st);
    if (zip_stat_index(z, (zip_uint64_t)a->indices[page], 0, &st) != 0) return NULL;

    zip_file_t *zf = zip_fopen_index(z, (zip_uint64_t)a->indices[page], 0);
    if (!zf) return NULL;

    unsigned char *buf = malloc(st.size);
    if (!buf) { zip_fclose(zf); return NULL; }

    zip_int64_t read = zip_fread(zf, buf, st.size);
    zip_fclose(zf);
    if (read < 0 || (zip_uint64_t)read != st.size) { free(buf); return NULL; }

    if (out_size) *out_size = st.size;
    return buf;
}
