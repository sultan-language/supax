# يثبت sultanc والمكتبة القياسية وسوباكس في بيت سوباكس على ويندوز (%USERPROFILE%\.supax):
#   .supax\bin\sultanc.exe
#   .supax\bin\supax.exe
#   .supax\lib\sultanc\library
#
# Installs sultanc, its standard library and Supax into the Supax home on Windows.
#
#   powershell -ExecutionPolicy Bypass -File tools\install.ps1 [-Checkout ..\sultanc] [-NoModifyPath]
#
# The SultanC checkout must already be built, so that <checkout>\build\sultanc.exe
# exists. Set SUPAX_HOME to install elsewhere. Adds .supax\bin to the user PATH
# (and to the current window) unless -NoModifyPath is given.
param(
    [string]$Checkout = "",
    [switch]$NoModifyPath
)
$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ($Checkout -eq "") { $Checkout = Join-Path $Root "..\sultanc" }
$Checkout = (Resolve-Path $Checkout).Path
$HomeDir = if ($env:SUPAX_HOME) { $env:SUPAX_HOME } else { Join-Path $HOME ".supax" }
$Bin = Join-Path $HomeDir "bin"
$Lib = Join-Path $HomeDir "lib\sultanc"

$Compiler = Join-Path $Checkout "build\sultanc.exe"
if (-not (Test-Path $Compiler)) { $Compiler = Join-Path $Checkout "build\sultanc" }
if (-not (Test-Path $Compiler)) {
    Write-Error "لم يُعثر على $Checkout\build\sultanc.exe؛ ابنِ المترجم أولا / not found: build the compiler first"
}
if (-not (Test-Path (Join-Path $Checkout "library\std"))) {
    Write-Error "not found: $Checkout\library\std"
}

New-Item -ItemType Directory -Force -Path $Bin, $Lib | Out-Null

# Replace each file through a temporary name; a running copy is renamed aside first.
function Install-File([string]$Source, [string]$Target) {
    $tmp = "$Target.tmp"
    Copy-Item -Force $Source $tmp
    if (Test-Path $Target) {
        $old = "$Target.old"
        Remove-Item -Force $old -ErrorAction SilentlyContinue
        Move-Item -Force $Target $old
    }
    Move-Item -Force $tmp $Target
}

Install-File $Compiler (Join-Path $Bin "sultanc.exe")
$NewLib = Join-Path $Lib "library.tmp"
Remove-Item -Recurse -Force $NewLib -ErrorAction SilentlyContinue
Copy-Item -Recurse (Join-Path $Checkout "library") $NewLib
Remove-Item -Recurse -Force (Join-Path $Lib "library") -ErrorAction SilentlyContinue
Move-Item $NewLib (Join-Path $Lib "library")

# Build Supax with the installed compiler. A compiler with --package-graph no
# longer reads Supax.toml: give it Supax's checked-in graph.
$Sultanc = Join-Path $Bin "sultanc.exe"
$Env:SULTANC_STD = $null
$probe = & $Sultanc --package-graph 2>&1 | Out-String
$GraphArgs = @()
if ($probe -notmatch "SULTANC-CLI-UNKNOWN-OPTION") {
    $GraphArgs = @("--package-graph=$(Join-Path $Root 'bootstrap\package-graph.toml')")
}
New-Item -ItemType Directory -Force -Path (Join-Path $Root "build") | Out-Null
$Built = Join-Path $Root "build\supax.install.exe"
Push-Location $Root
try {
    & $Sultanc @GraphArgs "src\main.sn" -o $Built
    if ($LASTEXITCODE -ne 0) { Write-Error "building supax failed" }
} finally {
    Pop-Location
}
Install-File $Built (Join-Path $Bin "supax.exe")
Remove-Item -Force $Built -ErrorAction SilentlyContinue

Write-Output "sultanc: $((& $Sultanc --version | Select-Object -First 1))"
Write-Output "supax:   $(& (Join-Path $Bin 'supax.exe') --version)"
Write-Output "installed in $HomeDir"

if (-not $NoModifyPath) {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $Parts = if ($UserPath) { $UserPath.Split(";") } else { @() }
    if ($Parts -notcontains $Bin) {
        $NewPath = if ($UserPath) { "$Bin;$UserPath" } else { $Bin }
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        Write-Output "PATH: added $Bin to the user PATH"
    }
    if (-not ($env:Path.Split(";") -contains $Bin)) { $env:Path = "$Bin;$env:Path" }
}
