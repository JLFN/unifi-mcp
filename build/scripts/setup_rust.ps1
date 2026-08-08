
function Get-LatestRustVersion {
    try {
        $url = "https://static.rust-lang.org/dist/channel-rust-stable.toml"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing
        
        $content = $response.Content
        if ($content -is [byte[]]) {
            $content = [System.Text.Encoding]::UTF8.GetString($content)
        }
        
        # Parse version from TOML content (look for [pkg.rust] section)
        # Regex: Find [pkg.rust], match lazily until version =, capture version string (ignoring commit/date)
        if ($content -match '(?s)\[pkg\.rust\].*?version = "([^"]+)"') {
            # Return just the version part (e.g. 1.92.0) from "1.92.0 (hash date)"
            $fullVer = $matches[1]
            if ($fullVer -match "^(\d+\.\d+\.\d+)") {
                return $matches[1]
            }
            return $fullVer
        }
    }
    catch {
        Write-Warning "Could not check for latest Rust version: $_"
    }
    return $null
}

function Step-SetupRust {
    Write-Step "Setting up Rust Environment"
    
    try {
        $cargoPath = "$env:USERPROFILE\.cargo\bin"
        $needsInstall = $false
        
        # Check current version
        $currentVersion = $null
        if (Test-Path "$cargoPath\rustc.exe") {
            $env:Path = "$cargoPath;$env:Path"
            $verOutput = & rustc --version
            if ($verOutput -match "rustc (\d+\.\d+\.\d+)") {
                $currentVersion = $matches[1]
            }
        }
        
        # Check latest version
        $latestVersion = Get-LatestRustVersion
        
        Write-Host "Rust version check:" -ForegroundColor Cyan
        Write-Host "  Current: $(if ($currentVersion) { $currentVersion } else { 'Not installed' })" -ForegroundColor Gray
        Write-Host "  Latest:  $(if ($latestVersion) { $latestVersion } else { 'Unknown' })" -ForegroundColor Gray
        
        # Determine if we need to install or update
        if (-not $currentVersion) {
            Write-Host "Rust not found. Installing..." -ForegroundColor Yellow
            $needsInstall = $true
        }
        elseif ($latestVersion -and $currentVersion -ne $latestVersion) {
            Write-Host "Newer Rust version available. Updating from $currentVersion to $latestVersion..." -ForegroundColor Yellow
            $needsInstall = $true
        }
        else {
            Write-Host "Rust is up to date: $currentVersion" -ForegroundColor Green
        }
        
        if ($needsInstall) {
            if ($currentVersion) {
                # Update existing installation
                Write-Host "Updating Rust toolchain..." -ForegroundColor Gray
                & rustup update stable
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "rustup update failed (possibly corrupted toolchain). Attempting clean reinstall..."
                    & rustup toolchain uninstall stable 2>&1 | Out-Null
                    & rustup toolchain install stable
                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to update Rust (clean reinstall also failed)"
                    }
                    Write-Host "Clean reinstall succeeded." -ForegroundColor Green
                }
            }
            else {
                # New installation
                Write-Host "Installing Rust..." -ForegroundColor Yellow
                $rustupInit = "$env:TEMP\rustup-init.exe"
                try {
                    Write-Host "Downloading Rust installer..." -ForegroundColor Gray
                    Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile $rustupInit -UseBasicParsing
                    
                    Write-Host "Installing Rust (this may take several minutes)..." -ForegroundColor Gray
                    $process = Start-Process -FilePath $rustupInit -ArgumentList "-y", "--default-toolchain", "stable" -Wait -PassThru -NoNewWindow
                    
                    if ($process.ExitCode -ne 0) {
                        throw "Rust installation failed with exit code $($process.ExitCode)"
                    }
                }
                finally {
                    if (Test-Path $rustupInit) {
                        Remove-Item $rustupInit -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            
            # Refresh path
            $env:Path = "$cargoPath;$env:Path"
            Write-Host "[OK] Rust installed/updated successfully" -ForegroundColor Green
        }
        
        # Verify installation
        try {
            $rustVersion = & rustc --version
            $cargoVersion = & cargo --version
            Write-Host "[OK] $rustVersion" -ForegroundColor Green
            Write-Host "[OK] $cargoVersion" -ForegroundColor Green
            
            # Save Rust info
            @{
                rustc   = $rustVersion
                cargo   = $cargoVersion
                updated = $needsInstall
            } | ConvertTo-Json | Out-File (Join-Path $ArtifactsPath "rust-info.json")
            
        }
        catch {
            throw "Failed to verify Rust installation: $_"
        }
    }
    catch {
        Write-Error "Rust setup failed: $_"
        throw
    }
    finally {
        Write-EndStep
    }
}
