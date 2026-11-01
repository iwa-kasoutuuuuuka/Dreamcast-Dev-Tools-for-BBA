<#
.SYNOPSIS
  Builds lib/dcdev against the mock KallistiOS in tests/mock and runs the PC tests
  (screenshot, log, VMU, assets, profiler, button combos). Uses the MinGW gcc from DreamSDK.
#>
. "$PSScriptRoot\..\scripts\_common.ps1"

$gcc = Join-Path $DreamSDK 'mingw64\bin\gcc.exe'
if (-not (Test-Path $gcc)) { throw "gcc not found: $gcc" }

$build = Join-Path $DevkitRoot 'build\tests'
if (Test-Path $build) { Remove-Item -Recurse -Force $build }
New-Item -ItemType Directory -Force $build | Out-Null
$exe = Join-Path $build 'test_dcdev.exe'

# The mock header must be found as <kos.h> and <dc/...> before anything else.
$lib = Join-Path $DevkitRoot 'lib\dcdev'
$src = @((Join-Path $PSScriptRoot 'test_dcdev.c')) + (Get-ChildItem $lib -Filter *.c | ForEach-Object FullName)
$gccArgs = @('-std=gnu11', '-Wall', '-Wextra', '-g', '-I', (Join-Path $PSScriptRoot 'mock'), '-include', 'kos.h', '-o', $exe) + $src
Invoke-Native $gcc $gccArgs

$work = Join-Path $build 'pc'
New-Item -ItemType Directory -Force $work | Out-Null
& $exe $work
if ($LASTEXITCODE -ne 0) { throw "dcdev tests failed" }
