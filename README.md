# Defender Deactivation Script

A native PowerShell utility designed for the absolute neutralization of Microsoft Defender in isolated laboratory environments (e.g., Commando or Flare VM). This script utilizes multi-layered enforcement to bypass kernel-mode protections and ensure persistence-free operation.

### Key Features
* **GPO Policy Overrides**: Forces `DisableAntiSpyware` and `DisableRealtimeMonitoring` registry keys to satisfy pre-installation checks for security suites.
* **ACL & Ownership Hijacking**: Programmatically takes ownership of protected SCM registry keys from `TrustedInstaller` to force-disable core services and drivers.
* **IFEO Redirection**: Hijacks Image File Execution Options to prevent Defender binaries (`MsMpEng.exe`, `MpCmdRun.exe`) from spawning by redirecting them to a null debugger.
* **Persistence Neutralization**: Disables the full stack of Defender-related scheduled tasks to prevent system self-healing.
* **Boot-Level Protection**: Deactivates Early Launch Anti-Malware (ELAM) and recovery-mode auto-repairs.

### Usage
Run in an **Administrative PowerShell** session. For a total cleanup, use the optional `-PurgeFiles` switch to remove application data directories.

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\defender-deactivation.ps1 [-PurgeFiles]
```

### Critical Requirements
1. **Tamper Protection**: Must be manually disabled via the Windows Security GUI before execution. Kernel-mode self-protection will otherwise block registry writes.
2. **Reboot**: A system restart is mandatory to unload kernel-mode filter drivers (`WdFilter.sys`) and finalize the neutralization.
3. **Environment**: Intended for **lab/analysis VMs only**. This operation is non-reversible without a system snapshot.

**Maintained by RedTeamNotes**
