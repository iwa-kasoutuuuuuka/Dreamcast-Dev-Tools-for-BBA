# Copy this file to bba.config.ps1 (same folder) and edit it.
# bba.config.ps1 is in .gitignore, so your network settings stay out of the repository.

# IP address of the Dreamcast (shown on the dcload-ip screen after it boots).
$DcIp = '192.168.1.200'

# Extra arguments added to every dc-tool-ip call.
#   '-f'  no FIFO delays: much faster uploads, but can drop packets on some networks
#   '-l'  legacy 1024-byte packets (try this if uploads stall)
$DcToolExtraArgs = @()

# Local TCP port where 'dc-tool-ip -g' serves GDB (fixed at 2159 in dc-tool-ip 2.0.3).
$GdbPort = 2159
