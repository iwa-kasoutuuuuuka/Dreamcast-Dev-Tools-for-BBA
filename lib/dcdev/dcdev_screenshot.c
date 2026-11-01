/* Screenshot of the displayed framebuffer -> BMP on the PC. */
#include <kos.h>
#include <stdio.h>
#include <stdlib.h>
#include "dcdev.h"

static int g_shot_no;   /* next number to try; 0 = not scanned yet */

static int file_exists(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f)
        return 0;
    fclose(f);
    return 1;
}

int dcdev_screenshot(const char *name) {
    char rel[96], path[384];
    uint8_t *rgb = NULL, *bmp = NULL;
    size_t bmp_size, wrote;
    FILE *f;
    uint64_t t0 = timer_ms_gettime64();

    if (!dcdev_available())
        return -1;

    if (name) {
        snprintf(rel, sizeof(rel), "screenshots/%s", name);
    } else {
        /* continue after the highest existing number (one scan per run) */
        if (g_shot_no == 0) {
            g_shot_no = 1;
            for (;;) {
                snprintf(rel, sizeof(rel), "screenshots/shot_%04d.bmp", g_shot_no);
                if (!file_exists(dcdev_path(rel, path, sizeof(path))))
                    break;
                g_shot_no++;
            }
        }
        snprintf(rel, sizeof(rel), "screenshots/shot_%04d.bmp", g_shot_no++);
    }
    dcdev_path(rel, path, sizeof(path));

    if (!vid_screen_shot_data(&rgb) || !rgb) {
        printf("[dcdev] screenshot: could not read the framebuffer\n");
        return -1;
    }
    bmp_size = dcdev_bmp_encode(rgb, vid_mode->width, vid_mode->height, &bmp);
    free(rgb);
    if (!bmp_size)
        return -1;

    f = fopen(path, "wb");
    if (!f) {
        printf("[dcdev] screenshot: cannot create %s (does the screenshots folder exist?)\n", path);
        free(bmp);
        return -1;
    }
    wrote = fwrite(bmp, 1, bmp_size, f);
    fclose(f);
    free(bmp);
    if (wrote != bmp_size)
        return -1;
    printf("[dcdev] screenshot %s (%dx%d, %u ms)\n", path, vid_mode->width, vid_mode->height,
           (unsigned)(timer_ms_gettime64() - t0));
    return 0;
}
