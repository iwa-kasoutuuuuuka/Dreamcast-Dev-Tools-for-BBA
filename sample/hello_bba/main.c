/*
 * hello_bba - sample for the BBA / dcload-ip workflow and the dcdev helpers.
 *
 *  - printf()/dcdev_log() go to the dc-tool-ip console (and host/logs/dc_log.txt)
 *  - host/assets/message.txt is shown on screen and reloaded when you edit it on the PC
 *  - hold L+R triggers:  A = screenshot   X = VMU A1 backup   Y = VMU A1 restore
 *                        B = print the profile
 *  - per-frame timings go to host/prof/prof.csv (scripts/prof_report.ps1 summarises it)
 *  - with -DUSE_GDB the GDB stub starts and waits for sh-elf-gdb (dc_gdb.ps1 / VS Code)
 *  - START returns to dcload-ip (ready for the next upload, no power cycle)
 */
#include <kos.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dc/fs_dcload.h>
#include "dcdev.h"
#ifdef USE_GDB
#include <arch/gdb.h>
#endif

/* host/ folder of this sample as seen through /pc/ (set by build.ps1). */
#define STR_(x) #x
#define STR(x)  STR_(x)
#ifdef HOST_DIR_RAW
#define HOST_DIR STR(HOST_DIR_RAW)
#else
#define HOST_DIR "/pc"
#endif

static char g_message[256] = "(host/assets/message.txt not found)";

static void load_message(void) {
    size_t size = 0;
    char *text = dcdev_asset_load("message.txt", &size);
    if (!text)
        return;
    if (size >= sizeof(g_message))
        size = sizeof(g_message) - 1;
    memcpy(g_message, text, size);
    g_message[size] = 0;
    /* one line only on screen */
    for (char *p = g_message; *p; p++)
        if (*p == '\r' || *p == '\n') { *p = 0; break; }
    free(text);
}

/* Full redraw only when the text changes; clearing the single framebuffer
   every few frames would flicker. */
static void draw_static(void) {
    vid_clear(16, 24, 48);
    bfont_draw_str(vram_s + 640 * 80 + 40, 640, 0, "Hello from the BBA!");
    bfont_draw_str(vram_s + 640 * 140 + 40, 640, 0, g_message);
    bfont_draw_str(vram_s + 640 * 260 + 40, 640, 0, "Hold L+R: A shot  X VMU backup");
    bfont_draw_str(vram_s + 640 * 290 + 40, 640, 0, "          Y VMU restore  B profile");
    bfont_draw_str(vram_s + 640 * 330 + 40, 640, 0, "START: back to dcload");
}

static void draw_counter(int frame) {
    char line[32];

    dcdev_prof_begin("draw");
    snprintf(line, sizeof(line), "frame %-10d", frame);
    bfont_draw_str(vram_s + 640 * 400 + 40, 640, 1, line);   /* opaque: overwrites the old digits */
    dcdev_prof_end("draw");
}

static void busy_logic(void) {
    /* stand-in for game logic, so the profiler has something to measure */
    volatile float x = 0;
    dcdev_prof_begin("logic");
    for (int i = 0; i < 2000; i++)
        x += i * 0.5f;
    dcdev_prof_end("logic");
}

int main(int argc, char **argv) {
    int frame = 0;
    (void)argc; (void)argv;
#ifdef USE_GDB
    gdb_init();          /* stops here until GDB connects */
    gdb_breakpoint();
#endif

    dcdev_init(HOST_DIR);
    dcdev_log("[hello_bba] KOS %s, dcload type %d (1 = dcload-ip)\n",
              kos_get_banner(), dcload_type);

    vid_set_mode(DM_640x480, PM_RGB565);
    load_message();
    dcdev_asset_changed("message.txt");   /* start watching */
    draw_static();

    for (;;) {
        maple_device_t *cont = maple_enum_type(0, MAPLE_FUNC_CONTROLLER);
        if (cont) {
            cont_state_t *st = (cont_state_t *)maple_dev_status(cont);
            if (st && (st->buttons & CONT_START) && st->ltrig < 200)
                break;
        }

        if (dcdev_poll())
            dcdev_log("[hello_bba] combo used at frame %d\n", frame);
        if (dcdev_asset_changed("message.txt")) {
            load_message();
            draw_static();
            dcdev_log("[hello_bba] message reloaded: %s\n", g_message);
        }

        busy_logic();
        if ((frame % 10) == 0)     /* update the counter a few times a second */
            draw_counter(frame);

        if ((frame % 600) == 0)
            dcdev_log("[hello_bba] frame %d\n", frame);
        frame++;
        dcdev_prof_frame();
        vid_waitvbl();
    }

    dcdev_log("[hello_bba] bye\n");
    dcdev_log_close();
    return 0;            /* returns to dcload-ip */
}
