
function Step-ValidateEnvironment {
    Write-Step "Validating Environment"
    
    try {
        # Check required files
        $requiredFiles = @("Cargo.toml")
        foreach ($file in $requiredFiles) {
            $filePath = Join-Path $ProjectRoot $file
            if (-not (Test-Path $filePath)) {
                throw "Required file not found: $file"
            }
            Write-Host "[OK] Found: $file" -ForegroundColor Green
        }
        
        # Check directory structure
        $requiredDirs = @("src", "tests")
        foreach ($dir in $requiredDirs) {
            $dirPath = Join-Path $ProjectRoot $dir
            if (-not (Test-Path $dirPath)) {
                Write-Warning "Recommended directory not found: $dir"
            }
            else {
                Write-Host "[OK] Found: $dir/" -ForegroundColor Green
            }
        }
    }
    catch {
        Write-Error "Environment validation failed: $_"
        throw
    }
    finally {
        Write-EndStep
    }
}

function Step-Clean {
    Write-Step "Cleaning Build Artifacts"
    
    Push-Location $ProjectRoot
    try {
        # Clean specific targets, but protect the 'build' folder
        $cleanTargets = @(
            "target",
            "dist",
            ".pytest_cache",
            "*.egg-info",
            "__pycache__",
            "Cargo.lock"
        )
        
        foreach ($target in $cleanTargets) {
            Get-ChildItem -Path $target -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Cleaned: $target" -ForegroundColor Gray
        }
        
        # Clean specific files in build directory but preserve important files
        $buildDir = Join-Path $ProjectRoot "build"
        if (Test-Path $buildDir) {
            Write-Host "Cleaning build directory (preserving scripts and requirements)..." -ForegroundColor Gray
            
            # Files to preserve in build directory
            $preservePatterns = @(
                "*.ps1",           # PowerShell scripts
                "*.bat",           # Batch files
                "*.cmd",           # Command files
                "*.sh",            # Shell scripts
                "*requirements*.txt", # Requirements files
                "*.toml",          # Config files
                "*.yml",           # YAML files
                "*.yaml",          # YAML files
                "*.json",          # JSON config files
                "*.md",            # Documentation
                "*.txt"            # Text files (including requirements)
            )
            
            # Get all files in build directory
            $allFiles = Get-ChildItem -Path $buildDir -Recurse -Force -File -ErrorAction SilentlyContinue
            
            # Filter out files to preserve
            $filesToDelete = $allFiles | Where-Object {
                $file = $_
                $shouldPreserve = $false
                
                foreach ($pattern in $preservePatterns) {
                    if ($file.Name -like $pattern) {
                        $shouldPreserve = $true
                        break
                    }
                }
                
                return -not $shouldPreserve
            }
            
            # Delete only the files we don't want to preserve
            foreach ($file in $filesToDelete) {
                try {
                    Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                    Write-Host "  Removed: $($file.Name)" -ForegroundColor DarkGray
                }
                catch {
                    Write-Warning "Could not remove: $($file.Name)"
                }
            }
            
            # Show preserved files
            $preservedFiles = Get-ChildItem -Path $buildDir -Recurse -Force -File -ErrorAction SilentlyContinue
            if ($preservedFiles.Count -gt 0) {
                Write-Host "  Preserved files:" -ForegroundColor Cyan
                foreach ($file in $preservedFiles) {
                    Write-Host "    - $($file.Name)" -ForegroundColor Green
                }
            }
            
            Write-Host "[OK] Cleaned build directory (preserved important files)" -ForegroundColor Gray
        }
        
        # Clean Cargo specifically
        if (Test-Command "cargo") {
            Write-Host "Running cargo clean..." -ForegroundColor Gray
            & cargo clean
        }
        
        Write-Host "[OK] Clean completed" -ForegroundColor Green
        
    }
    catch {
        Write-Error "Clean failed: $_"
        throw
    }
    finally {
        Pop-Location
        Write-EndStep
    }
}

function Step-Build {
    Write-Step "Building Rust Extension"
    
    Push-Location $ProjectRoot
    try {
        # Set build environment
        if ($Native) {
            $env:RUSTFLAGS = "-C target-cpu=native"
            Write-Host "  Using native CPU optimizations" -ForegroundColor Cyan
        }
        else {
            $env:RUSTFLAGS = ""
        }
        $env:RUST_BACKTRACE = if ($Verbose) { "full" } else { "1" }
        
        # Verify maturin is available
        if (-not (Test-Path $MaturinExe)) {
            throw "Maturin not found: $MaturinExe"
        }
        
        $maturinVersion = & $MaturinExe --version
        Write-Host "[OK] Using: $maturinVersion" -ForegroundColor Green
        
        Write-Host "[OK] Environment configured" -ForegroundColor Green
        Write-Host "  RUSTFLAGS: $env:RUSTFLAGS" -ForegroundColor Gray
        Write-Host "  RUST_BACKTRACE: $env:RUST_BACKTRACE" -ForegroundColor Gray
        
    }
    catch {
        Write-Error "Build setup failed: $_"
        throw
    }
    finally {
        Pop-Location
        Write-EndStep
    }
}

function Step-CreateWheel {
    Write-Step "Creating Python Wheel"
    
    Push-Location $ProjectRoot
    try {
        # Build arguments
        $buildArgs = @("build")
        
        if ($Configuration -eq "Release") {
            $buildArgs += "--release"
        }
        
        $buildArgs += "--strip"  # Strip debug symbols for smaller wheels
        
        if ($Verbose) {
            $buildArgs += "--verbose"
        }
        
        Write-Host "Building wheel with: maturin $($buildArgs -join ' ')" -ForegroundColor Gray
        
        $buildStart = Get-Date
        & $MaturinExe @buildArgs
        $buildDuration = (Get-Date) - $buildStart
        
        if ($LASTEXITCODE -ne 0) {
            throw "Maturin build failed with exit code: $LASTEXITCODE"
        }
        
        Write-Host "[OK] Wheel built successfully in $($buildDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        
        # List created wheels
        if (Test-Path $WheelsDir) {
            $wheels = Get-ChildItem -Path "$WheelsDir\*.whl"
            Write-Host "Created wheels:" -ForegroundColor Cyan
            foreach ($wheel in $wheels) {
                $size = [math]::Round($wheel.Length / 1MB, 2)
                Write-Host "  - $($wheel.Name) ($size MB)" -ForegroundColor Gray
            }
        }
        
    }
    catch {
        Write-Error "Wheel creation failed: $_"
        throw
    }
    finally {
        Pop-Location
        Write-EndStep
    }
}

function Step-InstallWheel {
    Write-Step "Installing RCLIENT Wheel"
    
    Push-Location $ProjectRoot
    try {
        # Find the latest wheel
        if (-not (Test-Path $WheelsDir)) {
            throw "Wheels directory not found: $WheelsDir"
        }
        
        $wheels = Get-ChildItem -Path "$WheelsDir\*.whl" | Sort-Object LastWriteTime -Descending
        if ($wheels.Count -eq 0) {
            throw "No wheel files found in $WheelsDir"
        }
        
        $latestWheel = $wheels[0]
        Write-Host "Installing wheel: $($latestWheel.Name)" -ForegroundColor Cyan
        
        # Install the wheel with force-reinstall (this will handle existing installations automatically)
        Write-Host "Installing/reinstalling wheel: $($latestWheel.Name)" -ForegroundColor Gray
        & $PythonExe -m pip install $latestWheel.FullName --force-reinstall --no-deps --quiet
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install wheel: $($latestWheel.Name)"
        }
        
        # Verify installation
        $testScript = @"
try:
    import rclient
    version = getattr(rclient, '__version__', 'unknown')
    location = getattr(rclient, '__file__', 'unknown')
    print('[OK] RCLIENT {0} installed successfully'.format(version))
    print('Location: {0}'.format(location))
except ImportError as e:
    print('[ERROR] Failed to import RCLIENT: {0}'.format(e))
    exit(1)
"@
        
        $result = & $PythonExe -c $testScript
        if ($LASTEXITCODE -ne 0) {
            throw "RCLIENT installation verification failed"
        }
        
        Write-Host $result -ForegroundColor Green
        
    }
    catch {
        Write-Error "Wheel installation failed: $_"
        throw
    }
    finally {
        Pop-Location
        Write-EndStep
    }
}

function Step-RunTests {
    Write-Step "Running Test Suite"
    
    Push-Location $ProjectRoot
    try {
        # Clean up existing pytest temp directories in system temp
        $userTemp = "$env:LOCALAPPDATA\Temp"
        $pytestTempPattern = "pytest-of-*"
        Get-ChildItem -Path $userTemp -Filter $pytestTempPattern -Directory -ErrorAction SilentlyContinue | 
        ForEach-Object { 
            try { 
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Cleaned up system temp: $($_.Name)" -ForegroundColor Gray
            }
            catch { 
                Write-Warning "Could not clean system temp: $($_.Name)"
            }
        }

        $testsDir = "tests"
        if (-not (Test-Path $testsDir)) {
            Write-Warning "Tests directory not found: $testsDir"
            Add-TestResult -TestName "Test Discovery" -Status "skipped" -Message "No tests directory found"
            return
        }
        
        # Discover test files
        $testFiles = Get-ChildItem -Path $testsDir -Filter "test_*.py" -Recurse
        Write-Host "Discovered $($testFiles.Count) test files:" -ForegroundColor Cyan
        foreach ($file in $testFiles) {
            Write-Host "  - $($file.Name)" -ForegroundColor Gray
        }
        
        if ($testFiles.Count -eq 0) {
            Write-Warning "No test files found"
            Add-TestResult -TestName "Test Discovery" -Status "skipped" -Message "No test files found"
            return
        }
        
        # Set custom temp directory for pytest (pytest will create it automatically)
        $customTempDir = Join-Path $ProjectRoot "pytest-temp"
        
        # Prepare pytest arguments
        $pytestArgs = @(
            $testsDir,
            "-v",
            "--tb=short",
            "--strict-markers",
            "--basetemp=$customTempDir"  # pytest creates this automatically
        )
        
        # Add JSON report if pytest-json-report is available
        try {
            & $PythonExe -c "import pytest_jsonreport" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $pytestArgs += "--json-report"
                $pytestArgs += "--json-report-file=$OutputPath\test-report.json"
            }
        }
        catch {}
        
        # Add HTML report if pytest-html is available
        try {
            & $PythonExe -c "import pytest_html" 2>$null
            if ($LASTEXITCODE -eq 0) {
                $pytestArgs += "--html=$OutputPath\test-report.html"
                $pytestArgs += "--self-contained-html"
            }
        }
        catch {}
        
        if ($Coverage) {
            $pytestArgs += @(
                "--cov=rclient",
                "--cov-report=html:$OutputPath\coverage-html",
                "--cov-report=xml:$OutputPath\coverage.xml",
                "--cov-report=term-missing"
            )
        }
        
        if ($FailFast) {
            $pytestArgs += "-x"  # Stop on first failure
        }
        
        # Disable parallel execution to avoid temp directory permission issues
        # Comment out xdist to run tests sequentially
        # try {
        #     & $PythonExe -c "import xdist" 2>$null
        #     if ($LASTEXITCODE -eq 0) {
        #         $pytestArgs += "-n"
        #         $pytestArgs += "auto"  # Use all available cores
        #     }
        # } catch {}
        
        Write-Host "Running pytest with: $($pytestArgs -join ' ')" -ForegroundColor Gray
        
        $testStart = Get-Date
        & $PythonExe -m pytest @pytestArgs
        $testExitCode = $LASTEXITCODE
        $testDuration = (Get-Date) - $testStart
        
        Write-Host "[OK] Tests completed in $($testDuration.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        
        # Parse test results if JSON report exists
        $testReportPath = Join-Path $OutputPath "test-report.json"
        if (Test-Path $testReportPath) {
            try {
                $testReport = Get-Content $testReportPath | ConvertFrom-Json
                # Fix: Handle null/empty test result values properly
                $Global:TestResults.Total = if ($testReport.summary.total) { $testReport.summary.total } else { 0 }
                $Global:TestResults.Passed = if ($testReport.summary.passed) { $testReport.summary.passed } else { 0 }
                $Global:TestResults.Failed = if ($testReport.summary.failed) { $testReport.summary.failed } else { 0 }
                $Global:TestResults.Skipped = if ($testReport.summary.skipped) { $testReport.summary.skipped } else { 0 }
                
                Write-Host "Test Results:" -ForegroundColor Cyan
                Write-Host "  Total: $($Global:TestResults.Total)" -ForegroundColor White
                Write-Host "  Passed: $($Global:TestResults.Passed)" -ForegroundColor Green
                Write-Host "  Failed: $($Global:TestResults.Failed)" -ForegroundColor $(if ($Global:TestResults.Failed -eq 0) { 'Green' } else { 'Red' })
                Write-Host "  Skipped: $($Global:TestResults.Skipped)" -ForegroundColor Yellow
                
            }
            catch {
                Write-Warning "Could not parse test report: $_"
            }
        }
        
        # Clean up custom temp directory after tests
        if (Test-Path $customTempDir) {
            Remove-Item $customTempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Cleaned up pytest temp directory" -ForegroundColor Gray
        }
        
        # Handle test results
        if ($testExitCode -eq 0) {
            Write-Host "[OK] All tests passed!" -ForegroundColor Green
        }
        elseif ($testExitCode -eq 5) {
            Write-Warning "No tests were collected"
        }
        else {
            Write-Error "Tests failed with exit code: $testExitCode"
            if ($FailFast) {
                throw "Tests failed and fail-fast is enabled"
            }
        }
        
    }
    catch {
        Write-Error "Test execution failed: $_"
        throw
    }
    finally {
        Pop-Location
        Write-EndStep
    }
}

function Step-CollectArtifacts {
    Write-Step "Collecting Artifacts"
    
    try {
        # Copy wheels
        if (Test-Path $WheelsDir) {
            Get-ChildItem -Path "$WheelsDir\*.whl" | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $ArtifactsPath -Force
                Write-Host "[OK] Collected: $($_.Name)" -ForegroundColor Green
            }
        }
        
        # Copy test reports
        $reports = @("test-report.html", "test-report.json", "coverage.xml")
        foreach ($report in $reports) {
            $reportPath = Join-Path $OutputPath $report
            if (Test-Path $reportPath) {
                Copy-Item -Path $reportPath -Destination $ArtifactsPath -Force
                Write-Host "[OK] Collected: $report" -ForegroundColor Green
            }
        }
        
        # Copy coverage HTML report
        $coverageHtml = Join-Path $OutputPath "coverage-html"
        if (Test-Path $coverageHtml) {
            Copy-Item -Path $coverageHtml -Destination $ArtifactsPath -Recurse -Force
            Write-Host "[OK] Collected: coverage-html/" -ForegroundColor Green
        }
        
        # Create build manifest
        $manifest = @{
            BuildTime     = $Global:BuildStartTime.ToString("yyyy-MM-dd HH:mm:ss")
            Configuration = $Configuration
            Platform      = $Platform
            PythonVersion = $PythonVersion
            TestResults   = $Global:TestResults
            Artifacts     = Get-ChildItem -Path $ArtifactsPath -File | ForEach-Object { $_.Name }
        }
        
        $manifest | ConvertTo-Json -Depth 5 | Out-File (Join-Path $ArtifactsPath "build-manifest.json")
        Write-Host "[OK] Build manifest created" -ForegroundColor Green
        
    }
    catch {
        Write-Error "Artifact collection failed: $_"
        throw
    }
    finally {
        Write-EndStep
    }
}

function Step-GenerateReport {
    Write-Step "Generating Build Report"
    
    try {
        $duration = (Get-Date) - $Global:BuildStartTime
        $durationStr = "{0:hh\:mm\:ss}" -f $duration
        
        $buildStatus = if ($Global:TestResults.Failed -eq 0) { "BUILD SUCCESSFUL" } else { "BUILD FAILED" }
        
        $reportParams = @{
            BuildTime     = $Global:BuildStartTime.ToString("yyyy-MM-dd HH:mm:ss")
            Duration      = $durationStr
            Configuration = $Configuration
            Platform      = $Platform
            TestResults   = $Global:TestResults
            BuildStatus   = $buildStatus
            Artifacts     = Get-ChildItem -Path $ArtifactsPath -File | ForEach-Object { $_.Name }
        }
        
        $reportContent = @"
# RCLIENT Build Report

**Build Time:** $($reportParams.BuildTime)  
**Duration:** $($reportParams.Duration)  
**Configuration:** $($reportParams.Configuration)  
**Platform:** $($reportParams.Platform)  

## Test Results
- **Total Tests:** $($reportParams.TestResults.Total)
- **Passed:** $($reportParams.TestResults.Passed)
- **Failed:** $($reportParams.TestResults.Failed)
- **Skipped:** $($reportParams.TestResults.Skipped)

## Build Status
$($reportParams.BuildStatus)

## Artifacts
$($reportParams.Artifacts -join "`n- ")

---
*Generated by RCLIENT CI/CD Pipeline (PowerShell Edition)*
"@
        
        $reportPath = Join-Path $ArtifactsPath "BUILD-REPORT.md"
        $reportContent | Out-File $reportPath
        
        Write-Host ""
        Write-Host $reportContent -ForegroundColor Cyan
        Write-Host ""
        
    }
    catch {
        Write-Error "Report generation failed: $_"
        throw
    }
    finally {
        Write-EndStep
    }
}
