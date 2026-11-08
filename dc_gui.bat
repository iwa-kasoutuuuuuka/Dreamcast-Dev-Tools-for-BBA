@echo off
rem Double-click: Dreamcast BBA manager (up to 16 Dreamcasts: run / watch / stop / logs / crash reports / VMU).
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0scripts\dc_gui.ps1"
