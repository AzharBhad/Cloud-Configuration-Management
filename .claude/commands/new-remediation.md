---
description: Create an Intune Remediations package (detection script, remediation script, README) in the Remediation folder
argument-hint: <what to detect and fix, e.g. "Detect and remove Zoom" or "Detect and remove Adobe packages, keep Acrobat Reader">
---

Create a new Microsoft Intune **Remediations** package for Windows 10 and Windows 11 devices.

Task: $ARGUMENTS

If the task above is empty or unclear, ask me what to detect and fix before doing anything.

## Where to put it

- Create a new folder inside `Remediation/` at the repo root (create `Remediation/` if it does not exist).
- Name the folder after the task, for example `Remediation/Detect and Remove Zoom`. If a folder with that name already exists, ask me before overwriting.
- Use `Remediation/Detect and Remove Adobe Pac/` as the reference for structure, style, logging and README layout.

## Files to create in that folder

1. **Detection script** - `Detect-<Name>.ps1`
   - Finds every instance of the target: HKLM uninstall keys (64-bit and WOW6432Node), per-user uninstall keys in loaded `HKU` hives, and AppX/MSIX packages (installed for all users and provisioned), plus any other location the target uses (services, files, registry values, scheduled tasks).
   - `exit 1` when the issue is found (Intune then runs remediation), `exit 0` when the device is compliant.
   - Writes one summary line with `Write-Output` (Intune shows the last line, max 2048 characters).
   - Treats an unexpected error as non-compliant (`exit 1`).

2. **Remediation script** - `Remediate-<Name>.ps1`
   - Fixes everything the detection script finds, silently, with no user prompts.
   - For uninstalls: MSI via `msiexec /x {ProductCode} /qn /norestart`; `QuietUninstallString` as-is; vendor-documented silent switches only. Never run an EXE uninstaller without a known silent switch - log it as Skipped instead.
   - Per-step timeout so the whole script stays well under Intune's 60-minute limit. Accept exit codes 0, 3010 and 1641 as success. Never force a restart.
   - `exit 0` when fully fixed, `exit 1` when anything is left, with a one-line summary via `Write-Output`.

3. **README.md** - describes the remediation and gives step-by-step instructions:
   - What it does, what it detects, how each item is fixed, files table.
   - Prerequisites (Windows edition, Intune enrollment, Entra join, licensing: Windows Enterprise E3/E5, Education A3/A5 or VDA per user).
   - Step-by-step creation in the Intune admin center: **Devices > Manage devices > Scripts and remediations > Remediations > + Create**, with the exact Basics, Settings (run as SYSTEM = logged-on credentials **No**, signature check **No**, 64-bit PowerShell **Yes**), Scope tags and Assignments values.
   - The schedule. Default is **Daily, repeats every 7 days** unless the task says otherwise. The schedule is set on the Intune assignment, not in the script.
   - How to check results, run on demand, troubleshooting, and an exit-code table.

## Rules for both scripts

- Run as SYSTEM in 64-bit PowerShell 5.1 - no PowerShell 7-only syntax, no external modules.
- Both scripts are standalone (no shared files) and use the same matching logic.
- Both have an `$ExcludeList` at the top for items to keep (wildcards allowed), and the README says the two lists must match.
- Both log to `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<Name>Remediation.log` with `[DETECT]` / `[REMEDIATE]` tags.
- Comment-based help header (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`) with exit codes, run-as and architecture.
- ASCII only, so Intune doesn't misread the encoding.

## Before finishing

- Check both scripts parse with no errors (use PowerShell 7's parser if Windows PowerShell isn't available) and test any helper functions you can on their own.
- Re-read both scripts for bugs: `$_` inside `catch` blocks, values lost in pipelines, paths with spaces, quoting in uninstall strings.
- Commit with a clear message and push to the current branch (create a branch first if on `main`).
- Tell me: the folder and files created, what was and wasn't tested (the scripts can't be run on Windows here), anything that will be skipped or needs manual handling, and the Intune settings to use.
