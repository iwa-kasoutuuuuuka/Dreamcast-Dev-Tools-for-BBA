/* Asset loading from the PC with /cd/ and /rd/ fallback, plus change detection. */
#include <kos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "dcdev.h"

static void *load_file(const char *path, size_t *size) {
    FILE *f = fopen(path, "rb");
    long n;
    void *buf;

    if (!f)
        return NULL;
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) {
        fclose(f);
        return NULL;
    }
    buf = malloc(n ? n : 1);
    if (buf && fread(buf, 1, n, f) != (size_t)n) {
        free(buf);
        buf = NULL;
    }
    fclose(f);
    if (buf && size)
        *size = (size_t)n;
    return buf;
}

void *dcdev_asset_load(const char *name, size_t *size) {
    char rel[256], path[512];
    void *buf = NULL;

    if (dcdev_available()) {
        snprintf(rel, sizeof(rel), "assets/%s", name);
        buf = load_file(dcdev_path(rel, path, sizeof(path)), size);
    }
    if (!buf) {
        snprintf(path, sizeof(path), "/cd/%s", name);
        buf = load_file(path, size);
    }
    if (!buf) {
        snprintf(path, sizeof(path), "/rd/%s", name);
        buf = load_file(path, size);
    }
    if (buf)
        printf("[dcdev] asset %s <- %s\n", name, path);
    return buf;
}

#define MAX_WATCH 32
static struct {
    char     name[64];
    time_t   mtime;
    off_t    size;
    uint64_t next_ms;
} g_watch[MAX_WATCH];

int dcdev_asset_changed(const char *name) {
    char rel[256], path[512];
    struct stat st;
    uint64_t now;
    int i, slot = -1;

    if (!dcdev_available())
        return 0;
    for (i = 0; i < MAX_WATCH; i++) {
        if (strcmp(g_watch[i].name, name) == 0) { slot = i; break; }
        if (slot < 0 && g_watch[i].name[0] == 0) slot = i;
    }
    if (slot < 0)
        return 0;
    now = timer_ms_gettime64();
    if (strcmp(g_watch[slot].name, name) == 0 && now < g_watch[slot].next_ms)
        return 0;
    g_watch[slot].next_ms = now + 500;

    snprintf(rel, sizeof(rel), "assets/%s", name);
    if (stat(dcdev_path(rel, path, sizeof(path)), &st) != 0)
        return 0;
    if (g_watch[slot].name[0] == 0) {             /* first call: remember, no change */
        strncpy(g_watch[slot].name, name, sizeof(g_watch[slot].name) - 1);
        g_watch[slot].mtime = st.st_mtime;
        g_watch[slot].size = st.st_size;
        return 0;
    }
    if (st.st_mtime != g_watch[slot].mtime || st.st_size != g_watch[slot].size) {
        g_watch[slot].mtime = st.st_mtime;
        g_watch[slot].size = st.st_size;
        printf("[dcdev] asset changed: %s\n", name);
        return 1;
    }
    return 0;
}
