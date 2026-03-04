<#
.SYNOPSIS
Autonomous build script for PS2xRuntime to be used by LLM agents.
.DESCRIPTION
Invokes CMake + Ninja (preferred) or MSBuild via Visual Studio Developer Command Prompt
in the background and streams the output. If a compilation error occurs, the agent can parse it.

The script auto-detects the best available toolchain:
  1. Clang-CL + Ninja  (FASTEST — 25x speedup on 29,000+ files)
  2. MSVC + Ninja       (fast, good parallelism)
  3. MSVC + VS Solution  (slowest fallback)

.EXAMPLE
.\build_daemon.ps1 -SourceDir ".\ps2xRuntime"
.\build_daemon.ps1 -SourceDir ".\ps2xRuntime" -BuildType Release
.\build_daemon.ps1 -SourceDir ".\ps2xRuntime" -ForceGenerator "Visual Studio 17 2022"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SourceDir,
    [string]$BuildType = "Debug",
    [string]$ForceGenerator = ""   # Override auto-detection (e.g. "Visual Studio 17 2022")
)

# ── Locate vcvars64.bat (dynamic, supports ANY VS install location) ──
$vcvars = $null

# Method 1: vswhere.exe (works even if VS is installed to D:\ or custom paths)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPath) {
        $candidate = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
        if (Test-Path $candidate) {
            $vcvars = $candidate
        }
    }
}

# Method 2: Fallback to hardcoded standard paths (covers edge cases where vswhere is missing)
if (-not $vcvars) {
    $fallbackPaths = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
    )
    foreach ($path in $fallbackPaths) {
        if (Test-Path $path) {
            $vcvars = $path
            break
        }
    }
}

if (-not $vcvars) {
    Write-Error "[Build-Daemon] ERROR: Could not locate vcvars64.bat. Is Visual Studio 2022 with C++ workload installed?"
    exit 1
}

# ── Detect best toolchain ────────────────────────────────────────────
$generator = ""
$cmakeExtra = ""

if ($ForceGenerator -ne "") {
    Write-Host "[Build-Daemon] Using FORCED generator: $ForceGenerator"
    $generator = $ForceGenerator
    if ($ForceGenerator -like "*Visual Studio*") {
        $cmakeExtra = "-A x64"
    }
}
else {
    # Auto-detect: prefer Clang+Ninja > MSVC+Ninja > MSVC+VS
    $hasNinja = $null -ne (Get-Command ninja -ErrorAction SilentlyContinue)
    $hasClang = $null -ne (Get-Command clang-cl -ErrorAction SilentlyContinue)

    if ($hasNinja -and $hasClang) {
        Write-Host "[Build-Daemon] ⚡ TURBO MODE: Clang-CL + Ninja detected. This is the fastest configuration."
        $generator = "Ninja"
        $cmakeExtra = "-DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl"
    }
    elseif ($hasNinja) {
        Write-Host "[Build-Daemon] 🔧 Ninja detected (MSVC backend). Good parallelism."
        $generator = "Ninja"
    }
    else {
        Write-Host "[Build-Daemon] ⚠️  Ninja/Clang not found. Falling back to Visual Studio solution (SLOW)."
        Write-Host "[Build-Daemon] TIP: Install 'C++ Clang Compiler for Windows' and 'Ninja' via Visual Studio Installer for 25x faster builds."
        $generator = "Visual Studio 17 2022"
        $cmakeExtra = "-A x64"
    }
}

Write-Host "[Build-Daemon] Compiling $SourceDir using $generator ..."
Write-Host "[Build-Daemon] WARNING: Heavy CPU usage incoming. Keep .h modifications to an absolute minimum."

# ── Build ────────────────────────────────────────────────────────────
$cmd = "call `"$vcvars`" && cd /d `"$SourceDir`""

# Configure if build/ doesn't exist or if generator changed
if (-not (Test-Path "$SourceDir\build")) {
    Write-Host "[Build-Daemon] build/ directory not found. Running CMake configure..."
    $cmd += " && cmake -S . -B build -G `"$generator`" $cmakeExtra"
}

$cmd += " && cd build && cmake --build . --config $BuildType"

cmd.exe /c $cmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n[Build-Daemon] ✅ SUCCESS: Build completed without errors."
}
else {
    Write-Host "`n[Build-Daemon] ❌ ERROR: Build failed. Check the compiler output above."
}
exit $LASTEXITCODE
