# Local build of StashNativeDesktop.dll, the tests and the sample through CMake.
#
#   powershell -ExecutionPolicy Bypass -File Desktop\Windows\build_plugin.ps1 [-Config Release] [-RunTests]
#       [-Generator "Visual Studio 18 2026"] [-CaBundle "C:\path\to\ca-bundle.crt"]
#
# Requirements: Visual Studio with the "Desktop development with C++" workload and CMake on
# PATH. The generator is pinned explicitly (-Generator) because with Ninja on PATH CMake would
# pick Ninja by default and then reject -A x64. The default, "Visual Studio 17 2022", needs
# CMake 3.21+; VS 2019 works with CMake 3.20+ via -Generator "Visual Studio 16 2019"; VS 2026
# needs CMake 4.2+ via -Generator "Visual Studio 18 2026".
# The WebView2 SDK is fetched from NuGet by CMake at configure time; if that download fails TLS
# verification (a CMake without a CA bundle, e.g. WinLibs), pass -CaBundle to point CMake at a
# real bundle. Verification is never disabled: this fetches a binary SDK that links into the
# payments host. Close Unity / Unreal editors first: they lock loaded DLLs.
param(
    [string]$Config = "Release",
    [switch]$RunTests,
    [string]$Generator = "Visual Studio 17 2022",
    [string]$CaBundle = ""
)

$ErrorActionPreference = "Stop"
$sourceDir = $PSScriptRoot
$buildDir = Join-Path $sourceDir "build"

# TLS verification is forced on for every configure, not only when a bundle is supplied:
# CMake before 3.31 defaults file(DOWNLOAD) verification OFF, and this fetch pulls a binary SDK.
$configureArgs = @("-S", $sourceDir, "-B", $buildDir, "-G", $Generator, "-A", "x64", "-DCMAKE_TLS_VERIFY=ON")
if ($CaBundle -ne "") {
    $configureArgs += @("-DCMAKE_TLS_CAINFO=$CaBundle")
}
cmake @configureArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
cmake --build $buildDir --config $Config
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($RunTests) {
    ctest --test-dir $buildDir -C $Config --output-on-failure
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Built $buildDir\$Config\StashNativeDesktop.dll"
