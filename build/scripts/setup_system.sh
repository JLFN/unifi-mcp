#!/bin/bash

# Cross-compilation tool installation functions
install_linux_cross_tools() {
    local rust_target="$1"
    
    case "$rust_target" in
        "x86_64-unknown-linux-gnu")
            echo -e "${GRAY}Installing x86_64 cross-compilation tools...${NC}"
            install_x64_linux_tools
            ;;
        "aarch64-unknown-linux-gnu")
            echo -e "${GRAY}Installing ARM64 cross-compilation tools...${NC}"
            install_arm64_linux_tools
            ;;
        *)
            write_warning "Unknown target for cross-compilation setup: $rust_target"
            ;;
    esac
}

install_x64_linux_tools() {
    # For cross-compiling to x86_64 Linux (usually from ARM64)
    if command_exists apt-get; then
        echo -e "${YELLOW}Installing x86_64 Linux cross-compilation tools...${NC}"
        sudo apt-get update -qq
        sudo apt-get install -y gcc-x86-64-linux-gnu g++-x86-64-linux-gnu libc6-dev-amd64-cross
        
        # Set environment variables
        export CC_x86_64_unknown_linux_gnu="x86_64-linux-gnu-gcc"
        export CXX_x86_64_unknown_linux_gnu="x86_64-linux-gnu-g++"
        export AR_x86_64_unknown_linux_gnu="x86_64-linux-gnu-ar"
        export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="x86_64-linux-gnu-gcc"
        
    elif command_exists pacman; then
        echo -e "${YELLOW}Installing x86_64 Linux cross-compilation tools via pacman...${NC}"
        # Note: Cross-compiling to x86_64 on Arch ARM usually requires AUR packages or custom builds
        if pacman -Ss gcc-x86-64-linux-gnu >/dev/null 2>&1; then
            sudo pacman -S --noconfirm --needed gcc-x86-64-linux-gnu
        fi
        
        # Verify the compiler exists, if not, warn about AUR
        if ! command_exists x86_64-linux-gnu-gcc; then
            write_error "Cross-compiler 'x86_64-linux-gnu-gcc' not found."
            echo -e "${YELLOW}On Arch Linux ARM, you likely need to install 'gcc-x86-64-linux-gnu' from the AUR.${NC}"
            echo -e "${GRAY}Example (using yay): yay -S gcc-x86-64-linux-gnu${NC}"
            exit 1
        fi
        
        export CC_x86_64_unknown_linux_gnu="x86_64-linux-gnu-gcc"
        export CXX_x86_64_unknown_linux_gnu="x86_64-linux-gnu-g++"
        export AR_x86_64_unknown_linux_gnu="x86_64-linux-gnu-ar"
        export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="x86_64-linux-gnu-gcc"

    elif command_exists yum || command_exists dnf; then
        local pkg_manager="yum"
        command_exists dnf && pkg_manager="dnf"
        
        echo -e "${YELLOW}Installing x86_64 Linux cross-compilation tools via $pkg_manager...${NC}"
        sudo $pkg_manager install -y gcc-x86_64-linux-gnu binutils-x86_64-linux-gnu
        
        export CC_x86_64_unknown_linux_gnu="x86_64-linux-gnu-gcc"
        export CXX_x86_64_unknown_linux_gnu="x86_64-linux-gnu-g++"
        export AR_x86_64_unknown_linux_gnu="x86_64-linux-gnu-ar"
        export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="x86_64-linux-gnu-gcc"
        
    else
        write_warning "Could not install x86_64 cross-compilation tools automatically"
        echo -e "${GRAY}Please install gcc-x86-64-linux-gnu manually${NC}"
    fi
}

install_arm64_linux_tools() {
    # For cross-compiling to ARM64 Linux (usually from x86_64)
    if command_exists apt-get; then
        echo -e "${YELLOW}Installing ARM64 Linux cross-compilation tools...${NC}"
        sudo apt-get update -qq
        sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross
        
        # Set environment variables
        export CC_aarch64_unknown_linux_gnu="aarch64-linux-gnu-gcc"
        export CXX_aarch64_unknown_linux_gnu="aarch64-linux-gnu-g++"
        export AR_aarch64_unknown_linux_gnu="aarch64-linux-gnu-ar"
        export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-linux-gnu-gcc"
        
    elif command_exists pacman; then
        echo -e "${YELLOW}Installing ARM64 Linux cross-compilation tools via pacman...${NC}"
        sudo pacman -S --noconfirm --needed aarch64-linux-gnu-gcc
        
        export CC_aarch64_unknown_linux_gnu="aarch64-linux-gnu-gcc"
        export CXX_aarch64_unknown_linux_gnu="aarch64-linux-gnu-g++"
        export AR_aarch64_unknown_linux_gnu="aarch64-linux-gnu-ar"
        export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-linux-gnu-gcc"

    elif command_exists yum || command_exists dnf; then
        local pkg_manager="yum"
        command_exists dnf && pkg_manager="dnf"
        
        echo -e "${YELLOW}Installing ARM64 Linux cross-compilation tools via $pkg_manager...${NC}"
        sudo $pkg_manager install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
        
        export CC_aarch64_unknown_linux_gnu="aarch64-linux-gnu-gcc"
        export CXX_aarch64_unknown_linux_gnu="aarch64-linux-gnu-g++"
        export AR_aarch64_unknown_linux_gnu="aarch64-linux-gnu-ar"
        export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="aarch64-linux-gnu-gcc"
        
    else
        write_warning "Could not install ARM64 cross-compilation tools automatically"
        echo -e "${GRAY}Please install gcc-aarch64-linux-gnu manually${NC}"
    fi
}

step_setup_system() {
    write_step "Setting up System Dependencies"
    
    # Check for apt-get (Debian/Ubuntu)
    if command_exists apt-get; then
        echo -e "${YELLOW}Installing system dependencies (cmake, clang, build-essential, git, nasm, ninja-build, pkg-config, golang, libssl-dev)...${NC}"
        # Using sudo to install required build tools
        sudo apt-get update -qq
        sudo apt-get install -y cmake build-essential git nasm ninja-build pkg-config golang libssl-dev clang libclang-dev
    elif command_exists pacman; then
        echo -e "${YELLOW}Installing system dependencies (cmake, clang, base-devel)...${NC}"
        sudo pacman -S --noconfirm --needed cmake base-devel clang linux-api-headers
    else
         echo -e "${GRAY}Not on Debian/Ubuntu/Arch, skipping automated system install.${NC}"
         if ! command_exists cmake; then
             write_warning "CMake not found. Build might fail."
         fi
         if ! command_exists clang; then
             write_warning "Clang not found. Build might fail."
         fi
    fi
    
    write_end_step
}
