# Windows Debloater

Original PowerShell GUI tool for Windows privacy & debloating. Built over 8 months with AI assistance.

## What it does
- Disables telemetry / telemetry services
- Removes bundled apps (OneDrive, Xbox, etc.)
- Applies registry privacy settings
- Updates Group Policy / refreshes settings
- Shows live status in a unified GUI

## Requirements
- Windows 10/11
- Administrator rights (`#Requires -RunAsAdministrator`)
- PowerShell 5.1+

## ⚠️ Disclaimer / Warning
- **Use at your own risk.** This script disables Windows services and removes pre-installed applications. It may break features you rely on (OneDrive sync, Xbox Live, Copilot, etc.).
- **Run in a VM or test machine first.** Back up before running.
- Not intended for critical production systems without validation.

## Usage
```powershell
# Right-click -> Run with PowerShell (as Administrator)
.\"Windows Debloater.ps1"
```

## License
MIT License — use, modify, and distribute freely. Original work by author; AI-assisted development.

## Note on false positives
Debloat scripts often trigger antivirus / Windows Defender warnings because they modify the OS. The script contains no external downloads, no `Invoke-WebRequest` payloads, and no encoded malicious commands.
