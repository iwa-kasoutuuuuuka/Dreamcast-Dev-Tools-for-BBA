# Shared settings for the BBA devkit scripts. Dot-source this file:  . "$PSScriptRoot\_common.ps1"

$ErrorActionPreference = 'Stop'

$DevkitRoot = Split-Path -Parent $PSScriptRoot

# --- DreamSDK location (override with the DREAMSDK_HOME environment variable) ---
$DreamSDK = if ($env:DREAMSDK_HOME) { $env:DREAMSDK_HOME } else { 'C:\DreamSDK' }
$DcRoot   = Join-Path $DreamSDK 'opt\toolchains\dc'

$Tools = @{
    DcToolIp = Join-Path $DcRoot 'bin\dc-tool-ip.exe'
    Gdb      = Join-Path $DcRoot 'sh-elf\bin\sh-elf-gdb.exe'
    Gcc      = Join-Path $DcRoot 'sh-elf\bin\sh-elf-gcc.exe'
    Objcopy  = Join-Path $DcRoot 'sh-elf\bin\sh-elf-objcopy.exe'
    Scramble = Join-Path $DcRoot 'kos\utils\scramble\scramble.exe'
    MakeIp   = Join-Path $DcRoot 'kos\utils\makeip\makeip.exe'
    MkIsoFs  = Join-Path $DreamSDK 'opt\dreamsdk\tools\bdreams\tools\mkisofs.exe'
    Cdi4dc   = Join-Path $DreamSDK 'opt\dreamsdk\tools\bdreams\tools\cdi4dc.exe'
    Bash     = Join-Path $DreamSDK 'usr\bin\bash.exe'
}
$DcloadSrc = Join-Path $DcRoot 'dcload\dcload-ip'

# makeip / mkisofs need the mingw64 DLLs (libpng etc.)
$env:PATH = (Join-Path $DreamSDK 'mingw64\bin') + ';' + $env:PATH

# Runs a native tool and fails on a non-zero exit code. stderr is shown, not treated as an
# error (Windows PowerShell 5.1 + ErrorActionPreference=Stop would abort on any stderr line).
function Invoke-Native([string]$exe, [string[]]$argList, [switch]$Quiet) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Quiet) { & $exe @argList 2>&1 | Out-Null } else { & $exe @argList 2>&1 | ForEach-Object { "$_" } }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { throw "$(Split-Path -Leaf $exe) failed (exit $code)" }
}

function Assert-Tool([string]$name) {
    $p = $Tools[$name]
    if (-not (Test-Path $p)) {
        throw "$name not found: $p  (Is DreamSDK installed? Set DREAMSDK_HOME if it is not in C:\DreamSDK.)"
    }
    return $p
}

# --- User config: config\bba.config.ps1 (copy it from bba.config.example.ps1) ---
$ConfigFile = Join-Path $DevkitRoot 'config\bba.config.ps1'
$DcIp = $null
$DcToolExtraArgs = @()
$GdbPort = 2159
if (Test-Path $ConfigFile) { . $ConfigFile }

function Get-DcIp([string]$override) {
    if ($override) { return $override }
    if ($script:DcIp) { return $script:DcIp }
    throw "Dreamcast IP is not set. Pass -Ip 192.168.x.y or copy config\bba.config.example.ps1 to config\bba.config.ps1 and set `$DcIp."
}

# Runs a command line inside the DreamSDK MSYS2 login shell (needed for 'make').
function Invoke-DreamSdkBash([string]$command, [string]$workDir) {
    $bash = Assert-Tool 'Bash'
    $env:MSYSTEM = 'MINGW64'
    $env:CHERE_INVOKING = '1'
    # The DreamSDK login profile changes directory, so cd explicitly (H:\a\b -> /h/a/b).
    $full = [System.IO.Path]::GetFullPath($workDir)
    $posix = '/' + $full.Substring(0, 1).ToLower() + ($full.Substring(2) -replace '\\', '/')
    & $bash --login -c "cd '$posix' && $command"
    if ($LASTEXITCODE -ne 0) { throw "DreamSDK shell command failed ($LASTEXITCODE): $command" }
}

# "H:\foo\bar" -> "/foo/bar": the path dc-tool-ip (Windows build) serves as /pc/foo/bar,
# as long as dc-tool-ip runs with its current directory on drive H:.
function ConvertTo-PcPath([string]$winPath) {
    $full = [System.IO.Path]::GetFullPath($winPath)
    return '/' + ($full.Substring(3) -replace '\\', '/')
}
