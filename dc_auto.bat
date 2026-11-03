@echo off
rem Double-click: auto debug loop for bleem2 (build, wait for dcload-ip, run, log, crash report, rerun on change).
rem Other uses: dc_auto.bat -Preset hello_bba -Watch   /   dc_auto.bat -Elf H:\path\game.elf
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\dc_auto.ps1" -Preset bleem2 -Watch
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\dc_auto.ps1" %*
)
pause
