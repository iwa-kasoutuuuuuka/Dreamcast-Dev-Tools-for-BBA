# Regression tests for bleem2 on real hardware:
#   .\scripts\dc_auto.ps1 -Preset bleem2 -Regress .\profiles\bleem2_regress.ps1 [-UpdateBaseline]
#
# Each hashtable is one boot of bleem2:
#   Name       folder name for the results (logs\regress\<date>\<Name>, baseline logs\regress\baseline\<Name>)
#   Disc       image to boot: a file name already in build\bleem2_cd, or a .bin/.cue path on the PC
#              (it is hard-linked into build\bleem2_cd, so it has to be on the same drive)
#   Pad        pad script (src/padscript.c): "<f0> <f1> <buttons>" holds buttons, "<f> SHOT" saves
#              SHOTn.bmp, "<f> EXIT" returns to dcload and ends the test. Frames are bleem2's frames.
#   Timeout    seconds until the test is stopped (default 180)
#   Tolerance  per-channel difference that still counts as equal (default 24 of 255)
#   MaxDiff    share of different pixels that still passes (default 0.005 = 0.5 %)
#
# Screenshots of games are not part of this repository: the baseline stays in logs\ (ignored by git).
@(
    @{
        Name    = 'mslugx_boot'
        Disc    = 'METAL_SL.BIN'
        Timeout = 150
        Pad     = @'
900  SHOT
1500 SHOT
1600 1610 ST
2100 SHOT
2200 EXIT
'@
    }
)
