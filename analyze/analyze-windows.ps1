#Requires -Version 5.1
<#
.SYNOPSIS
    Analyse complète du PC Windows pour préparer l'installation Arch Linux + Hyprland.
.DESCRIPTION
    Inventorie le matériel, les partitions, le réseau, l'affichage et les prérequis
    dual-boot. Génère hardware-report.json consommé par l'installateur Arch.
.PARAMETER OutputPath
    Chemin du fichier JSON de sortie.
.PARAMETER DryRun
    Utilise des données de test au lieu de l'inventaire réel.
#>
[CmdletBinding()]
param(
    # Résolu après le bloc param : $PSScriptRoot peut être vide ici sous PS 5.1 (-File)
    [string]$OutputPath = '',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $OutputPath = Join-Path $scriptDir 'hardware-report.json'
}

function Get-BytesAsGiB {
    param([long]$Bytes)
    [math]::Round($Bytes / 1GB, 2)
}

function Get-UnallocatedSpaceBytes {
    param([int]$DiskNumber = 0)
    $disk = Get-Disk -Number $DiskNumber -ErrorAction Stop
    $used = [long]0
    Get-Partition -DiskNumber $DiskNumber | ForEach-Object {
        $used += [long]$_.Size
    }
    [math]::Max([long]0, [long]$disk.Size - $used)
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-BitLockerStatus {
    $isAdmin = Test-IsAdmin
    try {
        $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
        if ($bl) {
            return @{
                enabled        = ($bl.ProtectionStatus -eq 'On')
                status         = [string]$bl.ProtectionStatus
                mustSuspend    = ($bl.ProtectionStatus -eq 'On')
                checkedAsAdmin = $isAdmin
            }
        }
    }
    catch {
        # BitLocker cmdlet unavailable on some editions
    }
    # Fallback manage-bde (sortie localisée : anglais et français gérés)
    try {
        $output = & manage-bde -status C: 2>$null | Out-String
        if ($LASTEXITCODE -eq 0 -and $output) {
            if ($output -match 'Protection\s+(On|activ)') {
                return @{ enabled = $true; status = 'On'; mustSuspend = $true; checkedAsAdmin = $isAdmin }
            }
            if ($output -match 'Protection\s+(Off|d[ée]sactiv)') {
                return @{ enabled = $false; status = 'Off'; mustSuspend = $false; checkedAsAdmin = $isAdmin }
            }
        }
    }
    catch {
        # manage-bde absent ou refusé sans élévation
    }
    if (-not $isAdmin) {
        Write-Warning "Statut BitLocker indéterminé : relancez ce script en administrateur avant l'installation réelle."
    }
    @{
        enabled        = $false
        status         = 'Unknown'
        mustSuspend    = $false
        checkedAsAdmin = $isAdmin
    }
}

function Initialize-DisplayNativeApi {
    if ('ArchDisplayNative' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class ArchDisplayNative {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public ushort dmSpecVersion;
        public ushort dmDriverVersion;
        public ushort dmSize;
        public ushort dmDriverExtra;
        public uint dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public uint dmDisplayOrientation;
        public uint dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public ushort dmLogPixels;
        public uint dmBitsPerPel;
        public uint dmPelsWidth;
        public uint dmPelsHeight;
        public uint dmDisplayFlags;
        public uint dmDisplayFrequency;
        public uint dmICMMethod;
        public uint dmICMIntent;
        public uint dmMediaType;
        public uint dmDitherType;
        public uint dmReserved1;
        public uint dmReserved2;
        public uint dmPanningWidth;
        public uint dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettingsW(string deviceName, int modeNum, ref DEVMODE devMode);

    public const int ENUM_CURRENT_SETTINGS = -1;
}
'@
}

# EnumDisplaySettings n'est pas virtualisé par le DPI : il renvoie le mode natif
# du panneau même dans un processus non DPI-aware (contrairement à Screen.Bounds).
function Get-NativeDisplayMode {
    param([string]$DeviceName)
    try {
        Initialize-DisplayNativeApi
        $devMode = New-Object ArchDisplayNative+DEVMODE
        $devMode.dmSize = [uint16][System.Runtime.InteropServices.Marshal]::SizeOf([type][ArchDisplayNative+DEVMODE])
        if ([ArchDisplayNative]::EnumDisplaySettingsW($DeviceName, [ArchDisplayNative]::ENUM_CURRENT_SETTINGS, [ref]$devMode)) {
            return @{
                width     = [int]$devMode.dmPelsWidth
                height    = [int]$devMode.dmPelsHeight
                refreshHz = if ($devMode.dmDisplayFrequency -gt 1) { [int]$devMode.dmDisplayFrequency } else { 60 }
            }
        }
    }
    catch {
        # P/Invoke indisponible : on retombera sur la résolution logique
    }
    return $null
}

function Get-DisplayScale {
    param(
        [double]$NativeWidth,
        [double]$LogicalWidth
    )
    if ($NativeWidth -le 0 -or $LogicalWidth -le 0) { return 1.0 }
    $raw = $NativeWidth / $LogicalWidth
    if ($raw -le 1.0) { return 1.0 }
    # Windows propose des paliers de 25 % : on aligne si on en est proche
    $snapped = [math]::Round($raw * 4) / 4
    if ([math]::Abs($raw - $snapped) -le 0.05) { return $snapped }
    return [math]::Round($raw, 2)
}

function Get-DisplayInfo {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $screens = @()
    if ([System.Windows.Forms.Screen]::AllScreens) {
        foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
            $native = Get-NativeDisplayMode -DeviceName $s.DeviceName
            $logicalWidth = $s.Bounds.Width
            $logicalHeight = $s.Bounds.Height
            $width = if ($native) { $native.width } else { $logicalWidth }
            $height = if ($native) { $native.height } else { $logicalHeight }
            $screens += @{
                deviceName    = $s.DeviceName
                primary       = $s.Primary
                width         = $width
                height        = $height
                logicalWidth  = $logicalWidth
                logicalHeight = $logicalHeight
                refreshHz     = if ($native) { $native.refreshHz } else { 60 }
                scale         = Get-DisplayScale -NativeWidth $width -LogicalWidth $logicalWidth
            }
        }
    }
    if ($screens.Count -eq 0) {
        $screens = @(@{
            deviceName    = 'Unknown'
            primary       = $true
            width         = 1920
            height        = 1080
            logicalWidth  = 1920
            logicalHeight = 1080
            refreshHz     = 60
            scale         = 1.0
        })
    }
    return $screens
}

function Get-NetworkAdaptersInfo {
    $adapters = @()
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
        $detail = $_
        $wifi = $false
        $bt = $false
        if ($detail.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\.11') { $wifi = $true }
        if ($detail.InterfaceDescription -match 'Bluetooth') { $bt = $true }
        $adapters += @{
            name        = $detail.Name
            description = $detail.InterfaceDescription
            macAddress  = $detail.MacAddress
            status      = $detail.Status
            isWifi      = $wifi
            isBluetooth = $bt
        }
    }
    return $adapters
}

function Get-PnpDevicesInfo {
    $devices = @()
    $classes = @('Net', 'Bluetooth', 'Display', 'System')
    foreach ($cls in $classes) {
        Get-PnpDevice -Class $cls -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -and $_.InstanceId } |
            ForEach-Object {
                $devices += @{
                    class       = $cls
                    friendlyName = $_.FriendlyName
                    instanceId  = $_.InstanceId
                    status      = $_.Status
                }
            }
    }
    return $devices
}

function Get-KeyboardLayout {
    try {
        $culture = [System.Globalization.CultureInfo]::CurrentUICulture
        $layout = (Get-WinUserLanguageList | Select-Object -First 1).LanguageTag
        @{
            layoutTag = $layout
            culture   = $culture.Name
        }
    }
    catch {
        @{ layoutTag = 'fr-FR'; culture = 'fr-FR' }
    }
}

function Get-DiskLayout {
    $layouts = @()
    Get-Disk | ForEach-Object {
        $disk = $_
        $partitions = Get-Partition -DiskNumber $disk.Number | ForEach-Object {
            $vol = Get-Volume -Partition $_ -ErrorAction SilentlyContinue
            @{
                number      = $_.PartitionNumber
                driveLetter = if ($_.DriveLetter) { [string]$_.DriveLetter } else { $null }
                sizeBytes   = [long]$_.Size
                sizeGiB     = (Get-BytesAsGiB $_.Size)
                type        = $_.Type
                gptType     = $_.GptType
                filesystem  = if ($vol) { $vol.FileSystem } else { $null }
                label       = if ($vol) { $vol.FileSystemLabel } else { $null }
            }
        }
        $unallocated = Get-UnallocatedSpaceBytes -DiskNumber $disk.Number
        $layouts += @{
            diskNumber       = $disk.Number
            friendlyName     = $disk.FriendlyName
            sizeBytes        = [long]$disk.Size
            sizeGiB          = (Get-BytesAsGiB $disk.Size)
            partitionStyle   = $disk.PartitionStyle
            unallocatedBytes = [long]$unallocated
            unallocatedGiB   = (Get-BytesAsGiB $unallocated)
            partitions       = @($partitions)
        }
    }
    return $layouts
}

function Get-InstallRecommendation {
    param($DiskLayout)
    $target = $DiskLayout | Where-Object { $_.unallocatedGiB -ge 50 } | Sort-Object -Property unallocatedGiB -Descending | Select-Object -First 1
    if (-not $target) {
        return @{
            canInstall     = $false
            reason         = 'Espace non alloué insuffisant (< 50 GiB requis)'
            targetDisk     = $null
            suggestedRootGiB = 0
        }
    }
    $rootGiB = [math]::Min([math]::Floor($target.unallocatedGiB * 0.85), 300)
  @{
        canInstall       = $true
        reason           = 'Espace libre détecté, installation sans réduction de Windows possible'
        targetDisk       = $target.diskNumber
        suggestedRootGiB = $rootGiB
        useExistingEfi   = $true
    }
}

function New-HardwareReport {
    $computer = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $gpus = Get-CimInstance Win32_VideoController | Where-Object {
        $_.Name -and $_.Name -notmatch 'Virtual|Basic Display|Microsoft Remote'
    } | ForEach-Object {
        @{
            name          = $_.Name
            adapterRamMiB = if ($_.AdapterRAM -and $_.AdapterRAM -lt 1TB) { [math]::Round($_.AdapterRAM / 1MB) } else { $null }
            driverVersion = $_.DriverVersion
            isDiscrete    = ($_.Name -notmatch 'Intel|Virtual|Basic')
        }
    }
    if ($gpus.Count -eq 0) {
        $gpus = @(@{ name = 'Unknown'; adapterRamMiB = $null; driverVersion = ''; isDiscrete = $false })
    }
    $firmware = (Get-ComputerInfo -Property BiosFirmwareType).BiosFirmwareType
    # @() force le contexte tableau : PowerShell "déballe" automatiquement un
    # tableau à un seul élément en scalaire quand une fonction le retourne via
    # le pipeline (cas du disque unique, le plus courant) — sans ça, storage.disks
    # devient un objet JSON au lieu d'un tableau, invalide selon le schéma.
    $diskLayout = @(Get-DiskLayout)
    $installRec = Get-InstallRecommendation -DiskLayout $diskLayout
    $primaryDisplay = (Get-DisplayInfo | Where-Object { $_.primary } | Select-Object -First 1)
    if (-not $primaryDisplay) { $primaryDisplay = (Get-DisplayInfo | Select-Object -First 1) }

    @{
        schemaVersion = '1.0.0'
        generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
        hostname      = $env:COMPUTERNAME
        system        = @{
            manufacturer = $computer.Manufacturer
            model        = $computer.Model
            firmware     = [string]$firmware
            biosVersion  = $bios.SMBIOSBIOSVersion
        }
        cpu = @{
            name       = $cpu.Name
            cores      = $cpu.NumberOfCores
            threads    = $cpu.NumberOfLogicalProcessors
            architecture = 'x86_64'
        }
        memory = @{
            totalBytes = [long]$computer.TotalPhysicalMemory
            totalGiB   = (Get-BytesAsGiB $computer.TotalPhysicalMemory)
        }
        gpu = @($gpus)
        storage = @{
            disks = @($diskLayout)
        }
        display = @{
            primary = $primaryDisplay
            all     = @(Get-DisplayInfo)
        }
        network = @{
            adapters = @(Get-NetworkAdaptersInfo)
        }
        pnpDevices = @(Get-PnpDevicesInfo)
        keyboard = Get-KeyboardLayout
        locale = @{
            timezone = [System.TimeZoneInfo]::Local.Id
            language = (Get-Culture).Name
        }
        security = @{
            bitlocker = Get-BitLockerStatus
        }
        install = $installRec
        profiles = @{
            dev        = $true
            gaming     = $true
            office     = $true
            video      = $true
            hyprland   = $true
        }
    }
}

function New-MockHardwareReport {
    @{
        schemaVersion = '1.0.0'
        generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
        hostname      = 'MOCK-PC'
        system        = @{
            manufacturer = 'HONOR'
            model        = 'HGE-WX6'
            firmware     = 'Uefi'
            biosVersion  = '1.0.0'
        }
        cpu = @{
            name       = '11th Gen Intel(R) Core(TM) i7-11390H @ 3.40GHz'
            cores      = 4
            threads    = 8
            architecture = 'x86_64'
        }
        memory = @{
            totalBytes = 17179869184
            totalGiB   = 16.0
        }
        gpu = @(
            @{ name = 'Intel(R) Iris(R) Xe Graphics'; adapterRamMiB = 2048; driverVersion = '32.0.101.7085'; isDiscrete = $false }
        )
        storage = @{
            disks = @(
                @{
                    diskNumber = 0
                    friendlyName = 'WD_BLACK SN770 2TB'
                    sizeBytes = 2000398934016
                    sizeGiB = 1863.02
                    partitionStyle = 'GPT'
                    unallocatedBytes = 337222451200
                    unallocatedGiB = 314.0
                    partitions = @()
                }
            )
        }
        display = @{
            primary = @{ deviceName = '\\.\DISPLAY1'; primary = $true; width = 2520; height = 1680; logicalWidth = 1680; logicalHeight = 1120; refreshHz = 60; scale = 1.5 }
            all = @(@{ deviceName = '\\.\DISPLAY1'; primary = $true; width = 2520; height = 1680; logicalWidth = 1680; logicalHeight = 1120; refreshHz = 60; scale = 1.5 })
        }
        network = @{ adapters = @() }
        pnpDevices = @()
        keyboard = @{ layoutTag = 'fr-FR'; culture = 'fr-FR' }
        locale = @{ timezone = 'Romance Standard Time'; language = 'fr-FR' }
        security = @{ bitlocker = @{ enabled = $false; status = 'Off'; mustSuspend = $false } }
        install = @{
            canInstall = $true
            reason = 'Mock'
            targetDisk = 0
            suggestedRootGiB = 250
            useExistingEfi = $true
        }
        profiles = @{
            dev = $true; gaming = $true; office = $true; video = $true; hyprland = $true
        }
    }
}

function Test-HardwareReportSchema {
    param([hashtable]$Report)
    $required = @('schemaVersion', 'generatedAt', 'system', 'cpu', 'memory', 'gpu', 'storage', 'display', 'install', 'profiles')
    foreach ($key in $required) {
        if (-not $Report.ContainsKey($key)) {
            throw "Clé manquante dans le rapport: $key"
        }
    }
    if ($Report.schemaVersion -ne '1.0.0') {
        throw "schemaVersion invalide: $($Report.schemaVersion)"
    }
    if (-not $Report.install.canInstall -and -not $Report.install.reason) {
        throw 'install.reason requis quand canInstall est false'
    }
}

function Export-HardwareReport {
    param(
        [hashtable]$Report,
        [string]$Path
    )
    Test-HardwareReportSchema -Report $Report
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Report | ConvertTo-Json -Depth 10
    # UTF-8 sans BOM : PS5.1 ajouterait un BOM avec Set-Content -Encoding UTF8,
    # ce qui casse json.load() côté installateur Linux
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
    Write-Host "Rapport matériel exporté: $Path"
    return $Path
}

# --- Exécution principale (uniquement si script invoqué, pas en dot-source) ---
if ($MyInvocation.InvocationName -ne '.') {
    $report = if ($DryRun) { New-MockHardwareReport } else { New-HardwareReport }
    $null = Export-HardwareReport -Report $report -Path $OutputPath
    $report
}
