---
name: new-remediation
description: Create a Microsoft Intune Remediations script package for Windows 10/11 (detection script, remediation script and README.md) in the Remediation folder. Checks first whether Remediations is the right tool (settings catalog, Win32 app, platform script, custom compliance). Use when the user asks for an Intune remediation, proactive remediation, detection and remediation scripts, or wants Windows devices to keep being checked and fixed on a schedule, even if they don't say "remediation", for example "detect and remove Zoom", "keep this service running", "make sure X stays uninstalled", "self-heal", "fix drift", "clean up expired certificates". For a one-time Windows change use new-platform-script; for macOS use new-platform-script with a script frequency (macOS has no Remediations).
argument-hint: <what to detect and fix, e.g. "Detect and remove Zoom" or "Detect and remove Adobe packages, keep Acrobat Reader">
---

Create a new Microsoft Intune **Remediations** script package for Windows 10 and Windows 11 devices.

Task: $ARGUMENTS

If the task above is empty or unclear, ask me what to detect and fix before doing anything.

## Steps

Do these in order, every time:

0. **Check that Remediations is the right tool** (see below). If it isn't, say which tool fits
   better and why, and build the package only if it is the right tool or I still want it.
1. **Create the folder** (see "Where to put it").
2. **Write the detection script**, then the **remediation script** (see "Files to create").
3. **Write `README.md`**.
4. **Check, commit and push** the new folder only (see "Before finishing").

## Is Remediations the right tool? (step 0)

Remediations run on a schedule and report detection and fix results per device, which makes them
the right tool for **"keep X in this state" on Windows**. Other tools fit better when:

| The task is… | Better tool | Why |
|---|---|---|
| A setting that exists in the settings catalog / a CSP | Configuration policy - `/new-configuration-policy` | Enforced continuously by MDM, per-setting reporting, no script to maintain |
| A one-time change | Platform script - `/new-platform-script` | Runs once, no schedule needed |
| Install or update software | Win32 / LOB app | Detection rules, dependencies, supersedence |
| Gate access (Conditional Access) on a value | Custom compliance - `/new-compliance-policy` | Feeds the compliance state |
| The same task on macOS | Shell script with a Script frequency - `/new-platform-script` | macOS has no Remediations |
| Only report a value, never fix | Detection script only (a package may contain just detection) | Results and output appear in the report |

Removing software that Intune didn't install (and so can't uninstall) is a good Remediations use.

## Where to put it

- Create a new folder inside `Remediation/` at the repo root (create `Remediation/` if it doesn't exist).
- Name it after the task in Title Case, starting with "Detect and", for example
  `Remediation/Detect and Remove Zoom`. If the folder already exists, ask me before overwriting.
- Use `Remediation/Detect and Remove Adobe Pac/` as the reference for structure, style, logging and
  README layout.
- The folder holds **exactly three files**: the detection script, the remediation script, `README.md`.

## Files to create

1. **Detection script** - `Detect-<Name>.ps1`
   - Checks every place the issue can exist. For software: HKLM uninstall keys (64-bit and
     WOW6432Node), per-user uninstall keys in loaded `HKU` hives, AppX/MSIX packages (installed for all
     users and provisioned), and any other location the target uses (services, files, registry values,
     scheduled tasks). For settings, services or registry values: read the current value and compare it
     with the wanted value.
   - `exit 1` when the issue is found (Intune then runs remediation), `exit 0` when the device is
     compliant. Any other exit code, or no output, counts as "issue not found".
   - Writes **one** summary line with `Write-Output` (Intune keeps at most **2,048 characters** of output).
     Don't print values that change every run (timestamps), so the report stays stable.
   - Treats an unexpected error as an issue (`exit 1`) so it gets looked at.

2. **Remediation script** - `Remediate-<Name>.ps1`
   - Fixes everything the detection script finds, silently, with no user prompts.
   - For uninstalls: MSI via `msiexec /x {ProductCode} /qn /norestart`; `QuietUninstallString` as-is;
     vendor-documented silent switches only. Never run an EXE uninstaller without a known silent switch -
     log it as Skipped instead.
   - For settings/services: set the wanted value, then read it back to confirm.
   - Give each long step (uninstall, download, wait) its own timeout so the whole run stays short
     (a few minutes; keep it well under 30 minutes). Accept exit codes 0, 3010 and 1641 as success.
     Never force a restart; log that one is needed.
   - `exit 0` when fully fixed, `exit 1` when anything is left, with a one-line summary via `Write-Output`.

3. **README.md** - for an Intune admin who has never seen the package:
   - What it does and why Remediations is the right tool; what it detects; how each item is fixed;
     files table.
   - Prerequisites (from Microsoft Learn "Remediations"): Microsoft Entra joined or hybrid joined
     devices, Intune-enrolled (or co-managed) Windows **Enterprise, Professional or Education**; users
     licensed for **Windows Enterprise E3/E5** (in Microsoft 365 F3/E3/E5), **Education A3/A5** or
     **VDA per user**; an **Intune Service Administrator** must confirm the licensing the first time
     Remediations is used; role permissions under **Device configurations**.
   - Step-by-step creation: **Devices > Manage devices > Scripts and remediations > Create script
     package**. Basics (Name, Description), Settings: upload both scripts; *Run this script using the
     logged-on credentials* **No** (SYSTEM) unless the fix is per-user (then **Yes**, and say why);
     *Enforce script signature check* **No** unless the scripts are signed (if Yes, save as UTF-8
     **without BOM**); *Run script in 64-bit PowerShell* **Yes** (Learn's default recommendation is No;
     use Yes so registry and Program Files paths aren't redirected, and set it when creating the package).
     Scope tags, Assignments.
   - Assignments: **device groups** (pilot group first); don't mix user and device groups across
     include and exclude. The **schedule** is set per assignment: Once, Hourly (every *n* hours, under 24)
     or Daily at a time. Default **Daily**; say why if the task needs another schedule. Missed runs happen
     when the device is next online.
   - How to check results: **Devices > Manage devices > Scripts and remediations** > the package >
     **Device status** (detection and remediation status, output, Export to CSV). Reports: a change is
     reported when it happens, and every 7 days regardless. The client fetches new packages every 8 hours,
     after a restart, and after a user signs in.
   - Run on demand: device > **…** > **Run remediation (preview)** (needs the *Run remediation*
     permission and the device online).
   - Troubleshooting (`IntuneManagementExtension.log`, `AgentExecutor.log`, the script's own log,
     common errors for this task) and an exit-code table.

## Rules for both scripts

- Run in 64-bit Windows PowerShell 5.1 - no PowerShell 7-only syntax, no external modules.
- Run as SYSTEM unless the task is per-user (HKCU, the user's profile); then explain the choice.
- Both scripts are standalone (no shared files) and use the same matching logic.
- Both have an `$ExcludeList` at the top for items to keep (wildcards allowed) when the task removes
  things, and the README says the two lists must match.
- Both log to `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<Name>Remediation.log` with
  `[DETECT]` / `[REMEDIATE]` tags; keep the log small (roll over above 1 MB).
- Comment-based help header (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`) with exit codes, run-as and
  architecture.
- ASCII only (a subset of UTF-8, so it's also valid when signature check needs UTF-8 without BOM).
- No secrets, passwords or personal data in the scripts, output or logs.

## Batch requests

When one request asks for several packages: list the plan first (folder, what it detects, schedule),
check that no two packages fix the same thing, build each as for a single request, make **one commit
per folder**, push once, and finish with **one** summary table.

## Before finishing

- Both scripts parse with no errors (use PowerShell 7's parser if Windows PowerShell isn't available,
  and download PowerShell 7 into the scratchpad if `pwsh` is missing). Test any helper functions you can
  on their own with fake data, especially the detection logic.
- Re-read both scripts for bugs: `$_` inside `catch` blocks, values lost in pipelines, paths with spaces,
  quoting in uninstall strings, 32/64-bit registry views, detection and remediation disagreeing.
- Commit **only the new folder** with a clear message plus the session's commit trailer, and push to
  the current branch with `git push -u origin <branch>` (create a branch first if on `main`).
- Don't include this skill file in a package's commit; skill changes are committed on their own.
- Tell me: whether Remediations was the right tool, the folder and files created, what was and wasn't
  tested (the scripts can't be run on Windows here), anything that will be skipped or needs manual
  handling, and the exact Intune settings and schedule to use.
