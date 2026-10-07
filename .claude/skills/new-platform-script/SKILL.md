---
name: new-platform-script
description: Create a Microsoft Intune Windows platform script (PowerShell script + README.md) in the "Platform Scripts" folder. Use when the user asks for an Intune platform script, a PowerShell script to deploy through Intune "Platform scripts", or a one-time configuration script for Windows 10/11 devices managed by Intune.
argument-hint: <what the script should do, e.g. "Set the device time zone to GMT Standard Time" or "Map the S: drive to \\fileserver\shared for all users">
---

Create a new Microsoft Intune **platform script** for Windows 10 and Windows 11 devices.

Task: $ARGUMENTS

If the task above is empty or unclear, ask me what the script should do before doing anything.
If the task is something that must be checked and fixed again and again on a schedule (for example
"keep X turned on"), tell me it fits Intune **Remediations** better and suggest `/new-remediation`
instead - but build the platform script if I still want it.

## Platform script facts (Microsoft Learn: "Use PowerShell scripts on Windows devices in Intune")

Design every script around how Intune runs platform scripts:

- Added in **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**.
- File must be **less than 200 KB** and **ASCII**.
- **Runs once** per device (or per user). It runs again only when the script or the policy changes,
  and a script assigned to a device runs again for **every new user who signs in** (not on
  multi-session SKUs).
- If it **fails**, the Intune Management Extension (IME) **retries three times** at the next three
  IME check-ins, then stops.
- **Times out after 30 minutes.**
- Runs **before Win32 apps** are installed.
- Settings and their defaults: **Run this script using the logged on credentials** (default **Yes** =
  user context; **No** = SYSTEM), **Enforce script signature check** (default **Yes**), **Run script in
  64-bit PowerShell host** (default **No** = 32-bit).
- Reported as **failed** when the script exits with a non-zero exit code **or writes to the error
  stream** (`Write-Error`, uncaught errors). Anything that is not a real failure must not reach the
  error stream.
- Devices must be **Microsoft Entra joined** or **hybrid joined** (registered-only devices don't get
  scripts). Scripts don't run on Windows in S mode or Surface Hub.
- Don't put passwords, secrets or personal data in scripts.

## Where to put it

- Create a new folder inside `Platform Scripts/` at the repo root (create `Platform Scripts/` if it
  does not exist).
- Name the folder after the task in plain words, for example `Platform Scripts/Set Time Zone` or
  `Platform Scripts/Map Shared Network Drive`. If a folder with that name already exists, ask me
  before overwriting.
- If `Platform Scripts/.gitkeep` exists, delete it once the new folder has real files.
- If other folders in `Platform Scripts/` already exist, match their structure, style and README
  layout. Otherwise use `Remediation/Detect and Remove Adobe Pac/` as the reference for script style
  and logging.

## Files to create in that folder

### 1. The PowerShell script - `<Verb>-<Noun>.ps1`

Name it with an approved PowerShell verb, for example `Set-TimeZone.ps1`, `Install-Fonts.ps1`,
`Add-NetworkDrive.ps1`.

- **Comment-based help header** (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`) with: what it does, every
  action in order, exit codes, the Intune settings to use (run as user or SYSTEM, 64-bit, signature
  check) and the log file path.
- **Settings at the top** in clearly commented variables (values to change, an `$ExcludeList` of
  items or computer/user names to skip when that makes sense). No hard-coded values buried in the code.
- **Idempotent**: safe to run more than once. Check the current state first and only change what
  is not already right, because the script re-runs for new users, after edits, and on retries.
- **Run context**: pick SYSTEM or user context from what the task needs, and say why in the help
  header and README.
  - SYSTEM: machine settings, HKLM, Program Files, services, installs.
  - User: HKCU, the user's profile, mapped drives, per-user apps. Users are usually not admins, so
    user-context scripts must not need admin rights unless the README says so.
  - If the task needs both, prefer SYSTEM and write to each user's profile / the Default profile,
    or explain the split in the README.
- **64-bit**: write for the 64-bit host (README says set "Run script in 64-bit PowerShell host" to
  **Yes**). If the script must also be safe in a 32-bit host, relaunch itself in 64-bit PowerShell
  through `$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe` when
  `[Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess`.
- **PowerShell 5.1 only**: no PowerShell 7 syntax, no external modules that aren't built into
  Windows. ASCII only.
- **Logging**: write a timestamped log to
  `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<Name>PlatformScript.log` (SYSTEM) or
  `%TEMP%\<Name>PlatformScript.log` (user context). Log every action and its result.
- **Error handling**: wrap the main body in `try/catch`. Use `-ErrorAction Stop` where a failure must
  stop the script and `-ErrorAction SilentlyContinue` for expected misses, so harmless errors never
  reach the error stream. Inside `catch` use `$_.Exception.Message` (not `$_` from an outer pipeline).
- **Time limit**: give any long step (downloads, installs, waits) its own timeout so the whole script
  finishes well under 30 minutes.
- **Never restart the device** or sign the user out. If a restart is needed, log it and say so in the
  output.
- **Exit codes**: `exit 0` on success, `exit 1` on failure (Intune then retries up to 3 times).
  Use `3010` only if the change needs a restart and that should be visible - and explain in the README
  that Intune treats any non-zero code as a failure.
- End with one short summary line via `Write-Output`.

### 2. README.md

Describe the script for an Intune admin who has never seen it, with these sections:

1. **Title and overview** - what the script does and why you'd use it (the use of it).
2. **Files** - table of the files in the folder.
3. **Typical actions** - when to use this script: typical scenarios and use cases (for example
   "new device setup", "after a migration", "one-time fix for a group of devices"), and what the
   script does on the device, step by step, in a table (action -> what happens -> when it is skipped).
4. **Settings in the script** - each variable at the top, its default and how to change it, with an
   example code block.
5. **How Intune runs it** - run once, re-runs after edits and for new users, 3 retries on failure,
   30-minute timeout, runs before Win32 apps; what that means for this particular script.
6. **Prerequisites** - Windows 10/11 edition, Intune enrollment, Microsoft Entra joined or hybrid
   joined (not registered-only), anything the task needs (network access, file share permissions for
   the computer account, licenses).
7. **Step-by-step: add the script in Intune** - exact steps:
   **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**, then
   Basics (Name, Description), Script settings (Script location, Run this script using the logged on
   credentials **Yes/No** for this script and why, Enforce script signature check **No** unless signed,
   Run script in 64-bit PowerShell host **Yes**), Scope tags, Assignments (device group or user group
   and why), Review + add.
8. **Step-by-step: check the results** - open the script under Platform scripts, **Device status** /
   **User status**, what success and failure look like, and how to check the change on a device.
9. **Running it again** - how to make Intune run it again (upload a changed script, or remove and
   re-add the assignment) and that it re-runs for new users automatically.
10. **Undo** (when the change can be reverted) - how to reverse what the script did.
11. **Troubleshooting** - the script's log file, `IntuneManagementExtension.log` and
    `AgentExecutor.log` in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`, common errors
    for this task and their fixes, and how to test locally (`psexec -i -s powershell.exe` for SYSTEM).
12. **Exit codes** - table.

Keep the README plain and practical: short sentences, exact menu paths and setting values.

## Before finishing

- Check the script parses with no errors. Use PowerShell 7's parser if Windows PowerShell isn't
  available (download PowerShell 7 into the scratchpad if `pwsh` isn't installed).
- Test every helper function you can on its own with fake data, especially the "is it already done?"
  checks that make the script idempotent.
- Re-read the script for bugs: `$_` inside `catch` blocks, values lost in pipelines, paths with spaces,
  quoting in command lines, anything that would write to the error stream on success, 32-bit vs
  64-bit registry and Program Files paths, and user vs SYSTEM context mistakes.
- Check the script is ASCII only and well under 200 KB.
- Commit with a clear message and push to the current branch (create a branch first if on `main`).
- Tell me: the folder and files created, what was and wasn't tested (the script can't be run on
  Windows here), anything that needs manual handling, and the Intune settings to use.
