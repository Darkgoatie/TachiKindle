/* Standalone perf check for library_scan against a large fixture tree
   (plan Phase 6, Task 6.3: target under 2s cold for ~500 chapters).
   Not a unit test -- prints timing, run manually via `make perf_scan`. */
#include "library.h"
#include <stdio.h>
#include <time.h>

int main(int argc, char **argv) {
    const char *root = argc > 1 ? argv[1] : "/tmp/perf_library";

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    library_t lib;
    library_scan(&lib, root);

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;

    size_t total_chapters = 0;
    for (size_t i = 0; i < lib.n_series; i++) total_chapters += lib.series[i].n_chapters;

    printf("scanned %zu series, %zu chapters in %.1f ms\n",
           lib.n_series, total_chapters, ms);

    library_free(&lib);
    return 0;
}
