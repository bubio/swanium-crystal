param(
  [string]$Output = "bin\swanium-crystal.exe",
  [ValidateSet("release", "debug")][string]$Configuration = "release",
  [string]$Crystal = "crystal"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (-not (Test-Path $vswhere)) { throw "Visual Studio C++ build tools were not found" }
  $installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $installation) { throw "Visual Studio C++ build tools were not found" }
  $vcvars = Join-Path $installation "VC\Auxiliary\Build\vcvars64.bat"
  $environment = & cmd.exe /d /c "call `"$vcvars`" >nul && set"
  foreach ($line in $environment) {
    if ($line -cmatch '^PATH=(.*)$') { $env:Path = $matches[1] }
    elseif ($line -match '^([^=]+)=(.*)$' -and $matches[1] -ine 'Path') {
      [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
  }
}
$sdlRoot = $env:SWANIUM_SDL2_DIR
if (-not $sdlRoot) { throw "SWANIUM_SDL2_DIR must point to an SDL2 development package (include and lib directories)" }

$arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") { "arm64" } else { "x64" }
$include = Join-Path $sdlRoot "include"
$library = Join-Path $sdlRoot "lib\$arch"
$dll = Join-Path $library "SDL2.dll"
if (-not (Test-Path (Join-Path $include "SDL.h"))) { throw "SDL.h was not found below $include" }
if (-not (Test-Path (Join-Path $library "SDL2.lib"))) { throw "SDL2.lib was not found below $library" }

$outputPath = Join-Path $root $Output
$outputDirectory = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force $outputDirectory | Out-Null
$object = Join-Path $outputDirectory "windows_menu.obj"
if (-not $env:CRYSTAL_CACHE_DIR) {
  $env:CRYSTAL_CACHE_DIR = Join-Path $outputDirectory ".crystal-cache"
}
New-Item -ItemType Directory -Force $env:CRYSTAL_CACHE_DIR | Out-Null

$compiler = (Get-Command cl.exe -ErrorAction SilentlyContinue).Source
if (-not $compiler -and $env:VCToolsInstallDir) {
  $compiler = Join-Path $env:VCToolsInstallDir "bin\Hostx64\x64\cl.exe"
}
if (-not $compiler -or -not (Test-Path $compiler)) { throw "cl.exe was not found after initializing the Visual Studio environment" }
& $compiler /nologo /W4 /WX /utf-8 /MT /I$include /c (Join-Path $root "src\swanium\frontend\windows_menu.c") /Fo$object
if ($LASTEXITCODE -ne 0) { throw "Compiling the Win32 frontend failed" }

$flags = @()
if ($Configuration -eq "release") { $flags += @("--release", "--no-debug") }
$flags += "--static"
$linkFlags = '"{0}" /LIBPATH:"{1}" SDL2.lib user32.lib gdi32.lib comdlg32.lib shell32.lib comctl32.lib' -f $object, $library
& $Crystal build @flags --link-flags $linkFlags (Join-Path $root "src\swanium.cr") -o $outputPath
if ($LASTEXITCODE -ne 0) { throw "Building Swanium Crystal failed" }

Get-ChildItem $outputDirectory -Filter "*.dll" | Remove-Item -Force
Copy-Item $dll (Join-Path $outputDirectory "SDL2.dll") -Force
Write-Output "Built $outputPath ($arch)"
