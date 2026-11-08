# dc_auto.ps1 preset: bleem2 (H:\DC\bleem2) built with H:\DC\KallistiOS (gcc 15.2 toolchain, dc15).
#   .\scripts\dc_auto.ps1 -Preset bleem2 -Watch
#
# Disc image: dcload-ip 2.0.3's /cd/ redirection (-i) does not work with KallistiOS 2.3
# (dcload answers GD-ROM commands with handle 0, which KOS treats as a failure, and it has no
# DMA read). So the disc files are put in a folder the program can read through /pc/ instead:
#   build\bleem2_cd\METAL_SL.BIN, build\bleem2_cd\psbios\*.BIN
#   = /pc/DC/tools/dc-bba-tools/build/bleem2_cd on the Dreamcast
# bleem2 scans that folder (BBA_DISC_DIR in src/disc.h) after /cd when it was started by dcload,
# and loads the BIOS from its psbios\ subfolder. Other games: put the .bin/.cue there instead.
#
# This file is dot-sourced by dc_auto.ps1: keep the variable names prefixed (preset_*) so they
# cannot collide with dc_auto's own parameters and variables.
$preset_bleem = 'H:\DC\bleem2'
$preset_disc = Join-Path (Split-Path -Parent $PSScriptRoot) 'build\bleem2_cd'
# BBA_LOG_DIR in src/disc.h: debug files (BLEEMLOG, BLEEMWIN, SHOTn, ...) and reload.req
$preset_logs = Join-Path (Split-Path -Parent $PSScriptRoot) 'logs\bleem2'
$preset_stats = Join-Path $PSScriptRoot 'bleem2_stats.ps1'
@{
    Elf      = Join-Path $preset_bleem 'bleem2.elf'
    BuildDir = $preset_bleem
    Build    = 'source /h/DC/KallistiOS/environ.sh && make'
    Watch    = @((Join-Path $preset_bleem 'src'), (Join-Path $preset_bleem 'Makefile'))
    # -Watch: after a rebuild this file asks the running bleem2 to return to dcload (no reset needed)
    ReloadReq = Join-Path $preset_logs 'reload.req'
    # logs\bleem2 (debug files, reload.req, BOOTDISC, BLEEMPAD, SHOTn) and build\bleem2_cd are one set
    # on the PC, built into bleem2: with several Dreamcasts, bleem2 runs on one at a time
    Exclusive = 'bleem2'
    Prepare  = {
        $game = Join-Path $preset_bleem 'build\Metal Slug X (USA).bin'
        New-Item -ItemType Directory -Force (Join-Path $preset_disc 'psbios') | Out-Null
        New-Item -ItemType Directory -Force $preset_logs | Out-Null
        # hard link: no 100 MB copy (same NTFS volume)
        $dst = Join-Path $preset_disc 'METAL_SL.BIN'
        if ((Test-Path $game) -and -not (Test-Path $dst)) { New-Item -ItemType HardLink -Path $dst -Target $game | Out-Null }
        foreach ($b in 'OPENBIOS.BIN', 'SCPH1000.BIN') {
            $src = Join-Path $preset_bleem "psbios\$($b.ToLower())"
            $d = Join-Path $preset_disc "psbios\$b"
            if ((Test-Path $src) -and -not (Test-Path $d)) { Copy-Item $src $d }
        }
        # left over from an interrupted -Regress run: would change what a normal run boots / presses
        foreach ($f in 'BOOTDISC', 'BLEEMPAD') { Remove-Item -LiteralPath (Join-Path $preset_logs $f) -ErrorAction SilentlyContinue }
    }
    # after every run: heartbeat lines -> <log>.stats.csv / .stats.html
    PostRun  = { param($log) & $preset_stats $log }

    # -Regress profiles\bleem2_regress.ps1: each test names a disc image and a pad script
    # (src/padscript.c: SHOT writes SHOTn.bmp to logs\bleem2, EXIT returns to dcload)
    RegressOutput = $preset_logs
    RegressSetup  = {
        param($test)
        $name = 'METAL_SL.BIN'
        if ($test.Disc) {
            $name = Split-Path -Leaf $test.Disc
            if (Test-Path $test.Disc) {     # a path on the PC: hard-link it (and a .cue's tracks) into the disc folder
                $files = @(Get-Item $test.Disc)
                if ($test.Disc -match '\.cue$') {
                    $dir = Split-Path -Parent $test.Disc
                    $files += Select-String -LiteralPath $test.Disc -Pattern 'FILE\s+"([^"]+)"' |
                              ForEach-Object { Get-Item (Join-Path $dir $_.Matches[0].Groups[1].Value) }
                }
                foreach ($f in $files) {
                    $dst = Join-Path $preset_disc $f.Name
                    if (-not (Test-Path $dst)) { New-Item -ItemType HardLink -Path $dst -Target $f.FullName | Out-Null }
                }
            }
        }
        [System.IO.File]::WriteAllText((Join-Path $preset_logs 'BOOTDISC'), $name)
        [System.IO.File]::WriteAllText((Join-Path $preset_logs 'BLEEMPAD'), (($test.Pad -replace "`r", '').Trim() + "`n"))
        Write-Host "[regress] disc $name, pad script $(@($test.Pad -split "`n").Count) line(s)"
    }
    RegressCleanup = { foreach ($f in 'BOOTDISC', 'BLEEMPAD') { Remove-Item -LiteralPath (Join-Path $preset_logs $f) -ErrorAction SilentlyContinue } }
}
