<#
.SYNOPSIS
    defender-deactivation.ps1
    Comprehensive Windows Defender Deactivation Script.
    
.DESCRIPTION
    A multi-layered neutralization tool designed for isolated lab environments (e.g., Flare-VM).
    Integrates GPO policy enforcement, ACL/Ownership hijacking for Service Control Manager (SCM),
    Scheduled Task suspension, and Image File Execution Options (IFEO) hijacking.
    
.PARAMETER PurgeFiles
    Optional switch to physically remove Defender application data directories.

.NOTES
    Compatibility: Windows 10/11 (21H2, 22H2, 24H2 Tested)
    Constraint: Zero third-party dependencies (100% Native PowerShell).
    Warning: This operation is non-reversible without system snapshots.
    2026 By RedTeamNotes
#>

[CmdletBinding()]
param ([Switch]$PurgeFiles)

Write-Host "[*] RedTeamNotes Defender Deactivation Script Initialized." -ForegroundColor Cyan
$ErrorActionPreference = "SilentlyContinue"

# --- Helper: Registry Ownership Hijacking ---
function Set-RegistryAccess {
    param([string]$Path)
    $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    try {
        $RegKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path.Replace("HKLM:\",""), [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
        $Acl = $RegKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
        $Acl.SetOwner($AdminSid)
        $RegKey.SetAccessControl($Acl)
        
        $Acl = $RegKey.GetAccessControl()
        $Ar = New-Object System.Security.AccessControl.RegistryAccessRule("Administrators", "FullControl", "Allow")
        $Acl.SetAccessRule($Ar)
        $RegKey.SetAccessControl($Acl)
        $RegKey.Close()
        return $true
    } catch { return $false }
}

# --- Phase 1: GPO Policy Enforcement (Critical for Flare-VM Pre-Checks) ---
Write-Host "[1/6] Overriding GPO Policies for Flare-VM compatibility..."
$GPOPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender",
    "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
)
foreach ($Path in $GPOPaths) {
    if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }
}
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1
Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableIOAVProtection" -Value 1

# --- Phase 2: Scanning Engine Deactivation ---
Write-Host "[2/6] Injecting Global Filesystem Exclusions..."
Add-MpPreference -ExclusionPath "C:\" 

# --- Phase 3: Persistence Neutralization (Scheduled Tasks) ---
Write-Host "[3/6] Disabling Defender Autonomic Maintenance Tasks..."
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" | Disable-ScheduledTask

# --- Phase 4: SCM & Kernel Driver Hijacking ---
Write-Host "[4/6] Hijacking Service Control Manager (SCM) Registry..."
$Services = @("WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "WdBoot", "WdFilter", "WdNisDrv")
foreach ($Svc in $Services) {
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\${Svc}"
    if (Test-Path $RegPath) {
        if (Set-RegistryAccess -Path $RegPath) {
            Set-ItemProperty -Path $RegPath -Name "Start" -Value 4
            Write-Host "    [-] ${Svc}: Status -> Disabled" -ForegroundColor Gray
        } else {
            Write-Host "    [!] ${Svc}: Registry Locked (Kernel-mode protection)" -ForegroundColor Red
        }
    }
}

# --- Phase 5: Image File Execution Options (IFEO) Hijacking ---
Write-Host "[5/6] Redirecting Defender Binaries to NULL Debugger..."
$Binaries = @("MsMpEng.exe", "MpCmdRun.exe")
foreach ($Bin in $Binaries) {
    $Key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\${Bin}"
    if (-not (Test-Path $Key)) { New-Item $Key -Force | Out-Null }
    Set-ItemProperty $Key -Name "Debugger" -Value "ntsd.exe -d"
}

# --- Phase 6: Kernel Integrity & Boot Config ---
Write-Host "[6/6] Neutralizing ELAM and Recovery Policies..."
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\EarlyLaunch" -Name "DisableAntiMalware" -Value 1
bcdedit /set {current} recoveryenabled No | Out-Null

if ($PurgeFiles) {
    Write-Host "[!] Purging Protected Directory Structure..."
    $TargetDir = "C:\ProgramData\Microsoft\Windows Defender"
    takeown /f $TargetDir /r /d y | Out-Null
    icacls $TargetDir /grant administrators:F /t | Out-Null
    Remove-Item $TargetDir -Recurse -Force
}

Write-Host "[#] RedTeamNotes: Neutralization complete. SYSTEM REBOOT REQUIRED." -ForegroundColor Green
