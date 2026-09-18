#include "minunit.h"
#include "archive.h"
#include <string.h>
#include <stdlib.h>

static void test_open_lists_entries(void) {
    archive_t a;
    mu_assert("open", archive_open(&a, "tests/fixtures/simple.cbz") == 0);
    mu_assert("3 pages", archive_page_count(&a) == 3);
    archive_close(&a);
}

static void test_pages_are_natural_sorted(void) {
    archive_t a;
    mu_assert("open", archive_open(&a, "tests/fixtures/simple.cbz") == 0);
    mu_assert("p0", strstr(archive_page_name(&a, 0), "page001") != NULL);
    mu_assert("p1", strstr(archive_page_name(&a, 1), "page002") != NULL);
    mu_assert("p2", strstr(archive_page_name(&a, 2), "page003") != NULL);
    archive_close(&a);
}

static void test_non_images_excluded(void) {
    archive_t a;
    mu_assert("open", archive_open(&a, "tests/fixtures/simple.cbz") == 0);
    for (int i = 0; i < archive_page_count(&a); i++) {
        const char *name = archive_page_name(&a, i);
        mu_assert("no Thumbs.db", strstr(name, "Thumbs.db") == NULL);
        mu_assert("no ComicInfo.xml", strstr(name, "ComicInfo.xml") == NULL);
        mu_assert("no __MACOSX", strstr(name, "__MACOSX") == NULL);
    }
    archive_close(&a);
}

static void test_extract_to_memory(void) {
    archive_t a;
    archive_open(&a, "tests/fixtures/simple.cbz");
    size_t size = 0;
    unsigned char *buf = archive_read_page(&a, 0, &size);
    mu_assert("buf not null", buf != NULL);
    mu_assert("size > 0", size > 0);
    mu_assert("content matches", memcmp(buf, "fake-page-one", size) == 0);
    free(buf);
    archive_close(&a);
}

static void test_open_missing_fails(void) {
    archive_t a;
    mu_assert("missing fails", archive_open(&a, "tests/fixtures/does_not_exist.cbz") < 0);
}

static void test_open_corrupt_fails(void) {
    FILE *f = fopen("/tmp/corrupt.cbz", "w");
    fputs("not a real zip file", f);
    fclose(f);
    archive_t a;
    mu_assert("corrupt fails", archive_open(&a, "/tmp/corrupt.cbz") < 0);
}

MU_MAIN_BEGIN
    mu_run(test_open_lists_entries);
    mu_run(test_pages_are_natural_sorted);
    mu_run(test_non_images_excluded);
    mu_run(test_extract_to_memory);
    mu_run(test_open_missing_fails);
    mu_run(test_open_corrupt_fails);
MU_MAIN_END
