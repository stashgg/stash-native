# Local build of StashNativeDesktop.dll, the tests and the sample through CMake.
#
#   powershell -ExecutionPolicy Bypass -File Desktop\Windows\build_plugin.ps1 [-Config Release] [-RunTests]
#
# Requirements: Visual Studio 2019/2022 with the "Desktop development with C++" workload (CMake
# finds it through the generator) and CMake 3.20+ on PATH. The WebView2 SDK is fetched from
# NuGet by CMake at configure time. Close Unity / Unreal editors first: they lock loaded DLLs.
param(
    [string]$Config = "Release",
    [switch]$RunTests
)

$ErrorActionPreference = "Stop"
$sourceDir = $PSScriptRoot
$buildDir = Join-Path $sourceDir "build"

cmake -S $sourceDir -B $buildDir -A x64
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake --build $buildDir --config $Config
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($RunTests) {
    ctest --test-dir $buildDir -C $Config --output-on-failure
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Built $buildDir\$Config\StashNativeDesktop.dll"
