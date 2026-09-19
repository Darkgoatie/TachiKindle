/* tests/test_repo.c -- host tests for repo.c parse/validate logic.
   Network fetch (repo_http_get) is exercised separately via a live
   HTTP server, not here -- these tests are pure and hermetic. */
#include "minunit.h"
#include "../src/repo.h"
#include <string.h>

static void test_parse_valid_index(void) {
    const char *json =
        "{\"repo_name\":\"My Repo\",\"repo_format_version\":1,"
        "\"extensions\":[{\"id\":\"en.foo\",\"name\":\"Foo\",\"lang\":\"en\","
        "\"version_code\":1,\"content_warning\":\"SAFE\","
        "\"path\":\"sources/en/foo.tkext.json\"}]}";
    repo_index idx;
    mu_assert("parse ok", repo_index_parse(json, strlen(json), &idx) == 0);
    mu_assert("repo name", strcmp(idx.repo_name, "My Repo") == 0);
    mu_assert("count 1", idx.count == 1);
    mu_assert("entry id", strcmp(idx.entries[0].id, "en.foo") == 0);
    mu_assert("entry path", strcmp(idx.entries[0].path, "sources/en/foo.tkext.json") == 0);
    repo_index_free(&idx);
}

static void test_parse_skips_incomplete_entries(void) {
    const char *json =
        "{\"repo_name\":\"R\",\"extensions\":["
        "{\"id\":\"en.good\",\"path\":\"a.json\"},"
        "{\"name\":\"no id or path\"}"
        "]}";
    repo_index idx;
    mu_assert("parse ok", repo_index_parse(json, strlen(json), &idx) == 0);
    mu_assert("only valid entry kept", idx.count == 1);
    mu_assert("kept the right one", strcmp(idx.entries[0].id, "en.good") == 0);
    repo_index_free(&idx);
}

static void test_parse_rejects_garbage(void) {
    const char *json = "not json at all";
    repo_index idx;
    mu_assert("garbage rejected", repo_index_parse(json, strlen(json), &idx) != 0);
}

static void test_parse_rejects_missing_extensions_array(void) {
    const char *json = "{\"repo_name\":\"R\"}";
    repo_index idx;
    mu_assert("missing extensions[] rejected", repo_index_parse(json, strlen(json), &idx) != 0);
}

static void test_content_warning_defaults_safe(void) {
    const char *json =
        "{\"repo_name\":\"R\",\"extensions\":["
        "{\"id\":\"en.foo\",\"path\":\"a.json\"}]}";
    repo_index idx;
    mu_assert("parse ok", repo_index_parse(json, strlen(json), &idx) == 0);
    mu_assert("defaults to SAFE", strcmp(idx.entries[0].content_warning, "SAFE") == 0);
    repo_index_free(&idx);
}

MU_MAIN_BEGIN
    mu_run(test_parse_valid_index);
    mu_run(test_parse_skips_incomplete_entries);
    mu_run(test_parse_rejects_garbage);
    mu_run(test_parse_rejects_missing_extensions_array);
    mu_run(test_content_warning_defaults_safe);
MU_MAIN_END
