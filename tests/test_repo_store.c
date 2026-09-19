#include "minunit.h"
#include "../src/repo_store.h"
#include <string.h>
#include <stdio.h>

static void test_load_missing_file_is_empty(void) {
    repo_store_t s;
    mu_assert("missing file ok", repo_store_load(&s, "/tmp/tk_repo_store_missing.json") == 0);
    mu_assert("count zero", s.count == 0);
}

static void test_add_save_load_roundtrip(void) {
    repo_store_t s;
    memset(&s, 0, sizeof(s));
    mu_assert("add 1", repo_store_add(&s, "https://example.com/repo") == 0);
    mu_assert("add 2", repo_store_add(&s, "https://other.com/repo2") == 0);
    mu_assert("dup rejected", repo_store_add(&s, "https://example.com/repo") == -1);
    mu_assert("count 2", s.count == 2);

    const char *path = "/tmp/tk_repo_store_test.json";
    mu_assert("save ok", repo_store_save(&s, path) == 0);

    repo_store_t loaded;
    mu_assert("load ok", repo_store_load(&loaded, path) == 0);
    mu_assert("loaded count", loaded.count == 2);
    mu_assert("loaded url 0", strcmp(loaded.urls[0], "https://example.com/repo") == 0);
    mu_assert("loaded url 1", strcmp(loaded.urls[1], "https://other.com/repo2") == 0);
    remove(path);
}

static void test_remove_shifts_entries(void) {
    repo_store_t s;
    memset(&s, 0, sizeof(s));
    repo_store_add(&s, "a");
    repo_store_add(&s, "b");
    repo_store_add(&s, "c");
    mu_assert("remove ok", repo_store_remove(&s, 0) == 0);
    mu_assert("count 2", s.count == 2);
    mu_assert("shifted", strcmp(s.urls[0], "b") == 0);
    mu_assert("shifted 2", strcmp(s.urls[1], "c") == 0);
}

static void test_add_respects_max(void) {
    repo_store_t s;
    memset(&s, 0, sizeof(s));
    char buf[32];
    for (int i = 0; i < REPO_STORE_MAX; i++) {
        snprintf(buf, sizeof(buf), "u%d", i);
        mu_assert("add within cap", repo_store_add(&s, buf) == 0);
    }
    mu_assert("add past cap fails", repo_store_add(&s, "overflow") == -1);
}

MU_MAIN_BEGIN
    mu_run(test_load_missing_file_is_empty);
    mu_run(test_add_save_load_roundtrip);
    mu_run(test_remove_shifts_entries);
    mu_run(test_add_respects_max);
MU_MAIN_END
