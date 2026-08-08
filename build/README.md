# Build System

One script per OS. Builds the project's binary, copies it to `./bin/` named after the binary target, removes `target/`.

This is the **standard builder** for any Rust project on this machine. It lives at `/data/build` (canonical copy) and works in two modes:

1. **Shared builder (recommended):** run the script directly from `/data/build` and point it at any project with `-p/--project DIR` (or `-ProjectDir` on Windows). Works for any Rust project anywhere on disk.
2. **Embedded copy:** a project can carry its own `build/<os>/build.sh` copy (as `open-grok` does), in which case the script auto-detects the project root two directories above itself.

The cargo target to build is **auto-detected** from the project itself via `cargo metadata` (first binary target found), so the scripts work in any Rust project. To force a specific target, use `-b, --bin NAME` (or set the `BIN_NAME` env var) on Linux/macOS, or `-BinName NAME` on Windows. The output in `bin/` is named after whatever target is built — e.g. `--bin uad` produces `bin/uad`, `--bin uad-ng` produces `bin/uad-ng`.

## Usage

```bash
# Shared builder: build any Rust project from /data/build
bash /data/build/linux/build.sh -p /path/to/project
bash /data/build/macos/build.sh -p /path/to/project
powershell /data/build/windows/build.ps1 -ProjectDir C:\path\to\project

# Embedded copy inside a project (Linux)
cd /path/to/project
bash build/linux/build.sh

# macOS
bash build/macos/build.sh

# Windows
powershell build/windows/build.ps1
```

### Options (all platforms)

| Option | Description | Default |
|--------|-------------|---------|
| `-c, --configuration` / `-Configuration` | `Debug` or `Release` | `Release` |
| `-b, --bin` / `-BinName` | Binary target to build | auto-detected |
| `-p, --project` / `-ProjectDir` | Project root to build | two dirs above script |
| `-n, --native` / `-Native` | `-C target-cpu=native` | Off |
| `-h, --help` | Show help | - |

On Linux/macOS the `PROJECT_ROOT` env var is also honored as an override, mirroring `BIN_NAME`.

## What each script does

1. Installs system deps if missing (`cmake`, `pkg-config`, `pkgconf`)
   - Linux: apt-get / pacman / dnf
   - macOS: Homebrew
   - Windows: MSYS2 + MinGW via winget
2. Installs Rust toolchain if missing
3. `cargo build --release --bin <detected binary>` (auto-detected via `cargo metadata`)
4. Copies binary to `./bin/<binary target name>` (e.g. `bin/uad`, `bin/uad-ng`)
5. Deletes `target/` to free disk space

> Note: step 5 removes `target/` after copying. This is intended for one-shot
> release-style builds. For iterative development (repeated rebuilds), run
> `cargo build` directly so the incremental cache survives.
