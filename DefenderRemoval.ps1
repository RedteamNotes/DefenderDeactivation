<#
.SYNOPSIS
    RedTeamNotes: Advanced Microsoft Defender Component Neutralization.
.DESCRIPTION
    Direct registry and filesystem manipulation to disable Defender for 
    isolated laboratory environments (e.g., Flare-VM).
.NOTES
    Branding: RedTeamNotes Infrastructure Engineering
#>

[CmdletBinding()]
param (
    [Parameter()]
    [Switch]$PurgeFiles
)

# 0. Privilege Check
$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "[RedTeamNotes] Execution failed: High-integrity process required."
    return
}

Write-Host "[*] RedTeamNotes Defender Neutralization initialized." -ForegroundColor Cyan

# 1. Verification: Tamper Protection
# Note: Mandatory manual intervention required if not already disabled via GUI.
$TamperPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
$TamperVal = Get-ItemProperty -Path $TamperPath -Name "TamperProtection" -ErrorAction SilentlyContinue
if ($TamperVal.TamperProtection -ne 4) {
    Write-Warning "[!] Tamper Protection is active. Manual disablement in Windows Security GUI is required."
}

# 2. Exclusion Policy Injection
# RedTeamNotes Strategy: Whitelist the entire filesystem to neutralize the engine.
Write-Host "[Step 1/4] Injecting global filesystem exclusions..."
$Drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
foreach ($Drive in $Drives) {
    Add-MpPreference -ExclusionPath $Drive -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "$($Drive)*" -ErrorAction SilentlyContinue
}

# 3. Scanning Engine Deactivation
Write-Host "[Step 2/4] Disabling real-time monitoring and reporting..."
$PrefParams = @{
    DisableRealtimeMonitoring = $true
    DisableBehaviorMonitoring = $true
    DisableIOAVProtection = $true
    DisableScriptScanning = $true
    MAPSReporting = 0
    SubmitSamplesConsent = 0
}
Set-MpPreference @PrefParams -ErrorAction SilentlyContinue

# 4. Service and Driver Hard-Disable
# Target: Modify 'Start' dword to 4 (Disabled). 
# Failure here usually indicates lack of TrustedInstaller privileges.
Write-Host "[Step 3/4] Neutralizing kernel drivers and services..."
$TargetComponents = @(
    "WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", # Services
    "WdBoot", "WdFilter", "WdNisDrv", "WdDevFlt"                # Drivers
)

foreach ($Comp in $TargetComponents) {
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Comp"
    if (Test-Path $RegPath) {
        try {
            Set-ItemProperty -Path $RegPath -Name "Start" -Value 4 -ErrorAction Stop
            Write-Host "    [-] $Comp: Success" -ForegroundColor Gray
        } catch {
            Write-Host "    [!] $Comp: Unauthorized (Requires TrustedInstaller/NSudo)" -ForegroundColor Red
        }
    }
}

# 5. Optional Filesystem Purge
if ($PurgeFiles) {
    Write-Host "[Step 4/4] Purging physical binary directories..."
    $DefenderDir = "C:\ProgramData\Microsoft\Windows Defender"
    if (Test-Path $DefenderDir) {
        takeown /f $DefenderDir /r /d y | Out-Null
        icacls $DefenderDir /grant administrators:F /t | Out-Null
        Remove-Item -Path $DefenderDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[#] RedTeamNotes: Operation complete. Reboot to commit changes." -ForegroundColor Green
