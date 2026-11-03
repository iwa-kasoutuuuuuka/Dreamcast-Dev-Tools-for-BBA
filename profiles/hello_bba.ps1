# dc_auto.ps1 preset: the sample program (DreamSDK's own KallistiOS).
#   .\scripts\dc_auto.ps1 -Preset hello_bba -Watch
# Dot-sourced by dc_auto.ps1: keep variable names prefixed (preset_*).
$preset_sample = Join-Path (Split-Path -Parent $PSScriptRoot) 'sample\hello_bba'
@{
    Elf      = Join-Path $preset_sample 'hello_bba.elf'
    BuildDir = $preset_sample
    Watch    = @((Join-Path $preset_sample 'main.c'), (Join-Path $preset_sample 'Makefile'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\dcdev'))
    # build.ps1 also prepares host\ and passes HOST_DIR_REL, so use it instead of a plain make
    Build    = { & (Join-Path $preset_sample 'build.ps1') }
}
