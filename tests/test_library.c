#include "minunit.h"
#include "library.h"
#include <string.h>

static void test_scan_finds_series(void) {
    library_t lib;
    mu_assert("scan ok", library_scan(&lib, "tests/fixtures/library") == 0);
    mu_assert("2 series (Empty excluded)", lib.n_series == 2);
    library_free(&lib);
}

static void test_series_lists_chapters_naturally_sorted(void) {
    library_t lib;
    library_scan(&lib, "tests/fixtures/library");
    series_t *alpha = NULL;
    for (size_t i = 0; i < lib.n_series; i++) {
        if (strcmp(lib.series[i].name, "Alpha") == 0) alpha = &lib.series[i];
    }
    mu_assert("found Alpha", alpha != NULL);
    mu_assert("3 chapters", alpha->n_chapters == 3);
    mu_assert("ch1 first", strcmp(alpha->chapters[0].name, "Ch1.cbz") == 0);
    mu_assert("ch2 second", strcmp(alpha->chapters[1].name, "Ch2.cbz") == 0);
    mu_assert("ch10 last (natural sort)", strcmp(alpha->chapters[2].name, "Ch10.cbz") == 0);
    library_free(&lib);
}

static void test_loose_image_dir_is_chapter(void) {
    library_t lib;
    library_scan(&lib, "tests/fixtures/library");
    series_t *beta = NULL;
    for (size_t i = 0; i < lib.n_series; i++) {
        if (strcmp(lib.series[i].name, "Beta") == 0) beta = &lib.series[i];
    }
    mu_assert("found Beta", beta != NULL);
    mu_assert("1 chapter (Vol01 dir)", beta->n_chapters == 1);
    mu_assert("is_dir_chapter", beta->chapters[0].is_dir_chapter == 1);
    library_free(&lib);
}

static void test_empty_dir_ignored(void) {
    library_t lib;
    library_scan(&lib, "tests/fixtures/library");
    for (size_t i = 0; i < lib.n_series; i++) {
        mu_assert("Empty not a series", strcmp(lib.series[i].name, "Empty") != 0);
    }
    library_free(&lib);
}

static void test_nonexistent_root_is_empty_not_crash(void) {
    library_t lib;
    mu_assert("no crash", library_scan(&lib, "tests/fixtures/does_not_exist") == 0);
    mu_assert("empty", lib.n_series == 0);
    library_free(&lib);
}

MU_MAIN_BEGIN
    mu_run(test_scan_finds_series);
    mu_run(test_series_lists_chapters_naturally_sorted);
    mu_run(test_loose_image_dir_is_chapter);
    mu_run(test_empty_dir_ignored);
    mu_run(test_nonexistent_root_is_empty_not_crash);
MU_MAIN_END
