/* Tiny section profiler: per-frame microseconds -> prof/prof.csv. */
#include <kos.h>
#include <stdio.h>
#include <string.h>
#include "dcdev.h"

#define MAX_SECT 16

typedef struct {
    const char *name;
    uint64_t start;       /* us, 0 = not running */
    uint64_t frame_us;    /* this frame */
    uint64_t sum_us;      /* over the interval */
    uint64_t max_us;
} sect_t;

static sect_t   g_sect[MAX_SECT];
static int      g_nsect;
static int      g_interval = 60;
static int      g_frames;
static uint64_t g_frame_start, g_frame_sum, g_frame_max;
static uint32_t g_frame_no;
static FILE    *g_csv;
static int      g_csv_failed;

static sect_t *find(const char *name) {
    int i;
    for (i = 0; i < g_nsect; i++)
        if (g_sect[i].name == name)
            return &g_sect[i];
    if (g_nsect == MAX_SECT)
        return NULL;
    g_sect[g_nsect].name = name;
    return &g_sect[g_nsect++];
}

void dcdev_prof_begin(const char *name) {
    sect_t *s = find(name);
    if (s)
        s->start = timer_us_gettime64();
}

void dcdev_prof_end(const char *name) {
    sect_t *s = find(name);
    if (s && s->start) {
        s->frame_us += timer_us_gettime64() - s->start;
        s->start = 0;
    }
}

void dcdev_prof_set_interval(int frames) {
    g_interval = frames > 0 ? frames : 60;
}

static void write_csv(void) {
    int i;
    if (!dcdev_available() || g_csv_failed)
        return;
    if (!g_csv) {
        char path[384];
        g_csv = fopen(dcdev_path("prof/prof.csv", path, sizeof(path)), "wb");
        if (!g_csv) {
            g_csv_failed = 1;
            printf("[dcdev] prof: cannot create %s (does the prof folder exist?)\n", path);
            return;
        }
        fprintf(g_csv, "frame,section,avg_us,max_us\n");
    }
    fprintf(g_csv, "%u,frame,%u,%u\n", (unsigned)g_frame_no,
            (unsigned)(g_frame_sum / g_frames), (unsigned)g_frame_max);
    for (i = 0; i < g_nsect; i++)
        fprintf(g_csv, "%u,%s,%u,%u\n", (unsigned)g_frame_no, g_sect[i].name,
                (unsigned)(g_sect[i].sum_us / g_frames), (unsigned)g_sect[i].max_us);
    fflush(g_csv);
}

void dcdev_prof_print(void) {
    int i, n = g_frames ? g_frames : 1;
    printf("[dcdev] prof frame %u: frame avg %u us max %u us\n", (unsigned)g_frame_no,
           (unsigned)(g_frame_sum / n), (unsigned)g_frame_max);
    for (i = 0; i < g_nsect; i++)
        printf("[dcdev]   %-16s avg %6u us  max %6u us\n", g_sect[i].name,
               (unsigned)(g_sect[i].sum_us / n), (unsigned)g_sect[i].max_us);
}

void dcdev_prof_frame(void) {
    uint64_t now = timer_us_gettime64();
    int i;

    if (g_frame_start) {
        uint64_t ft = now - g_frame_start;
        g_frame_sum += ft;
        if (ft > g_frame_max) g_frame_max = ft;
        g_frames++;
        for (i = 0; i < g_nsect; i++) {
            g_sect[i].sum_us += g_sect[i].frame_us;
            if (g_sect[i].frame_us > g_sect[i].max_us) g_sect[i].max_us = g_sect[i].frame_us;
        }
    }
    for (i = 0; i < g_nsect; i++)
        g_sect[i].frame_us = 0;
    g_frame_start = now;
    g_frame_no++;

    if (g_frames >= g_interval) {
        write_csv();
        g_frames = 0;
        g_frame_sum = g_frame_max = 0;
        for (i = 0; i < g_nsect; i++)
            g_sect[i].sum_us = g_sect[i].max_us = 0;
    }
}
