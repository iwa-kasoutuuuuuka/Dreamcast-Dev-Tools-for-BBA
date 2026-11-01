<#
.SYNOPSIS
  Source-level debugging on real hardware: starts 'dc-tool-ip -g -x <elf>' in its own
  window (console + GDB bridge), then opens sh-elf-gdb connected to it.

  The program must call gdb_init() (from <arch/gdb.h>) early in main(); the GDB
  stub then stops there and waits for GDB. Build it with -g -O0 (or -Og) for good
  source stepping.

.EXAMPLE
  .\dc_gdb.ps1 ..\sample\hello_bba\hello_bba.elf
  .\dc_gdb.ps1 my.elf -Iso game.iso -Break my_function
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Elf,
    [string]$Ip,
    [string]$Iso,
    [string[]]$Break = @(),
    [switch]$Fast
)
. "$PSScriptRoot\_common.ps1"

$gdb = Assert-Tool 'Gdb'
$Elf = (Resolve-Path $Elf).Path
$ip = Get-DcIp $Ip

# 1. dc-tool-ip with the GDB server, in a separate console window
$runArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', (Join-Path $PSScriptRoot 'dc_run.ps1'), $Elf, '-Ip', $ip, '-Gdb')
if ($Iso)  { $runArgs += @('-Iso', (Resolve-Path $Iso).Path) }
if ($Fast) { $runArgs += '-Fast' }
# Windows PowerShell joins -ArgumentList with spaces and no quoting, so quote each item.
$argLine = ($runArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
Start-Process powershell -ArgumentList $argLine | Out-Null
Write-Host 'Started dc-tool-ip in a new window.'

# 2. Do NOT probe port 2159 here: dc-tool-ip accepts exactly one client, and a test
#    connection would take GDB's place. GDB retries the connect itself (tcp connect-timeout).
Start-Sleep -Seconds 2

# 3. GDB
$gdbArgs = @('-q', '-x', (Join-Path $DevkitRoot 'gdb\dreamcast.gdbinit'), '-ex', "target remote 127.0.0.1:$GdbPort")
foreach ($b in $Break) { $gdbArgs += @('-ex', "break $b") }
$gdbArgs += $Elf
Write-Host "sh-elf-gdb $($gdbArgs -join ' ')"
& $gdb @gdbArgs
