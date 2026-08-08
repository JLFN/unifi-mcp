#!/bin/bash
set -euo pipefail

CONFIGURATION="Release"
NATIVE_OPT=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(dirname "$SCRIPT_DIR")"
SHARED_DIR="$BUILD_DIR/scripts"
# Default project root: two directories above this script, which matches a
# build/<os>/build.sh embedded in a project. Override with -p/--project (or
# the PROJECT_ROOT env var) to build any other Rust project directly from the
# shared builder at /data/build.
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

# The cargo target to build is auto-detected from the project (see
# detect_bin_name) and can be overridden with --bin NAME or the BIN_NAME
# environment variable. The output binary in bin/ is named after that target.
BIN_NAME="${BIN_NAME:-}"

source "$SHARED_DIR/utils.sh"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "    -c, --configuration CONF    Debug or Release [default: Release]"
    echo "    -b, --bin NAME              Binary target to build [default: auto-detected]"
    echo "    -p, --project DIR           Project root to build [default: two dirs above script]"
    echo "    -n, --native                Enable -C target-cpu=native"
    echo "    -h, --help                  Show this help"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--configuration)
            CONFIGURATION="$2"
            if [[ ! "$CONFIGURATION" =~ ^(Debug|Release)$ ]]; then
                echo -e "${RED}Error: Invalid configuration '$CONFIGURATION'. Must be Debug or Release.${NC}" >&2
                exit 1
            fi
            shift 2 ;;
        -b|--bin)
            BIN_NAME="$2"
            shift 2 ;;
        -p|--project)
            PROJECT_ROOT="$2"
            shift 2 ;;
        -n|--native) NATIVE_OPT=true; shift 1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo -e "${RED}Error: Unknown option '$1'${NC}" >&2; usage >&2; exit 1 ;;
    esac
done

# Normalize the project root and make sure it is actually a Cargo project.
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd || echo "$PROJECT_ROOT")"
if [[ ! -f "$PROJECT_ROOT/Cargo.toml" ]]; then
    echo -e "${RED}Error: no Cargo.toml found in project '$PROJECT_ROOT'${NC}" >&2
    echo -e "${YELLOW}Pass the project root with: $0 -p /path/to/project${NC}" >&2
    exit 1
fi

write_section "Open Grok Builder — Linux"
echo -e "Configuration: ${GREEN}$CONFIGURATION${NC}"

# --- System deps (Linux) ---
write_step "Checking system dependencies"

install_if_missing() {
    local cmd="$1" pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y "$pkg"
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm --needed "$pkg"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "$pkg"
        else
            echo -e "${YELLOW}WARNING: $cmd not found. Install $pkg manually.${NC}"
        fi
    fi
}

install_if_missing cmake cmake
install_if_missing pkg-config pkg-config
install_if_missing pkgconf pkgconf

write_end_step

# --- Rust ---
write_step "Checking Rust"

if ! command -v cargo &>/dev/null; then
    echo -e "${YELLOW}Rust not found. Installing...${NC}"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

echo -e "${GREEN}rustc: $(rustc --version)${NC}"
echo -e "${GREEN}cargo: $(cargo --version)${NC}"

write_end_step

# --- Resolve binary target (auto-detected, overridable) ---
detect_bin_name() {
    if [[ -n "$BIN_NAME" ]]; then
        echo "$BIN_NAME"
        return 0
    fi

    local json bin
    json="$(cargo metadata --manifest-path "$PROJECT_ROOT/Cargo.toml" --no-deps --format-version 1 2>/dev/null || true)"
    if [[ -z "$json" ]]; then
        echo -e "${RED}Error: could not read Cargo metadata — is this a Cargo project?${NC}" >&2
        echo -e "${YELLOW}Specify the binary explicitly with: $0 --bin NAME (or BIN_NAME=NAME)${NC}" >&2
        return 1
    fi

    if command -v python3 &>/dev/null; then
        bin="$(printf '%s' "$json" | python3 -c '
import json, sys
try:
    m = json.load(sys.stdin)
except Exception:
    sys.exit(1)
bins = [t["name"] for p in m["packages"] for t in p["targets"] if "bin" in t["kind"]]
print(bins[0] if bins else "")
')" || bin=""
    elif command -v jq &>/dev/null; then
        bin="$(printf '%s' "$json" | jq -r '[.packages[].targets[] | select(.kind | index("bin")) | .name][0]' 2>/dev/null)" || bin=""
    fi

    if [[ -z "$bin" ]]; then
        echo -e "${RED}Error: could not determine a binary target (no binaries, or python3/jq missing).${NC}" >&2
        echo -e "${YELLOW}Specify the binary explicitly with: $0 --bin NAME (or BIN_NAME=NAME)${NC}" >&2
        return 1
    fi

    echo "$bin"
}

BIN_NAME="$(detect_bin_name)"

# --- Build ---
write_step "Building $BIN_NAME"

cd "$PROJECT_ROOT"

if [[ "$NATIVE_OPT" == "true" ]]; then
    export RUSTFLAGS="${RUSTFLAGS:-} -C target-cpu=native"
    echo -e "${GRAY}Native optimizations enabled${NC}"
fi

if [[ "$CONFIGURATION" == "Release" ]]; then
    cargo build --release --bin "$BIN_NAME"
    SRC="$PROJECT_ROOT/target/release/$BIN_NAME"
else
    cargo build --bin "$BIN_NAME"
    SRC="$PROJECT_ROOT/target/debug/$BIN_NAME"
fi

write_end_step

# --- Copy to bin/ ---
mkdir -p "$PROJECT_ROOT/bin"
cp "$SRC" "$PROJECT_ROOT/bin/$BIN_NAME"
echo -e "${GREEN}Binary → $PROJECT_ROOT/bin/$BIN_NAME${NC}"

# --- Remove target/ ---
write_step "Removing target/ (~100GB freed)"
rm -rf "$PROJECT_ROOT/target"
echo -e "${GREEN}Done${NC}"
