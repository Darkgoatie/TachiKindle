#ifndef MINUNIT_H
#define MINUNIT_H
#include <stdio.h>
#include <string.h>
extern int mu_tests_run, mu_tests_failed;
#define mu_assert(msg, test) do { \
    if (!(test)) { printf("  FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); \
                   mu_tests_failed++; return; } } while (0)
#define mu_run(fn) do { printf("running %s\n", #fn); mu_tests_run++; fn(); } while (0)
#define MU_MAIN_BEGIN int mu_tests_run = 0, mu_tests_failed = 0; int main(void) {
#define MU_MAIN_END printf("%d run, %d failed\n", mu_tests_run, mu_tests_failed); \
                    return mu_tests_failed ? 1 : 0; }
#endif
