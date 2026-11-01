# GDB settings for KallistiOS programs on a Dreamcast via dcload-ip (dc-tool-ip -g).
# Loaded by scripts\dc_gdb.ps1 before "target remote".

set architecture sh4
set endian little
# The stub only answers after the program has called gdb_init(); upload + boot can take a while.
set remotetimeout 60
set tcp connect-timeout 60
set pagination off
set confirm off
set print pretty on

# Show the source line and next instruction on every stop.
set disassemble-next-line auto

# Handy shortcuts
define kregs
  info registers pc pr sr r15
end
document kregs
Show PC, PR (return address), SR and the stack pointer.
end
