#Requires -Version 5.1
<#
.SYNOPSIS
    Utilitaire Windows — préparation et copie du projet vers clé USB.
.DESCRIPTION
    Commandes :
      prepare   Analyse le PC, valide le rapport, affiche le résumé
      copy-usb  Copie le projet sur une clé USB
      check     Vérifie que tout est prêt sans modifier
      all       prepare + copy-usb en une commande
.EXAMPLE
    .\arch-setup.ps1 prepare
    .\arch-setup.ps1 copy-usb -DriveLetter E
    .\arch-setup.ps1 all -DriveLetter E
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('prepare', 'copy-usb', 'check', 'all', 'help')]
    [string]$Action = 'help',

    [string]$DriveLetter,
    [string]$DestinationPath,
    [switch]$Force,
    [switch]$SkipAnalyze,
    [switch]$ListVolumes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = $PSScriptRoot
$AnalyzeScript = Join-Path $ProjectRoot 'analyze\analyze-windows.ps1'
$ReportPath = Join-Path $ProjectRoot 'analyze\hardware-report.json'
$SchemaPath = Join-Path $ProjectRoot 'analyze\hardware-report.schema.json'

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ReportObject {
    if (-not (Test-Path $ReportPath)) {
        throw ('Rapport absent: {0} - lancez: .\arch-setup.ps1 prepare' -f $ReportPath)
    }
    Get-Content $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Invoke-PrepareStep {
    Write-Step "Analyse matérielle"
    if (-not $SkipAnalyze) {
        if (-not (Test-IsAdmin)) {
            Write-Warning 'PowerShell non administrateur - BitLocker peut rester Unknown.'
            Write-Warning "Relancez en admin pour une analyse complète."
        }
        & $AnalyzeScript -OutputPath $ReportPath
    }
    else {
        Write-Host "Analyse ignorée (-SkipAnalyze), rapport existant conservé" -ForegroundColor DarkYellow
    }

    $report = Get-ReportObject

    Write-Step "Validation du rapport"
    if (-not $report.install.canInstall) {
        throw "Installation impossible: $($report.install.reason)"
    }
    Write-Host "[OK] Espace disque suffisant (~$($report.storage.disks[0].unallocatedGiB) GiB libres)" -ForegroundColor Green

    $bl = $report.security.bitlocker.status
    switch ($bl) {
        'On' {
            throw @"
BitLocker est ACTIF sur Windows.
Suspendez-le avant l'installation :
  Gérer BitLocker > Suspendre la protection
Ou PowerShell admin : Suspend-BitLocker -MountPoint 'C:' -RebootCount 1
"@
        }
        'Unknown' {
            Write-Warning 'Statut BitLocker inconnu - relancez en admin ou verifiez manuellement.'
        }
        default {
            Write-Host "[OK] BitLocker: $bl" -ForegroundColor Green
        }
    }

    Write-Host "[OK] Disque cible: $($report.storage.disks[$report.install.targetDisk].friendlyName)" -ForegroundColor Green
    Write-Host "[OK] Root suggéré: $($report.install.suggestedRootGiB) GiB" -ForegroundColor Green
    Write-Host ('[OK] Affichage: {0}x{1} @ {2} Hz (scale {3})' -f `
        $report.display.primary.width, $report.display.primary.height, `
        $report.display.primary.refreshHz, $report.display.primary.scale) -ForegroundColor Green

    Write-Step 'Prochaines etapes'
    @'

1. Flashez l ISO Arch sur une cle USB : https://archlinux.org/download/
2. Copiez ce projet sur la cle (branchez-la avant) :
     .\arch-setup.ps1 copy-usb
     # ou : .\arch-setup.ps1 copy-usb -ListVolumes
3. Bootez sur l ISO Arch, puis en root :
     ./arch-setup live

'@ | Write-Host
}

function Invoke-CheckStep {
    Write-Step "Vérifications"
    $ok = $true

    foreach ($path in @($AnalyzeScript, (Join-Path $ProjectRoot 'install\install.sh'), (Join-Path $ProjectRoot 'arch-setup'))) {
        if (Test-Path $path) {
            Write-Host "[OK] $(Split-Path -Leaf $path)" -ForegroundColor Green
        }
        else {
            Write-Host "[MANQUANT] $path" -ForegroundColor Red
            $ok = $false
        }
    }

    if (Test-Path $ReportPath) {
        try {
            $report = Get-ReportObject
            if ($report.install.canInstall) {
                Write-Host "[OK] hardware-report.json (canInstall=true)" -ForegroundColor Green
            }
            else {
                Write-Host "[FAIL] canInstall=false" -ForegroundColor Red
                $ok = $false
            }
            if ($report.security.bitlocker.status -eq 'On') {
                Write-Host "[FAIL] BitLocker actif" -ForegroundColor Red
                $ok = $false
            }
        }
        catch {
            Write-Host "[FAIL] Rapport JSON invalide: $_" -ForegroundColor Red
            $ok = $false
        }
    }
    else {
        Write-Host '[MANQUANT] hardware-report.json - lancez prepare' -ForegroundColor Yellow
        $ok = $false
    }

    if (-not $ok) { throw "Vérifications échouées" }
    Write-Host "`nTout est prêt pour copy-usb et l''installation." -ForegroundColor Green
}

function Get-CandidateUsbVolumes {
    $results = @()
    Get-Volume -ErrorAction SilentlyContinue | Where-Object {
        $_.DriveLetter -and ($_.DriveType -eq 'Removable' -or $_.DriveType -eq 'Fixed')
    } | ForEach-Object {
        $part = Get-Partition -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue
        $disk = $null
        if ($part) { $disk = Get-Disk -Number $part.DiskNumber -ErrorAction SilentlyContinue }
        $isUsb = ($_.DriveType -eq 'Removable') -or ($disk -and $disk.BusType -eq 'USB')
        if ($isUsb -or $_.DriveType -eq 'Removable') {
            $results += [PSCustomObject]@{
                DriveLetter = $_.DriveLetter
                Label       = $_.FileSystemLabel
                FreeGiB     = [math]::Round($_.SizeRemaining / 1GB, 1)
                TotalGiB    = [math]::Round($_.Size / 1GB, 1)
                Path        = ($_.DriveLetter.ToString() + ':\')
                Source      = 'volume'
            }
        }
    }
    return $results
}

function Get-UsbDisksWithoutLetter {
    $results = @()
    Get-Disk -ErrorAction SilentlyContinue | Where-Object {
        $_.BusType -eq 'USB' -and $_.OperationalStatus -eq 'Online'
    } | ForEach-Object {
        $diskNum = $_.Number
        Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue | Where-Object {
            -not $_.DriveLetter -and $_.PartitionNumber -gt 0
        } | ForEach-Object {
            $sizeGiB = [math]::Round($_.Size / 1GB, 1)
            $results += [PSCustomObject]@{
                DiskNumber  = $diskNum
                Partition   = $_.PartitionNumber
                Label       = $_.GptType
                FreeGiB     = $null
                TotalGiB    = $sizeGiB
                Path        = $null
                Source      = 'partition'
            }
        }
    }
    return $results
}

function Show-AvailableVolumes {
    Write-Host "`nLecteurs amovibles / USB detectes :" -ForegroundColor Yellow
    $volumes = @(Get-CandidateUsbVolumes)
    if ($volumes.Count -eq 0) {
        Write-Host "  (aucun lecteur avec lettre de lecteur)" -ForegroundColor DarkGray
    }
    else {
        $volumes | ForEach-Object {
            $label = if ($_.Label) { $_.Label } else { '(sans nom)' }
            Write-Host "  $($_.DriveLetter):  $label  - $($_.FreeGiB) Go libres / $($_.TotalGiB) Go" -ForegroundColor White
        }
    }
    $noLetter = @(Get-UsbDisksWithoutLetter)
    if ($noLetter.Count -gt 0) {
        Write-Host "`nPartitions USB sans lettre (branchez une clé ou assignez une lettre dans Gestion des disques) :" -ForegroundColor Yellow
        $noLetter | ForEach-Object {
            Write-Host "  Disque $($_.DiskNumber) partition $($_.Partition) - $($_.TotalGiB) Go" -ForegroundColor White
        }
        if (-not (Test-IsAdmin)) {
            Write-Host "  Relancez PowerShell en admin pour assigner une lettre automatiquement." -ForegroundColor DarkYellow
        }
    }
    if ($volumes.Count -eq 0 -and $noLetter.Count -eq 0) {
        Write-Host (@'

Aucune cle USB detectee.
  1. Branchez votre cle USB (ou la 2e cle si l ISO est sur une autre)
  2. Attendez que Windows l affiche dans l Explorateur
  3. Relancez : .\arch-setup.ps1 copy-usb

Alternative - copier vers un dossier local (puis recopier manuellement) :
  .\arch-setup.ps1 copy-usb -DestinationPath D:\backup-arch

'@) -ForegroundColor Cyan
    }
    else {
        $first = $volumes[0].DriveLetter
        Write-Host (@"

Usage :
  .\arch-setup.ps1 copy-usb -DriveLetter $first
  .\arch-setup.ps1 copy-usb

"@) -ForegroundColor Cyan
    }
}

function Get-DriveRoot {
    param([string]$Letter)
    return ($Letter.TrimEnd(':').ToUpper() + ':\')
}

function Get-ArchDestOnDrive {
    param([string]$Letter)
    return (Join-Path (Get-DriveRoot $Letter) 'arch')
}

function Try-AssignDriveLetter {
    param([int]$DiskNumber, [int]$PartitionNumber)
    if (-not (Test-IsAdmin)) { return $null }
    $used = Get-Volume | Where-Object DriveLetter | ForEach-Object { [int][char]$_.DriveLetter }
    foreach ($code in (68..90)) { # D-Z
        if ($used -notcontains $code) {
            $letter = [char]$code
            try {
                Set-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -NewDriveLetter $letter
                Start-Sleep -Seconds 1
                return [string]$letter
            }
            catch {
                return $null
            }
        }
    }
    return $null
}

function Resolve-CopyDestination {
    if ($DestinationPath) {
        $dest = $DestinationPath
        if (-not $dest.EndsWith('\arch') -and (Split-Path -Leaf $dest) -ne 'arch') {
            $dest = Join-Path $dest 'arch'
        }
        return $dest
    }

    $letter = $null
    if ($DriveLetter) {
        $letter = $DriveLetter.TrimEnd(':').ToUpper()
        if (-not (Test-Path (Get-DriveRoot $letter))) {
            Write-Host ('Lecteur {0}: introuvable.' -f $letter) -ForegroundColor Red
            Show-AvailableVolumes
            throw "Lecteur ${letter}: introuvable - branchez la cle USB ou utilisez -DestinationPath"
        }
        return (Get-ArchDestOnDrive $letter)
    }

    # Auto : une seule cle USB -> la prendre
    $volumes = @(Get-CandidateUsbVolumes)
    if ($volumes.Count -eq 1) {
        Write-Host "Cle USB auto-selectionnee : $($volumes[0].DriveLetter):" -ForegroundColor Green
        return (Get-ArchDestOnDrive $volumes[0].DriveLetter)
    }

    if ($volumes.Count -gt 1) {
        Show-AvailableVolumes
        $pick = Read-Host "Lettre du lecteur cible (ex. F)"
        if (-not $pick) { throw 'Copie annulee' }
        $letter = $pick.TrimEnd(':').ToUpper()
        if (-not (Test-Path (Get-DriveRoot $letter))) { throw "Lecteur ${letter}: introuvable" }
        return (Get-ArchDestOnDrive $letter)
    }

    # USB sans lettre : tenter d'en assigner une (admin)
    $noLetter = @(Get-UsbDisksWithoutLetter)
    if ($noLetter.Count -eq 1 -and (Test-IsAdmin)) {
        Write-Host 'Assignation d''une lettre de lecteur a la cle USB...' -ForegroundColor Yellow
        $newLetter = Try-AssignDriveLetter -DiskNumber $noLetter[0].DiskNumber -PartitionNumber $noLetter[0].Partition
        if ($newLetter) {
            Write-Host "Cle accessible sur ${newLetter}:" -ForegroundColor Green
            return (Get-ArchDestOnDrive $newLetter)
        }
    }

    Show-AvailableVolumes
    throw 'Aucune destination - branchez une cle USB et relancez copy-usb'
}

function Invoke-CopyUsbStep {
    if ($ListVolumes) {
        Show-AvailableVolumes
        return
    }

    if (-not (Test-Path $ReportPath)) {
        throw ('hardware-report.json absent - lancez d''abord: .\arch-setup.ps1 prepare')
    }

    $destRoot = Resolve-CopyDestination

    if ((Test-Path $destRoot) -and -not $Force) {
        throw "Destination existe deja: $destRoot - utilisez -Force pour ecraser"
    }

    # Vérifier espace libre (~500 Mo minimum)
    $drive = Split-Path $destRoot -Qualifier
    if ($drive) {
        $vol = Get-Volume -DriveLetter $drive.TrimEnd(':') -ErrorAction SilentlyContinue
        if ($vol -and $vol.SizeRemaining -lt 500MB) {
            $freeMb = [math]::Round($vol.SizeRemaining / 1MB)
            throw ('Espace insuffisant sur {0} ({1} Mo libres)' -f $drive, $freeMb)
        }
    }

    Write-Step "Copie vers $destRoot"
    $excludeDirs = @('.git', '.github')
    $items = Get-ChildItem -Path $ProjectRoot -Force |
        Where-Object { $excludeDirs -notcontains $_.Name }

    if (Test-Path $destRoot) {
        Remove-Item -Recurse -Force $destRoot
    }
    New-Item -ItemType Directory -Path $destRoot -Force | Out-Null

    foreach ($item in $items) {
        $target = Join-Path $destRoot $item.Name
        Write-Host "  Copie $($item.Name)..." -ForegroundColor DarkGray
        Copy-Item -Path $item.FullName -Destination $target -Recurse -Force
    }

    # Copie explicite du rapport dans analyze/
    $destReport = Join-Path $destRoot 'analyze\hardware-report.json'
    Copy-Item -Path $ReportPath -Destination $destReport -Force

    Write-Host "[OK] Projet copié sur $destRoot" -ForegroundColor Green
    Write-Step 'Sur l''ISO Arch (root)'
    @'

  mkdir -p /root/usb
  mount /dev/sdX1 /root/usb
  cd /root/usb/arch
  chmod +x arch-setup
  ./arch-setup live

'@ | Write-Host
}

function Show-Help {
    @"
Arch + Hyprland — utilitaire Windows

Usage:
  .\arch-setup.ps1 prepare              Analyse PC + valide le rapport
  .\arch-setup.ps1 copy-usb             Copie (auto-détecte la clé USB)
  .\arch-setup.ps1 copy-usb -DriveLetter F   Force une lettre
  .\arch-setup.ps1 copy-usb -DestinationPath D:\staging   Dossier quelconque
  .\arch-setup.ps1 copy-usb -ListVolumes  Liste les clés USB
  .\arch-setup.ps1 check                Vérifie sans modifier
  .\arch-setup.ps1 all                  prepare + copy-usb (auto)

Options:
  -Force          Écrase arch\ existant sur la clé
  -SkipAnalyze    prepare/check sans relancer l'analyse

Sur l'ISO Arch :
  ./arch-setup live

Après installation :
  ./arch-setup first-boot
"@ | Write-Host
}

switch ($Action) {
    'prepare'  { Invoke-PrepareStep }
    'copy-usb' { Invoke-CopyUsbStep }
    'check'    { Invoke-CheckStep }
    'all'      { Invoke-PrepareStep; Invoke-CopyUsbStep }
    'help'     { Show-Help }
    default    { Show-Help }
}
