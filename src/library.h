#ifndef CI_LIBRARY_H
#define CI_LIBRARY_H
#include <stddef.h>

typedef struct {
    char *name;
    char *path;
    int   is_dir_chapter; /* 1 = a directory of loose images, 0 = a .cbz file */
} chapter_t;

typedef struct {
    char       *name;
    char       *path;
    chapter_t  *chapters;
    size_t      n_chapters;
    char       *cover_path; /* resolved lazily elsewhere; NULL here */
} series_t;

typedef struct {
    series_t *series;
    size_t    n_series;
} library_t;

/* Never fails on a missing/unreadable root -- returns an empty library instead. */
int library_scan(library_t *lib, const char *root);
void library_free(library_t *lib);

#endif
