# hello_bba - KallistiOS sample for the BBA / dcload-ip workflow.
# Build inside the DreamSDK shell (or any KOS environment):  make            (release)
#                                                           make DEBUG=1    (-g -O0 + GDB stub)
# build.ps1 runs this Makefile from PowerShell.

TARGET = hello_bba.elf
OBJS   = main.o

# Folder of this sample as seen through dc-tool-ip's /pc/ (build.ps1 sets it, e.g.
# /work/dc_bba_devkit/sample/hello_bba). Passed unquoted and stringified in main.c,
# so the path must not contain spaces.
ifneq ($(HOST_DIR_REL),)
  KOS_CFLAGS += -DHOST_DIR_RAW=/pc$(HOST_DIR_REL)
endif
ifeq ($(DEBUG),1)
  KOS_CFLAGS += -DUSE_GDB -g -O0
endif

all: rm-elf $(TARGET)

include $(KOS_BASE)/Makefile.rules

clean: rm-elf
	-rm -f $(OBJS)

rm-elf:
	-rm -f $(TARGET)

$(TARGET): $(OBJS)
	kos-cc -o $(TARGET) $(OBJS)

# make run DC_IP=192.168.1.200
run: $(TARGET)
	dc-tool-ip -t $(DC_IP) -x $(TARGET)
