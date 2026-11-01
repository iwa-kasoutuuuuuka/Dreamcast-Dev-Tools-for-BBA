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
    int      exists;
    time_t   mtime;
    off_t    size;
    uint64_t next_ms;
} g_watch[MAX_WATCH];

int dcdev_asset_changed(const char *name) {
    char rel[256], path[512];
    struct stat st;
    uint64_t now;
    int i, slot = -1, is_new = 0, exists, changed = 0;

    if (!dcdev_available() || !name || strlen(name) >= sizeof(g_watch[0].name))
        return 0;
    for (i = 0; i < MAX_WATCH && g_watch[i].name[0]; i++)
        if (strcmp(g_watch[i].name, name) == 0) { slot = i; break; }
    if (slot < 0) {
        if (i == MAX_WATCH)
            return 0;                             /* table full */
        slot = i;
        is_new = 1;
        strcpy(g_watch[slot].name, name);
    }

    /* every name, even a missing file, is asked about at most every 500 ms:
       each stat is a network round trip to dc-tool-ip */
    now = timer_ms_gettime64();
    if (!is_new && now < g_watch[slot].next_ms)
        return 0;
    g_watch[slot].next_ms = now + 500;

    snprintf(rel, sizeof(rel), "assets/%s", name);
    exists = stat(dcdev_path(rel, path, sizeof(path)), &st) == 0;
    if (!is_new) {
        if (exists && !g_watch[slot].exists)
            changed = 1;                          /* file appeared */
        else if (exists && (st.st_mtime != g_watch[slot].mtime || st.st_size != g_watch[slot].size))
            changed = 1;
    }
    g_watch[slot].exists = exists;
    if (exists) {
        g_watch[slot].mtime = st.st_mtime;
        g_watch[slot].size = st.st_size;
    }
    if (changed)
        printf("[dcdev] asset changed: %s\n", name);
    return changed;
}
