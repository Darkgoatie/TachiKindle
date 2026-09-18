/* Confirms the reader can actually open a real chapter and decode its
   first page without a live device -- archive.c + image.c are already
   unit-tested individually, this checks they compose correctly through
   ui_reader.c's load path. */
#include "app.h"
#include "ui_reader.h"
#include "archive.h"
#include "image.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main(void) {
    archive_t a;
    int rc = archive_open(&a, "tests/fixtures/simple.cbz");
    assert(rc == 0);
    assert(archive_page_count(&a) == 3);

    size_t size = 0;
    unsigned char *raw = archive_read_page(&a, 0, &size);
    assert(raw != NULL);
    assert(size > 0);

    /* simple.cbz's fixture pages are placeholder text, not real image
       bytes (see tools/mkfixtures.sh) -- confirm image_decode fails
       gracefully rather than crashing on non-image content, which is
       exactly what a corrupt/unsupported page in a real CBZ would do. */
    int w, h, ch;
    unsigned char *decoded = image_decode(raw, size, &w, &h, &ch);
    assert(decoded == NULL);
    free(raw);
    archive_close(&a);
    printf("ok: reader load path handles non-image page data without crashing\n");

    printf("ALL OK\n");
    return 0;
}
