#!/bin/bash

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m' # No Color

# Utility functions
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get current platform
get_current_platform() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        "x86_64")
            echo "x64"
            ;;
        "aarch64"|"arm64")
            echo "arm64"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Environment detection
get_environment_info() {
    local os_info
    local git_version="Not installed"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command_exists lsb_release; then
            os_info="$(lsb_release -d | cut -f2) $(uname -m)"
        else
            os_info="Linux $(uname -r) $(uname -m)"
        fi
    else
        os_info="$OSTYPE $(uname -m)"
    fi
    
    if command_exists git; then
        git_version=$(git --version 2>/dev/null | sed 's/git version //')
    fi
    
    cat << EOF
{
    "OS": "$os_info",
    "Shell": "$BASH_VERSION",
    "WorkingDir": "$PWD",
    "User": "${USER:-$LOGNAME}",
    "Timestamp": "$BUILD_START_TIME",
    "Git": "$git_version"
}
EOF
}

# Logging functions
write_section() {
    local title="$1"
    local line=$(printf '=%.0s' {1..80})
    echo -e "${BLUE}$line${NC}"
    echo -e "${WHITE}  $title${NC}"
    echo -e "${BLUE}$line${NC}"
}

write_step() {
    local message="$1"
    echo -e "${CYAN}::group::$message${NC}"
    echo -e "${GREEN}> $message${NC}"
}

write_end_step() {
    echo -e "${CYAN}::endgroup::${NC}"
}

write_warning() {
    local message="$1"
    echo -e "${YELLOW}::warning::$message${NC}"
}

write_error() {
    local message="$1"
    echo -e "${RED}::error::$message${NC}"
}

write_notice() {
    local message="$1"
    echo -e "${BLUE}::notice::$message${NC}"
}

add_test_result() {
    local test_name="$1"
    local status="$2"
    local message="${3:-}"
    local duration="${4:-0}"
    
    ((TEST_RESULTS[total]++))
    case "${status,,}" in
        "passed")
            ((TEST_RESULTS[passed]++))
            ;;
        "failed")
            ((TEST_RESULTS[failed]++))
            TEST_ERRORS+=("$test_name: $message (${duration}s)")
            ;;
        "skipped")
            ((TEST_RESULTS[skipped]++))
            ;;
    esac
}

# Ensure a usable Rust toolchain, not merely a cargo on PATH. A rustup shim
# with no default toolchain passes "command -v cargo" and then fails on every
# invocation, which turns a missing toolchain into a confusing failure much
# later in the build, so the tools are run rather than looked up. Repair order
# mirrors the Windows builder, which already selects a default toolchain:
# source the cargo env, select stable when rustup is present, install Rust when
# cargo is absent, and only then stop with an actionable message.
ensure_rust_toolchain() {
    local cargo_env="$HOME/.cargo/env"
    [[ -f "$cargo_env" ]] && source "$cargo_env"

    if cargo --version >/dev/null 2>&1 && rustc --version >/dev/null 2>&1; then
        return 0
    fi

    if command_exists rustup; then
        echo -e "${YELLOW}Rust is installed but no toolchain is active. Selecting stable...${NC}"
        rustup default stable >/dev/null 2>&1 || {
            rustup toolchain install stable --profile minimal || true
            rustup default stable || true
        }
        [[ -f "$cargo_env" ]] && source "$cargo_env"
        if cargo --version >/dev/null 2>&1 && rustc --version >/dev/null 2>&1; then
            echo -e "${GREEN}Toolchain ready: $(rustc --version)${NC}"
            return 0
        fi
    elif ! command_exists cargo; then
        echo -e "${YELLOW}Rust not found. Installing...${NC}"
        if command_exists curl; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
                | sh -s -- -y --default-toolchain stable --profile minimal || true
        elif command_exists wget; then
            wget -qO- https://sh.rustup.rs \
                | sh -s -- -y --default-toolchain stable --profile minimal || true
        else
            echo -e "${RED}Error: neither curl nor wget is available to install Rust.${NC}" >&2
            return 1
        fi
        [[ -f "$cargo_env" ]] && source "$cargo_env"
        if cargo --version >/dev/null 2>&1 && rustc --version >/dev/null 2>&1; then
            echo -e "${GREEN}Rust installed: $(rustc --version)${NC}"
            return 0
        fi
    fi

    echo -e "${RED}Error: cargo and rustc cannot run, so no build is possible.${NC}" >&2
    if command_exists rustup; then
        echo -e "${YELLOW}Repair the toolchain with: rustup default stable${NC}" >&2
    else
        echo -e "${YELLOW}Install Rust with: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable${NC}" >&2
    fi
    return 1
}
