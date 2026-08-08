#!/bin/bash

# Platform to Rust target mapping (Linux only)
get_rust_target() {
    local platform="$1"
    case "$platform" in
        "x64")
            echo "x86_64-unknown-linux-gnu"
            ;;
        "arm64")
            echo "aarch64-unknown-linux-gnu"
            ;;
        *)
            echo "unknown"
            return 1
            ;;
    esac
}

step_setup_rust() {
    write_step "Setting up Rust Environment"
    
    local cargo_env="$HOME/.cargo/env"
    local rustup_init_url="https://sh.rustup.rs"
    
    # Source cargo environment if it exists
    if [[ -f "$cargo_env" ]]; then
        source "$cargo_env"
    fi
    
    # Function to get installed Rust version
    get_rust_version() {
        if command_exists rustc; then
            rustc --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
        else
            echo "none"
        fi
    }
    
	# Function to get latest stable Rust version
	get_latest_rust_version() {
		local version
		local url="https://static.rust-lang.org/dist/channel-rust-stable.toml"
		
		# Extract version from [pkg.rust] section
		# We check for the [pkg.rust] header, then look for the first 'version = ...' line
		# awk prints the third field (the value) which we then strip quotes from
		if command_exists curl; then
			version=$(curl -sSf "$url" 2>/dev/null | \
				awk '/^\[pkg\.rust\]/ {found=1} found && $1 == "version" && $2 == "=" {print $3; exit}' | tr -d '"')
		elif command_exists wget; then
			version=$(wget -qO- "$url" 2>/dev/null | \
				awk '/^\[pkg\.rust\]/ {found=1} found && $1 == "version" && $2 == "=" {print $3; exit}' | tr -d '"')
		else
			echo "unknown"
			return
		fi
		
		if [[ -n "$version" ]]; then
			echo "$version"
		else
			echo "unknown"
		fi
	}
    
    local current_version latest_version
    current_version=$(get_rust_version)
    latest_version=$(get_latest_rust_version)
    
    echo -e "${CYAN}Rust version check:${NC}"
    echo -e "${GRAY}  Current: ${current_version}${NC}"
    echo -e "${GRAY}  Latest:  ${latest_version}${NC}"
    
    local needs_install=false
    
    # Check if Rust needs installation or update
    if [[ "$current_version" == "none" ]]; then
        echo -e "${YELLOW}Rust not found. Installing...${NC}"
        needs_install=true
    elif [[ "$latest_version" != "unknown" && "$current_version" != "$latest_version" ]]; then
        echo -e "${YELLOW}Newer Rust version available. Updating from $current_version to $latest_version...${NC}"
        needs_install=true
    elif ! command_exists rustup; then
        echo -e "${YELLOW}rustup not found. Reinstalling Rust toolchain...${NC}"
        needs_install=true
    else
        echo -e "${GREEN}Rust is up to date: $current_version${NC}"
        
        # Verify rustup has a default toolchain configured
        if ! rustup default >/dev/null 2>&1; then
            echo -e "${YELLOW}No default toolchain configured. Setting up...${NC}"
            rustup default stable
        fi
    fi
    
    # Install or update Rust
    if [[ "$needs_install" == "true" ]]; then
        # Clean up old installation if it exists
        if [[ -d "$HOME/.cargo" ]] || [[ -d "$HOME/.rustup" ]]; then
            echo -e "${YELLOW}Removing old Rust installation...${NC}"
            rm -rf "$HOME/.cargo" "$HOME/.rustup"
            echo -e "${GREEN}Old installation removed${NC}"
        fi
        
        echo -e "${YELLOW}Installing Rust toolchain...${NC}"
        
        # Download and install Rust
        if command_exists curl; then
            curl --proto '=https' --tlsv1.2 -sSf "$rustup_init_url" | \
                sh -s -- -y --default-toolchain stable --profile minimal
        elif command_exists wget; then
            wget -qO- "$rustup_init_url" | \
                sh -s -- -y --default-toolchain stable --profile minimal
        else
            write_error "Neither curl nor wget found. Cannot install Rust."
            write_end_step
            exit 1
        fi
        
        # Source the cargo environment
        source "$cargo_env"
        
        echo -e "${GREEN}Rust installed successfully${NC}"
        
        # Verify installation
        current_version=$(get_rust_version)
        echo -e "${GREEN}Installed version: $current_version${NC}"
    fi
    
    # Ensure rustup has a default toolchain
    if command_exists rustup; then
        if ! rustup default >/dev/null 2>&1; then
            echo -e "${YELLOW}Setting default toolchain to stable...${NC}"
            rustup default stable
        fi
    fi
    
    # Get target information
    local rust_target
    rust_target=$(get_rust_target "$PLATFORM")
    
    if [[ "$rust_target" == "unknown" ]]; then
        write_error "Unsupported platform: $PLATFORM"
        write_end_step
        exit 1
    fi
    
    local current_platform
    current_platform=$(get_current_platform)
    
    echo -e "${CYAN}Target platform: $PLATFORM ($rust_target)${NC}"
    echo -e "${CYAN}Current platform: $current_platform${NC}"
    
    # Install target and cross-compilation tools if needed
    if [[ "$PLATFORM" != "$current_platform" ]]; then
        echo -e "${YELLOW}Cross-compilation detected. Installing target: $rust_target${NC}"
        rustup target add "$rust_target"
        
        # Install cross-compilation tools for Linux
        install_linux_cross_tools "$rust_target"
    else
        echo -e "${GREEN}Native compilation (no cross-compilation needed)${NC}"
        # Still add the target to be explicit
        rustup target add "$rust_target"
    fi
    
    # Verify installation
    local rust_version cargo_version
    rust_version=$(rustc --version)
    cargo_version=$(cargo --version)
    echo -e "${GREEN}rustc: $rust_version${NC}"
    echo -e "${GREEN}cargo: $cargo_version${NC}"
    
    # List installed targets
    echo -e "${CYAN}Installed Rust targets:${NC}"
    rustup target list --installed | sed 's/^/  - /'
    
    # Save Rust info
    cat > "$ARTIFACTS_PATH/rust-info.json" << EOF
{
    "rustc": "$rust_version",
    "cargo": "$cargo_version",
    "target": "$rust_target",
    "platform": "$PLATFORM",
    "cross_compile": $([ "$PLATFORM" != "$current_platform" ] && echo "true" || echo "false"),
    "updated": $([ "$needs_install" == "true" ] && echo "true" || echo "false")
}
EOF
    
    write_end_step
}
