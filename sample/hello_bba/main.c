/*
 * hello_bba - smallest useful program for the BBA / dcload-ip workflow.
 *
 *  - printf() goes to the dc-tool-ip console on the PC
 *  - /pc/... reads and writes files on the PC (dc-tool-ip file server)
 *  - with -DUSE_GDB the GDB stub starts and waits for sh-elf-gdb (dc_gdb.ps1)
 *  - START returns to dcload-ip (ready for the next upload, no power cycle)
 */
#include <kos.h>
#include <stdio.h>
#include <string.h>
#include <dc/fs_dcload.h>
#ifdef USE_GDB
#include <arch/gdb.h>
#endif

/* Folder of this sample as seen through /pc/ (set by build.ps1). */
#define STR_(x) #x
#define STR(x)  STR_(x)
#ifdef HOST_DIR_RAW
#define HOST_DIR STR(HOST_DIR_RAW)
#else
#define HOST_DIR "/pc"
#endif

static int frame_counter;

static void read_host_file(void) {
    char buf[256];
    FILE *f = fopen(HOST_DIR "/data/hello.txt", "r");
    if (!f) {
        printf("[hello_bba] could not open %s/data/hello.txt\n", HOST_DIR);
        return;
    }
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    buf[n] = 0;
    fclose(f);
    printf("[hello_bba] host file says: %s\n", buf);
}

static void write_host_file(void) {
    FILE *f = fopen(HOST_DIR "/data/from_dreamcast.txt", "w");
    if (!f) return;
    fprintf(f, "Written by the Dreamcast at frame %d\n", frame_counter);
    fclose(f);
    printf("[hello_bba] wrote %s/data/from_dreamcast.txt\n", HOST_DIR);
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
#ifdef USE_GDB
    gdb_init();          /* stops here until GDB connects */
    gdb_breakpoint();
#endif

    printf("[hello_bba] KOS %s, dcload type %d (1 = dcload-ip)\n",
           kos_get_banner(), dcload_type);

    read_host_file();
    write_host_file();

    vid_set_mode(DM_640x480, PM_RGB565);
    bfont_draw_str(vram_s + 640 * 200 + 120, 640, 1, "Hello from the BBA! START = back to dcload");

    for (;;) {
        maple_device_t *cont = maple_enum_type(0, MAPLE_FUNC_CONTROLLER);
        if (cont) {
            cont_state_t *st = (cont_state_t *)maple_dev_status(cont);
            if (st && (st->buttons & CONT_START))
                break;
        }
        if ((frame_counter % 60) == 0)
            printf("[hello_bba] frame %d\n", frame_counter);
        frame_counter++;
        vid_waitvbl();
    }

    printf("[hello_bba] bye\n");
    return 0;            /* returns to dcload-ip */
}
