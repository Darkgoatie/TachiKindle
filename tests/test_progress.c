#include "minunit.h"
#include "progress.h"

static void test_roundtrip(void) {
    progress_t p = {0};
    progress_init(&p);
    progress_set(&p, "Berserk", "Ch003.cbz", 42);
    mu_assert("save ok", progress_save(&p, "/tmp/ci_prog.tsv") == 0);

    progress_t q = {0};
    progress_init(&q);
    mu_assert("load ok", progress_load(&q, "/tmp/ci_prog.tsv") == 0);
    mu_assert("page restored", progress_get_page(&q, "Berserk", "Ch003.cbz") == 42);
    progress_free(&p); progress_free(&q);
}

static void test_missing_returns_zero(void) {
    progress_t p = {0}; progress_init(&p);
    mu_assert("unknown -> 0", progress_get_page(&p, "Nope", "Nope") == 0);
    progress_free(&p);
}

static void test_update_overwrites(void) {
    progress_t p = {0}; progress_init(&p);
    progress_set(&p, "A", "1", 5);
    progress_set(&p, "A", "1", 9);
    mu_assert("overwritten", progress_get_page(&p, "A", "1") == 9);
    mu_assert("single entry", progress_count(&p) == 1);
    progress_free(&p);
}

static void test_corrupt_line_skipped(void) {
    FILE *f = fopen("/tmp/ci_bad.tsv", "w");
    fputs("garbage-with-no-tabs\nA\t1\t7\t0\n", f); fclose(f);
    progress_t p = {0}; progress_init(&p);
    mu_assert("load tolerates junk", progress_load(&p, "/tmp/ci_bad.tsv") == 0);
    mu_assert("good line kept", progress_get_page(&p, "A", "1") == 7);
    progress_free(&p);
}

static void test_load_missing_file_is_empty_not_error(void) {
    progress_t p = {0}; progress_init(&p);
    mu_assert("missing file ok", progress_load(&p, "/tmp/ci_does_not_exist.tsv") == 0);
    mu_assert("empty", progress_count(&p) == 0);
    progress_free(&p);
}

MU_MAIN_BEGIN
    mu_run(test_roundtrip);
    mu_run(test_missing_returns_zero);
    mu_run(test_update_overwrites);
    mu_run(test_corrupt_line_skipped);
    mu_run(test_load_missing_file_is_empty_not_error);
MU_MAIN_END
