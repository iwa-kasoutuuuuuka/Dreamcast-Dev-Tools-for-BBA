/* dcdev core: host folder, /pc/ availability, button combos. */
#include <kos.h>
#include <dc/fs_dcload.h>
#include <stdio.h>
#include <string.h>
#include "dcdev.h"

static char g_host[256];
static int  g_avail;

int dcdev_init(const char *host_dir) {
    size_t n;
    strncpy(g_host, host_dir ? host_dir : "/pc", sizeof(g_host) - 1);
    n = strlen(g_host);
    while (n > 1 && g_host[n - 1] == '/')
        g_host[--n] = 0;
    g_avail = (dcload_type != DCLOAD_TYPE_NONE) && strncmp(g_host, "/pc", 3) == 0;
    if (g_avail)
        printf("[dcdev] host folder %s\n", g_host);
    return g_avail;
}

int dcdev_available(void) {
    return g_avail;
}

const char *dcdev_path(const char *sub, char *out, size_t outlen) {
    snprintf(out, outlen, "%s/%s", g_host, sub);
    return out;
}

uint32_t dcdev_poll(void) {
    static uint32_t prev;
    maple_device_t *dev = maple_enum_type(0, MAPLE_FUNC_CONTROLLER);
    cont_state_t *st;
    uint32_t now, pressed, fired = 0;

    if (!dev || !(st = (cont_state_t *)maple_dev_status(dev)))
        return 0;
    if (st->ltrig < 200 || st->rtrig < 200) {
        prev = st->buttons;
        return 0;
    }
    now = st->buttons;
    pressed = now & ~prev;
    prev = now;

    if (pressed & CONT_A) {
        fired = CONT_A;
        dcdev_screenshot(NULL);
    } else if (pressed & CONT_X) {
        fired = CONT_X;
        dcdev_vmu_backup(0, 1);
    } else if (pressed & CONT_Y) {
        fired = CONT_Y;
        dcdev_vmu_restore(0, 1);
    } else if (pressed & CONT_B) {
        fired = CONT_B;
        dcdev_prof_print();
    }
    return fired;
}
