#include "input.h"
#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

#define SWIPE_MIN_DIST_PX 80
#define SWIPE_MAX_MS       400
#define TAP_MAX_DIST_PX    20

static int touch_fd = -1;

/* Protocol B multitouch state, tracking slot 0 only -- we don't need
   multi-finger gestures for a page-turning reader. */
static int cur_slot = 0;
static int down_x = -1, down_y = -1;
static int last_x = -1, last_y = -1;
static long down_ms = 0;

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static int probe_supports_mt_x(const char *devpath) {
    int fd = open(devpath, O_RDONLY | O_NONBLOCK);
    if (fd < 0) return 0;

    unsigned long absbits[(ABS_MAX + 1) / (sizeof(unsigned long) * 8) + 1];
    memset(absbits, 0, sizeof(absbits));
    int has_mt = 0;
    if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(absbits)), absbits) >= 0) {
        int word = ABS_MT_POSITION_X / (sizeof(unsigned long) * 8);
        int bit = ABS_MT_POSITION_X % (sizeof(unsigned long) * 8);
        has_mt = (absbits[word] >> bit) & 1;
    }
    close(fd);
    return has_mt;
}

int input_init(void) {
    DIR *d = opendir("/dev/input");
    if (!d) return -1;

    struct dirent *ent;
    char path[512];
    int found = -1;
    while ((ent = readdir(d)) != NULL) {
        if (strncmp(ent->d_name, "event", 5) != 0) continue;
        snprintf(path, sizeof(path), "/dev/input/%s", ent->d_name);
        if (probe_supports_mt_x(path)) {
            found = open(path, O_RDONLY | O_NONBLOCK);
            if (found >= 0) break;
        }
    }
    closedir(d);

    if (found < 0) return -1;
    touch_fd = found;
    cur_slot = 0;
    down_x = down_y = last_x = last_y = -1;
    return 0;
}

void input_shutdown(void) {
    if (touch_fd >= 0) {
        close(touch_fd);
        touch_fd = -1;
    }
}

static ev_type_t classify_release(void) {
    int dx = last_x - down_x;
    int dy = last_y - down_y;
    int adx = dx < 0 ? -dx : dx;
    int ady = dy < 0 ? -dy : dy;
    long dt = now_ms() - down_ms;

    if (adx < TAP_MAX_DIST_PX && ady < TAP_MAX_DIST_PX) {
        return EV_TAP;
    }
    if (dt <= SWIPE_MAX_MS) {
        if (adx > ady && adx >= SWIPE_MIN_DIST_PX) {
            return dx < 0 ? EV_SWIPE_L : EV_SWIPE_R;
        }
        if (ady >= adx && ady >= SWIPE_MIN_DIST_PX) {
            return dy < 0 ? EV_SWIPE_U : EV_SWIPE_D;
        }
    }
    return EV_NONE;
}

int input_poll(ci_event_t *out, int timeout_ms) {
    if (touch_fd < 0) return 0;

    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(touch_fd, &fds);
    struct timeval tv = { timeout_ms / 1000, (timeout_ms % 1000) * 1000 };

    int r = select(touch_fd + 1, &fds, NULL, NULL, &tv);
    if (r <= 0) return 0; /* timeout or error */

    struct input_event ev;
    int got_release = 0;

    while (read(touch_fd, &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
        if (ev.type == EV_ABS) {
            if (ev.code == ABS_MT_SLOT) {
                cur_slot = ev.value;
            } else if (cur_slot == 0 && ev.code == ABS_MT_TRACKING_ID) {
                if (ev.value == -1) {
                    got_release = 1;
                } else {
                    down_x = down_y = -1;
                    down_ms = now_ms();
                }
            } else if (cur_slot == 0 && ev.code == ABS_MT_POSITION_X) {
                last_x = ev.value;
                if (down_x < 0) down_x = ev.value;
            } else if (cur_slot == 0 && ev.code == ABS_MT_POSITION_Y) {
                last_y = ev.value;
                if (down_y < 0) down_y = ev.value;
            }
        } else if (ev.type == EV_KEY) {
            if (ev.code == KEY_BACK && ev.value == 1) {
                out->type = EV_KEY_BACK;
                out->x = out->y = 0;
                return 1;
            }
            if (ev.code == KEY_POWER && ev.value == 1) {
                out->type = EV_QUIT;
                out->x = out->y = 0;
                return 1;
            }
        } else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
            if (got_release && down_x >= 0 && down_y >= 0) {
                ev_type_t t = classify_release();
                down_x = down_y = -1;
                if (t != EV_NONE) {
                    out->type = t;
                    out->x = last_x;
                    out->y = last_y;
                    return 1;
                }
                got_release = 0;
            }
        }
    }
    return 0;
}
