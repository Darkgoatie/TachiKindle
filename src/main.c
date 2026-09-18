#include <stdio.h>
#include <unistd.h>
#include "fbink.h"

int main(void) {
    FBInkConfig cfg = { 0 };
    cfg.is_centered = true;
    cfg.is_halfway  = true;
    cfg.is_cleared  = true;

    int fbfd = fbink_open();
    if (fbfd < 0) { fprintf(stderr, "fbink_open failed\n"); return 1; }
    if (fbink_init(fbfd, &cfg) < 0) { fprintf(stderr, "fbink_init failed\n"); return 1; }

    fbink_print(fbfd, "TachiKindle: hello", &cfg);
    sleep(5);

    cfg.is_cleared = true;
    fbink_cls(fbfd, &cfg, NULL, false);
    fbink_close(fbfd);
    return 0;
}
