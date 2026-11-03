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
@{
    Elf      = Join-Path $preset_bleem 'bleem2.elf'
    BuildDir = $preset_bleem
    Build    = 'source /h/DC/KallistiOS/environ.sh && make'
    Watch    = @((Join-Path $preset_bleem 'src'), (Join-Path $preset_bleem 'Makefile'))
    # -Watch: after a rebuild this file asks the running bleem2 to return to dcload (no reset needed)
    ReloadReq = Join-Path $preset_logs 'reload.req'
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
    }
}
