#Requires -Version 5.1
<#
.SYNOPSIS
    Harnais de tests global pour le projet Arch + Hyprland.
.DESCRIPTION
    Lance Pester (PowerShell), shellcheck et bats (via Docker archlinux),
    plus validation des configs et dry-run de l'installateur.
#>
[CmdletBinding()]
param(
    [switch]$SkipDocker,
    [switch]$SkipPester
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Failed = 0
$Passed = 0

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Invoke-TestStep {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Host "`n>> $Name" -ForegroundColor Yellow
    try {
        & $Action
        Write-Host "[OK] $Name" -ForegroundColor Green
        $script:Passed++
    }
    catch {
        Write-Host "[FAIL] $Name : $_" -ForegroundColor Red
        $script:Failed++
    }
}

# --- 1. Génération rapport matériel (DryRun) ---
Write-TestHeader "Phase 1 - Analyse matérielle"
Invoke-TestStep "Génération hardware-report.json (DryRun)" {
    # Fichier temporaire : ne jamais écraser analyze\hardware-report.json (vrai rapport machine)
    $outPath = Join-Path $env:TEMP 'arch-test-hardware-report.json'
    & (Join-Path $ProjectRoot 'analyze\analyze-windows.ps1') -DryRun -OutputPath $outPath | Out-Null
    if (-not (Test-Path $outPath)) { throw "Fichier non généré" }
    $json = Get-Content $outPath -Raw | ConvertFrom-Json
    if ($json.schemaVersion -ne '1.0.0') { throw "schemaVersion invalide" }
    Remove-Item $outPath -Force -ErrorAction SilentlyContinue
}

# --- 2. Tests Pester ---
if (-not $SkipPester) {
    Write-TestHeader "Tests Pester"
    Invoke-TestStep "Exécution tests Pester" {
        Import-Module Pester -ErrorAction Stop
        $pesterResult = Invoke-Pester -Path (Join-Path $ProjectRoot 'tests\Pester') -PassThru -Quiet
        if ($pesterResult.FailedCount -gt 0) {
            throw "$($pesterResult.FailedCount) test(s) Pester échoué(s)"
        }
    }
}

# --- 3. Validation JSON configs ---
Write-TestHeader "Validation configurations"
Invoke-TestStep "waybar/config.json JSON valide" {
    Get-Content (Join-Path $ProjectRoot 'dotfiles\waybar\config.json') -Raw | ConvertFrom-Json | Out-Null
}
Invoke-TestStep "swaync/config.json JSON valide" {
    Get-Content (Join-Path $ProjectRoot 'dotfiles\swaync\config.json') -Raw | ConvertFrom-Json | Out-Null
}
Invoke-TestStep "hardware-report.schema.json JSON valide" {
    Get-Content (Join-Path $ProjectRoot 'analyze\hardware-report.schema.json') -Raw | ConvertFrom-Json | Out-Null
}

# --- 4. Tests Bash (Docker, WSL, ou runner portable) ---
Write-TestHeader "Tests Bash"
Invoke-TestStep "Tests bash (shellcheck + assertions)" {
    $projectWsl = $ProjectRoot -replace '\\', '/' -replace '^([A-Z]):', { "/mnt/$($_.Groups[1].Value.ToLower())" }
    $ran = $false

    if (-not $SkipDocker) {
        try {
            docker info 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $dockerCmd = "pacman -Sy --noconfirm shellcheck bats python jq 2>/dev/null; cd /project && find install configure dotfiles -name '*.sh' -print0 | xargs -0 shellcheck -e SC1091,SC2034 && bats tests/*.bats"
                docker run --rm -v "${ProjectRoot}:/project" -w /project archlinux:latest bash -c $dockerCmd
                if ($LASTEXITCODE -eq 0) { $ran = $true }
            }
        }
        catch {
            Write-Host "Docker indisponible..." -ForegroundColor DarkYellow
        }
    }

    if (-not $ran -and (Get-Command wsl -ErrorAction SilentlyContinue)) {
        $driveLetter = $ProjectRoot.Substring(0, 1).ToLower()
        $projectWsl = "/mnt/$driveLetter" + ($ProjectRoot.Substring(2) -replace '\\', '/')
        wsl bash -c "cd '$projectWsl' && chmod +x tests/run-bash-tests.sh && bash tests/run-bash-tests.sh"
        if ($LASTEXITCODE -eq 0) { $ran = $true }
    }

    if (-not $ran) {
        throw "Impossible d'exécuter les tests bash (Docker/WSL requis)"
    }
}

# --- 5. Dry-run installateur local (sans Docker) ---
Write-TestHeader "Dry-run installateur"
Invoke-TestStep "install.sh --dry-run via bash (WSL si dispo)" {
    $reportPath = Join-Path $ProjectRoot 'tests\fixtures\hardware-report.json'
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        $driveLetter = $ProjectRoot.Substring(0, 1).ToLower()
        $wslPath = "/mnt/$driveLetter" + ($ProjectRoot.Substring(2) -replace '\\', '/')
        $reportWsl = "$wslPath/tests/fixtures/hardware-report.json"
        wsl bash -c "cd '$wslPath' && DRY_RUN=1 bash install/install.sh --dry-run --disk nvme0n1 --user archuser --password test --report '$reportWsl'"
        if ($LASTEXITCODE -ne 0) { throw "install.sh dry-run échoué" }
    }
    else {
        Write-Host "WSL non disponible, test ignoré (couvert par run-bash-tests.sh)" -ForegroundColor DarkYellow
    }
}

# --- Résumé ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " RÉSUMÉ: $Passed réussis, $Failed échoués" -ForegroundColor $(if ($Failed -eq 0) { 'Green' } else { 'Red' })
Write-Host "========================================" -ForegroundColor Cyan

if ($Failed -gt 0) {
    exit 1
}
exit 0
