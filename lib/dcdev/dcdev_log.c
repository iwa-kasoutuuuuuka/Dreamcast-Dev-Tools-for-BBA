/* Console + file log. */
#include <kos.h>
#include <stdio.h>
#include <stdarg.h>
#include "dcdev.h"

static FILE *g_log;
static int   g_log_failed;

void dcdev_log(const char *fmt, ...) {
    char line[512];
    va_list ap;
    uint64_t ms = timer_ms_gettime64();

    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);

    printf("%s", line);

    if (!dcdev_available() || g_log_failed)
        return;
    if (!g_log) {
        char path[384];
        g_log = fopen(dcdev_path("logs/dc_log.txt", path, sizeof(path)), "a");
        if (!g_log) {
            g_log_failed = 1;
            printf("[dcdev] log: cannot open %s (does the logs folder exist?)\n", path);
            return;
        }
        fprintf(g_log, "---- new run ----\n");
    }
    fprintf(g_log, "[%7u.%03u] %s", (unsigned)(ms / 1000), (unsigned)(ms % 1000), line);
    fflush(g_log);
}

void dcdev_log_close(void) {
    if (g_log) {
        fclose(g_log);
        g_log = NULL;
    }
}
