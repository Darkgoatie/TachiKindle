#ifndef CI_PROGRESS_H
#define CI_PROGRESS_H
#include <stddef.h>

typedef struct {
    char  *series;
    char  *chapter;
    int    page;
    long   mtime;
} progress_entry_t;

typedef struct {
    progress_entry_t *entries;
    size_t            count;
    size_t            cap;
} progress_t;

void   progress_init(progress_t *p);
void   progress_free(progress_t *p);
int    progress_load(progress_t *p, const char *path);
int    progress_save(const progress_t *p, const char *path);
void   progress_set(progress_t *p, const char *series, const char *chapter, int page);
int    progress_get_page(const progress_t *p, const char *series, const char *chapter);
size_t progress_count(const progress_t *p);
#endif
