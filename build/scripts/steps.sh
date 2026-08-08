#!/bin/bash

step_validate_environment() {
    write_step "Validating Environment"
    
    local required_files=("Cargo.toml")
    local required_dirs=("src" "tests")
    
    # Check required files
    for file in "${required_files[@]}"; do
        local file_path="$PROJECT_ROOT/$file"
        if [[ ! -f "$file_path" ]]; then
            write_error "Required file not found: $file"
            write_end_step
            exit 1
        fi
        echo -e "${GREEN}Found: $file${NC}"
    done
    
    # Check directory structure
    for dir in "${required_dirs[@]}"; do
        local dir_path="$PROJECT_ROOT/$dir"
        if [[ ! -d "$dir_path" ]]; then
            write_warning "Recommended directory not found: $dir"
        else
            echo -e "${GREEN}Found: $dir/${NC}"
        fi
    done
    
    write_end_step
}

step_clean() {
    write_step "Cleaning Build Artifacts"
    
    cd "$PROJECT_ROOT"
    
    # Clean specific targets, but protect important files
    local clean_targets=(
        "target"
        "dist"
        ".pytest_cache"
        "*.egg-info"
        "__pycache__"
    )
    
    for target in "${clean_targets[@]}"; do
        find . -name "$target" -type d -exec rm -rf {} + 2>/dev/null || true
        find . -name "$target" -type f -delete 2>/dev/null || true
        echo -e "${GRAY}Cleaned: $target${NC}"
    done
    
    # Clean only specific build artifacts, not the entire build directory
    local build_artifacts=(
        "Cargo.lock"
        "*.pyc"
        "*.pyo"
        "*.pyd"
        ".coverage"
        ".tox"
        ".cache"
    )
    
    for artifact in "${build_artifacts[@]}"; do
        find . -name "$artifact" -type f -delete 2>/dev/null || true
        echo -e "${GRAY}Cleaned: $artifact${NC}"
    done
    
    # Clean specific temporary directories only
    local temp_dirs=(
        "pytest-temp"
        ".mypy_cache"
        ".ruff_cache"
        "htmlcov"
    )
    
    for temp_dir in "${temp_dirs[@]}"; do
        if [[ -d "$temp_dir" ]]; then
            rm -rf "$temp_dir"
            echo -e "${GRAY}Cleaned: $temp_dir/${NC}"
        fi
    done
    
    # Clean Cargo specifically
    if command_exists cargo; then
        echo -e "${GRAY}Running cargo clean...${NC}"
        cargo clean
    fi
    
    # Clean only output directories we created
    if [[ -d "$OUTPUT_PATH" ]]; then
        echo -e "${GRAY}Cleaning output directory: $OUTPUT_PATH${NC}"
        rm -rf "$OUTPUT_PATH"/*
    fi
    
    echo -e "${GREEN}Clean completed${NC}"
    
    write_end_step
}

step_build() {
    write_step "Building Rust Extension"
    
    cd "$PROJECT_ROOT"
    
    # Set build environment
    local current_platform
    current_platform=$(get_current_platform)
    
    if [[ "$PLATFORM" == "$current_platform" ]]; then
        if [[ "$NATIVE" == "true" ]]; then
            export RUSTFLAGS="-C target-cpu=native"
            echo -e "${CYAN}Using native CPU optimizations${NC}"
        else
            export RUSTFLAGS=""
        fi
    else
        echo -e "${YELLOW}Cross-compilation detected: skipping native optimizations${NC}"
        export RUSTFLAGS=""
    fi

    # Fix for boring-sys2 on Arch Linux ARM (missing/mismatched syscall definitions)
    if [[ "$PLATFORM" == "arm64" ]]; then
        echo -e "${YELLOW}Debugging: Checking system syscall definitions...${NC}"
        echo "#include <sys/syscall.h>
#include <stdio.h>
int main() {
#ifdef __NR_getrandom
    printf(\"System __NR_getrandom: %d\\n\", __NR_getrandom);
#else
    printf(\"System __NR_getrandom: UNDEFINED\\n\");
#endif
    return 0;
}" > check_syscall.c
        
        if gcc check_syscall.c -o check_syscall; then
            ./check_syscall
            rm check_syscall check_syscall.c
        else
            echo -e "${RED}Failed to compile syscall check${NC}"
        fi

        # Force the correct syscall number for aarch64 (278)
        # We use -U to ensure we override any bad system header value
        export CFLAGS="${CFLAGS:-} -U__NR_getrandom -D__NR_getrandom=278"
        
        # Explicitly set C/C++ compiler for cross-compilation to ensure boring-sys2 matches target
        export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
        export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
        export AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar
        
        # Aggressive override: Set global CC/CXX/AR to force cross-compilation for all crates
        # This is safe here because we are inside the 'arm64' platform block
        export CC=aarch64-linux-gnu-gcc
        export CXX=aarch64-linux-gnu-g++
        export AR=aarch64-linux-gnu-ar
        
        # Ensure cmake-rs finds the toolchain file for cross-compilation
        export CMAKE_TOOLCHAIN_FILE="$PROJECT_ROOT/cmake-toolchain-aarch64.cmake"
        export CMAKE_TOOLCHAIN_FILE_aarch64_unknown_linux_gnu="$PROJECT_ROOT/cmake-toolchain-aarch64.cmake"
    fi
    
    export RUST_BACKTRACE=$( [[ "$VERBOSE" == "true" ]] && echo "full" || echo "1" )
    
    # Verify maturin is available
    if [[ ! -f "$MATURIN_BIN" ]]; then
        write_error "Maturin not found: $MATURIN_BIN"
        write_end_step
        exit 1
    fi
    
    local maturin_version
    maturin_version=$("$MATURIN_BIN" --version)
    echo -e "${GREEN}Using: $maturin_version${NC}"
    
    echo -e "${GREEN}Environment configured${NC}"
    echo -e "${GRAY}  RUSTFLAGS: $RUSTFLAGS${NC}"
    echo -e "${GRAY}  RUST_BACKTRACE: $RUST_BACKTRACE${NC}"
    
    write_end_step
}

step_create_wheel() {
    write_step "Creating Python Wheel"
    
    cd "$PROJECT_ROOT"
    
    # Get target information
    local rust_target
    rust_target=$(get_rust_target "$PLATFORM")
    
    # Build arguments
    local build_args=("build")
    
    if [[ "$CONFIGURATION" == "Release" ]]; then
        build_args+=("--release")
    fi
    
    build_args+=("--strip")  # Strip debug symbols for smaller wheels
    
    # Always specify target for clarity
    build_args+=("--target" "$rust_target")
    
    local current_platform
    current_platform=$(get_current_platform)
    
    if [[ "$PLATFORM" != "$current_platform" ]]; then
        echo -e "${CYAN}Cross-compiling from $current_platform to $PLATFORM ($rust_target)${NC}"
    else
        echo -e "${CYAN}Native compilation for $PLATFORM ($rust_target)${NC}"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        build_args+=("--verbose")
    fi
    
    echo -e "${GRAY}Building wheel with: maturin ${build_args[*]}${NC}"
    
    local build_start build_end build_duration
    build_start=$(date +%s)
    "$MATURIN_BIN" "${build_args[@]}"
    build_end=$(date +%s)
    build_duration=$((build_end - build_start))
    
    echo -e "${GREEN}Wheel built successfully in ${build_duration}s${NC}"
    
    # List created wheels
    if [[ -d "$WHEELS_DIR" ]]; then
        echo -e "${CYAN}Created wheels:${NC}"
        find "$WHEELS_DIR" -name "*.whl" -exec sh -c '
            for wheel; do
                size=$(du -h "$wheel" | cut -f1)
                echo "  - $(basename "$wheel") ($size)"
            done
        ' sh {} +
    fi
    
    write_end_step
}

step_install_wheel() {
    write_step "Installing RCLIENT Wheel"
    
    cd "$PROJECT_ROOT"
    
    # Find the latest wheel
    if [[ ! -d "$WHEELS_DIR" ]]; then
        write_error "Wheels directory not found: $WHEELS_DIR"
        write_end_step
        exit 1
    fi
    
    local latest_wheel
    latest_wheel=$(find "$WHEELS_DIR" -name "*.whl" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -z "$latest_wheel" ]]; then
        write_error "No wheel files found in $WHEELS_DIR"
        write_end_step
        exit 1
    fi
    
    echo -e "${CYAN}Installing wheel: $(basename "$latest_wheel")${NC}"
    
    # Install the wheel with force-reinstall
    echo -e "${GRAY}Installing/reinstalling wheel: $(basename "$latest_wheel")${NC}"
    "$PYTHON_BIN" -m pip install "$latest_wheel" --force-reinstall --no-deps --quiet
    
    # Verify installation
    local test_result
    test_result=$("$PYTHON_BIN" -c "
try:
    import rclient
    version = getattr(rclient, '__version__', 'unknown')
    location = getattr(rclient, '__file__', 'unknown')
    print('RCLIENT {0} installed successfully'.format(version))
    print('Location: {0}'.format(location))
except ImportError as e:
    print('Failed to import RCLIENT: {0}'.format(e))
    exit(1)
" 2>&1)
    
    echo -e "${GREEN}$test_result${NC}"
    
    write_end_step
}

step_run_tests() {
    write_step "Running Test Suite"
    
    cd "$PROJECT_ROOT"
    
    # Clean up existing pytest temp directories
    find /tmp -name "pytest-of-*" -type d -user "$(whoami)" -exec rm -rf {} + 2>/dev/null || true
    
    local tests_dir="tests"
    if [[ ! -d "$tests_dir" ]]; then
        write_warning "Tests directory not found: $tests_dir"
        add_test_result "Test Discovery" "skipped" "No tests directory found"
        write_end_step
        return
    fi
    
    # Discover test files
    local test_files
    readarray -t test_files < <(find "$tests_dir" -name "test_*.py" -type f)
    
    echo -e "${CYAN}Discovered ${#test_files[@]} test files:${NC}"
    for file in "${test_files[@]}"; do
        echo -e "${GRAY}  - $(basename "$file")${NC}"
    done
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        write_warning "No test files found"
        add_test_result "Test Discovery" "skipped" "No test files found"
        write_end_step
        return
    fi
    
    # Set custom temp directory for pytest
    local custom_temp_dir="$PROJECT_ROOT/pytest-temp"
    
    # Prepare pytest arguments
    local pytest_args=(
        "$tests_dir"
        "-v"
        "--tb=short"
        "--strict-markers"
        "--basetemp=$custom_temp_dir"
    )
    
    # Add JSON report if pytest-json-report is available
    if "$PYTHON_BIN" -c "import pytest_jsonreport" 2>/dev/null; then
        pytest_args+=(
            "--json-report"
            "--json-report-file=$OUTPUT_PATH/test-report.json"
        )
    fi
    
    # Add HTML report if pytest-html is available
    if "$PYTHON_BIN" -c "import pytest_html" 2>/dev/null; then
        pytest_args+=(
            "--html=$OUTPUT_PATH/test-report.html"
            "--self-contained-html"
        )
    fi
    
    if [[ "$COVERAGE" == "true" ]]; then
        pytest_args+=(
            "--cov=rclient"
            "--cov-report=html:$OUTPUT_PATH/coverage-html"
            "--cov-report=xml:$OUTPUT_PATH/coverage.xml"
            "--cov-report=term-missing"
        )
    fi
    
    if [[ "$FAIL_FAST" == "true" ]]; then
        pytest_args+=("-x")  # Stop on first failure
    fi
    
    echo -e "${GRAY}Running pytest with: ${pytest_args[*]}${NC}"
    
    local test_start test_end test_duration test_exit_code
    test_start=$(date +%s)
    "$PYTHON_BIN" -m pytest "${pytest_args[@]}" || test_exit_code=$?
    test_end=$(date +%s)
    test_duration=$((test_end - test_start))
    
    echo -e "${GREEN}Tests completed in ${test_duration}s${NC}"
    
    # Parse test results if JSON report exists
    local test_report_path="$OUTPUT_PATH/test-report.json"
    if [[ -f "$test_report_path" ]]; then
        if command_exists jq; then
            local summary
            summary=$(jq -r '.summary // {}' "$test_report_path" 2>/dev/null)
            TEST_RESULTS[total]=$(echo "$summary" | jq -r '.total // 0')
            TEST_RESULTS[passed]=$(echo "$summary" | jq -r '.passed // 0')
            TEST_RESULTS[failed]=$(echo "$summary" | jq -r '.failed // 0')
            TEST_RESULTS[skipped]=$(echo "$summary" | jq -r '.skipped // 0')
        else
            # Fallback parsing without jq
            local total passed failed skipped
            total=$(grep -o '"total":[^,}]*' "$test_report_path" | cut -d: -f2 | tr -d ' ' || echo 0)
            passed=$(grep -o '"passed":[^,}]*' "$test_report_path" | cut -d: -f2 | tr -d ' ' || echo 0)
            failed=$(grep -o '"failed":[^,}]*' "$test_report_path" | cut -d: -f2 | tr -d ' ' || echo 0)
            skipped=$(grep -o '"skipped":[^,}]*' "$test_report_path" | cut -d: -f2 | tr -d ' ' || echo 0)
            
            TEST_RESULTS[total]=${total:-0}
            TEST_RESULTS[passed]=${passed:-0}
            TEST_RESULTS[failed]=${failed:-0}
            TEST_RESULTS[skipped]=${skipped:-0}
        fi
        
        echo -e "${CYAN}Test Results:${NC}"
        echo -e "${WHITE}  Total: ${TEST_RESULTS[total]}${NC}"
        echo -e "${GREEN}  Passed: ${TEST_RESULTS[passed]}${NC}"
        echo -e "$( [[ ${TEST_RESULTS[failed]} -eq 0 ]] && echo "${GREEN}" || echo "${RED}" )  Failed: ${TEST_RESULTS[failed]}${NC}"
        echo -e "${YELLOW}  Skipped: ${TEST_RESULTS[skipped]}${NC}"
    fi
    
    # Clean up custom temp directory after tests
    [[ -d "$custom_temp_dir" ]] && rm -rf "$custom_temp_dir"
    echo -e "${GRAY}Cleaned up pytest temp directory${NC}"
    
    # Handle test results
    if [[ ${test_exit_code:-0} -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
    elif [[ ${test_exit_code:-0} -eq 5 ]]; then
        write_warning "No tests were collected"
    else
        write_error "Tests failed with exit code: ${test_exit_code:-1}"
        if [[ "$FAIL_FAST" == "true" ]]; then
            write_end_step
            exit 1
        fi
    fi
    
    write_end_step
}

step_collect_artifacts() {
    write_step "Collecting Build Artifacts"
    
    # Copy wheels
    if [[ -d "$WHEELS_DIR" ]]; then
        find "$WHEELS_DIR" -name "*.whl" -exec cp {} "$ARTIFACTS_PATH/" \;
        for wheel in "$WHEELS_DIR"/*.whl; do
            [[ -f "$wheel" ]] && echo -e "${GREEN}Collected: $(basename "$wheel")${NC}"
        done
    fi
    
    # Copy test reports
    local reports=(
        "test-report.html"
        "test-report.json"
        "coverage.xml"
    )
    
    for report in "${reports[@]}"; do
        local report_path="$OUTPUT_PATH/$report"
        if [[ -f "$report_path" ]]; then
            cp "$report_path" "$ARTIFACTS_PATH/"
            echo -e "${GREEN}Collected: $report${NC}"
        fi
    done
    
    # Copy coverage HTML report
    local coverage_html="$OUTPUT_PATH/coverage-html"
    if [[ -d "$coverage_html" ]]; then
        cp -r "$coverage_html" "$ARTIFACTS_PATH/"
        echo -e "${GREEN}Collected: coverage-html/${NC}"
    fi
    
    # Create build manifest
    local artifacts_list
    artifacts_list=$(find "$ARTIFACTS_PATH" -type f -printf '{"name": "%f", "size": %s, "modified": "%TY-%Tm-%Td %TH:%TM:%TS"}\n' 2>/dev/null | 
                    sed 's/$/,/' | sed '$s/,$//' | sed '1i[' | sed '$a]')
    
    cat > "$ARTIFACTS_PATH/build-manifest.json" << EOF
{
    "build_time": "$BUILD_START_TIME",
    "configuration": "$CONFIGURATION",
    "platform": "$PLATFORM",
    "python_version": "$PYTHON_VERSION",
    "test_results": {
        "total": ${TEST_RESULTS[total]},
        "passed": ${TEST_RESULTS[passed]},
        "failed": ${TEST_RESULTS[failed]},
        "skipped": ${TEST_RESULTS[skipped]}
    },
    "artifacts": ${artifacts_list:-[]}
}
EOF
    
    echo -e "${GREEN}Build manifest created${NC}"
    
    write_end_step
}

step_generate_report() {
    write_step "Generating Build Report"
    
    local build_end_epoch build_duration_seconds build_duration_formatted
    build_end_epoch=$(date +%s)
    build_duration_seconds=$((build_end_epoch - BUILD_START_EPOCH))
    build_duration_formatted=$(printf '%02d:%02d:%02d' $((build_duration_seconds/3600)) $((build_duration_seconds%3600/60)) $((build_duration_seconds%60)))
    
    local build_status
    if [[ ${TEST_RESULTS[failed]} -eq 0 ]]; then
        build_status="BUILD SUCCESSFUL"
    else
        build_status="BUILD FAILED"
    fi
    
    local artifacts_list
    artifacts_list=$(find "$ARTIFACTS_PATH" -type f -printf '- %f\n' 2>/dev/null | sort)
    
    cat > "$ARTIFACTS_PATH/BUILD-REPORT.md" << EOF
# RCLIENT Build Report

**Build Time:** $BUILD_START_TIME  
**Duration:** $build_duration_formatted  
**Configuration:** $CONFIGURATION  
**Platform:** $PLATFORM  

## Test Results
- **Total Tests:** ${TEST_RESULTS[total]}
- **Passed:** ${TEST_RESULTS[passed]}
- **Failed:** ${TEST_RESULTS[failed]}
- **Skipped:** ${TEST_RESULTS[skipped]}

## Build Status
$build_status

## Artifacts
$artifacts_list

---
*Generated by RCLIENT CI/CD Pipeline with Linux Cross-Compilation Support*
EOF
    
    echo -e "${CYAN}"
    cat "$ARTIFACTS_PATH/BUILD-REPORT.md"
    echo -e "${NC}"
    
    write_end_step
}
