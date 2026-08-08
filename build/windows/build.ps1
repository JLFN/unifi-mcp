param(
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [string]$BinName = "",

    [string]$ProjectDir = "",

    [switch]$Native
)

$ErrorActionPreference = "Stop"

# Setup Paths — build/windows/ → project root (two levels up), or the explicit
# -ProjectDir when building any other Rust project from the shared builder.
$BuildDir = $PSScriptRoot
$OpenGrokDir = Split-Path -Parent (Split-Path -Parent $BuildDir)
$ProjectRoot = $OpenGrokDir
if (-not [string]::IsNullOrWhiteSpace($ProjectDir)) {
    $ProjectRoot = (Resolve-Path -Path $ProjectDir -ErrorAction Stop).Path
    $OpenGrokDir = $ProjectRoot
}

if (-not (Test-Path (Join-Path $ProjectRoot "Cargo.toml"))) {
    throw "No Cargo.toml found in project '$ProjectRoot'. Pass -ProjectDir C:\path\to\project."
}

# The cargo target to build is auto-detected from the project via
# `cargo metadata` unless overridden with the -BinName parameter (see
# "Resolve binary target" below). The output binary in bin/ is named after
# that target.

Write-Host "--- Rust Builder (PowerShell) ---" -ForegroundColor Cyan
Write-Host "Configuration: $Configuration" -ForegroundColor Gray

# Check if cargo is available, and install if not
$cargoPath = "$env:USERPROFILE\.cargo\bin"
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    if (Test-Path "$cargoPath\cargo.exe") {
        $env:Path = "$cargoPath;$env:Path"
    } else {
        Write-Host "Rust (cargo) not found. Installing..." -ForegroundColor Yellow
        $rustupInit = "$env:TEMP\rustup-init.exe"
        try {
            Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile $rustupInit -UseBasicParsing
            $process = Start-Process -FilePath $rustupInit -ArgumentList "-y", "--default-host", "x86_64-pc-windows-gnu", "--default-toolchain", "stable-x86_64-pc-windows-gnu" -Wait -PassThru -NoNewWindow
            if ($process.ExitCode -ne 0) {
                throw "Rust installation failed with exit code $($process.ExitCode)"
            }
            $env:Path = "$cargoPath;$env:Path"
        } finally {
            if (Test-Path $rustupInit) { Remove-Item $rustupInit -Force }
        }
    }
}

# Ensure GNU toolchain is set as default to avoid MSVC linker dependency
Write-Host "Ensuring GNU toolchain is active..." -ForegroundColor Gray
if (Get-Command rustup -ErrorAction SilentlyContinue) {
    Start-Process -FilePath "rustup" -ArgumentList "default", "stable-x86_64-pc-windows-gnu" -Wait -NoNewWindow
} elseif (Test-Path "$cargoPath\rustup.exe") {
    Start-Process -FilePath "$cargoPath\rustup.exe" -ArgumentList "default", "stable-x86_64-pc-windows-gnu" -Wait -NoNewWindow
}

# Ensure MinGW (dlltool.exe/gcc.exe) is installed for the GNU toolchain
$mingwBin = "C:\msys64\mingw64\bin"
if (-not (Get-Command dlltool -ErrorAction SilentlyContinue)) {
    if (Test-Path "$mingwBin\dlltool.exe") {
        Write-Host "Found MinGW at $mingwBin, adding to PATH..." -ForegroundColor Gray
        $env:Path += ";$mingwBin"
    } else {
        if (-not (Test-Path "C:\msys64\usr\bin\pacman.exe")) {
            Write-Host "MinGW not found. Installing MSYS2 (GNU tools)..." -ForegroundColor Yellow
            Start-Process -FilePath "winget" -ArgumentList "install", "MSYS2.MSYS2", "--accept-package-agreements", "--accept-source-agreements", "--silent" -Wait -NoNewWindow
        }
        
        if (Test-Path "C:\msys64\usr\bin\pacman.exe") {
            Write-Host "Installing MinGW-w64 toolchain..." -ForegroundColor Yellow
            Start-Process -FilePath "C:\msys64\usr\bin\pacman.exe" -ArgumentList "-S", "--noconfirm", "mingw-w64-x86_64-toolchain" -Wait -NoNewWindow
            $env:Path += ";$mingwBin"
            
            # Persist to User PATH for future sessions
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($userPath -notmatch "msys64\\mingw64\\bin") {
                [Environment]::SetEnvironmentVariable("Path", $userPath + ";$mingwBin", "User")
            }
        } else {
            throw "Failed to install MSYS2. Please install MSYS2 manually."
        }
    }
}

# Resolve binary target (auto-detected via cargo metadata, overridable with -BinName)
if ([string]::IsNullOrWhiteSpace($BinName)) {
    $metaJson = cargo metadata --manifest-path "$OpenGrokDir\Cargo.toml" --no-deps --format-version 1 2>$null
    if ([string]::IsNullOrWhiteSpace($metaJson)) {
        Write-Error "Could not read Cargo metadata - is this a Cargo project? Specify a binary with -BinName."
    }
    $meta = $metaJson | ConvertFrom-Json
    $binTargets = $meta.packages | ForEach-Object { $_.targets } | Where-Object { $_.kind -contains "bin" }
    if (-not $binTargets) {
        Write-Error "No binary target found. Specify one with -BinName."
    }
    $BinName = $binTargets | Select-Object -First 1 -ExpandProperty name
}

# Build Rust Binary
Push-Location $OpenGrokDir
try {
    if ($Native) {
        $env:RUSTFLAGS = "$env:RUSTFLAGS -C target-cpu=native".Trim()
        Write-Host "Native optimizations enabled (-C target-cpu=native)" -ForegroundColor Gray
    }

    if ($Configuration -eq "Release") {
        cargo build --release --bin $BinName
    } else {
        cargo build --bin $BinName
    }
}
finally {
    Pop-Location
}

# Ensure bin directory exists at project root
$BinDir = Join-Path $ProjectRoot "bin"
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

# Copy the binary
if ($Configuration -eq "Release") {
    $ExePath = Join-Path $OpenGrokDir "target\release\$BinName.exe"
} else {
    $ExePath = Join-Path $OpenGrokDir "target\debug\$BinName.exe"
}

if (-not (Test-Path $ExePath)) {
    Write-Error "CRITICAL - Build failed or binary not found at $ExePath"
}

$DestPath = Join-Path $BinDir "$BinName.exe"
Copy-Item -Path $ExePath -Destination $DestPath -Force

Write-Host "SUCCESS - Binary copied to $DestPath" -ForegroundColor Green

# Remove target/ to save disk space
Write-Host "Removing target/ directory to save disk space..." -ForegroundColor Gray
$TargetDir = Join-Path $OpenGrokDir "target"
if (Test-Path $TargetDir) {
    Remove-Item -Path $TargetDir -Recurse -Force
    Write-Host "target/ removed (~100GB freed)" -ForegroundColor Green
}
