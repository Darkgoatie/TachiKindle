#ifndef CI_ARCHIVE_H
#define CI_ARCHIVE_H
#include <stddef.h>

typedef struct zip zip_t_fwd; /* opaque, avoids leaking zip.h into every includer */

typedef struct {
    void   *zip;          /* struct zip* */
    char  **names;        /* sorted page entry names, owned */
    int    *indices;      /* corresponding index in the zip archive */
    int     count;
} archive_t;

int archive_open(archive_t *a, const char *path);
void archive_close(archive_t *a);
int archive_page_count(const archive_t *a);
const char *archive_page_name(const archive_t *a, int page);
/* caller frees the returned buffer */
unsigned char *archive_read_page(archive_t *a, int page, size_t *out_size);

#endif
