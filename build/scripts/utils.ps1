
# Logging functions
function Write-Section {
    param([string]$Title)
    $line = "=" * 80
    Write-Host $line -ForegroundColor Blue
    Write-Host "  $Title" -ForegroundColor White
    Write-Host $line -ForegroundColor Blue
}

function Write-Step {
    param([string]$Message)
    Write-Host "::group::$Message" -ForegroundColor Cyan
    Write-Host "> $Message" -ForegroundColor Green
}

function Write-EndStep {
    Write-Host "::endgroup::" -ForegroundColor Cyan
}

function Write-Warning {
    param([string]$Message)
    Write-Host "::warning::$Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "::error::$Message" -ForegroundColor Red
}

function Write-Notice {
    param([string]$Message)
    Write-Host "::notice::$Message" -ForegroundColor Blue
}

function Add-TestResult {
    param(
        [string]$TestName,
        [string]$Status,
        [string]$Message = "",
        [double]$Duration = 0
    )
    
    $Global:TestResults.Total++
    switch ($Status.ToLower()) {
        "passed" { $Global:TestResults.Passed++ }
        "failed" { 
            $Global:TestResults.Failed++
            $Global:TestResults.Errors += @{
                Test     = $TestName
                Message  = $Message
                Duration = $Duration
            }
        }
        "skipped" { $Global:TestResults.Skipped++ }
    }
}

# Utility function to check if command exists
function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

# Environment detection
function Get-EnvironmentInfo {
    $info = @{
        OS         = "$env:OS $env:PROCESSOR_ARCHITECTURE"
        PowerShell = $PSVersionTable.PSVersion.ToString()
        WorkingDir = $PWD.Path
        User       = $env:USERNAME
        Timestamp  = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
    }
    
    try {
        $info.Git = (git --version 2>$null) -replace "git version ", ""
    }
    catch {
        $info.Git = "Not installed"
    }
    
    return $info
}
