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
