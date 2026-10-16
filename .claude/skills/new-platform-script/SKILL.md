---
name: new-platform-script
description: Create a Microsoft Intune platform script for Windows 10/11 (PowerShell) or macOS (shell script), with a README.md, in the "Platform Scripts" folder. Checks first whether a script is the right tool (settings catalog, Remediations, app, custom attribute) and identifies the platform from the request. Use when the user asks for an Intune platform script, a PowerShell or shell script to deploy through Intune, a one-time configuration script, or a macOS hardening/maintenance script.
argument-hint: <what the script should do, e.g. "Set the device time zone to GMT Standard Time" or "macOS - remove local admin rights from standard users">
---

Create a new Microsoft Intune **platform script** for **Windows 10/11** (PowerShell) or **macOS** (shell).

Task: $ARGUMENTS

If the task above is empty or unclear, ask me what the script should do before doing anything.

## Steps

Do these in order, every time:

0. **Check that a script is the right tool** (see "Is a script the right tool?"). If it isn't, say
   which tool fits better and why. Build the script only if it is the right tool, or if I still want it.
1. **Identify the platform** (Windows or macOS) from the task. Say which one and what told you.
   Ask only if it truly can't be told. One request for both platforms means **two scripts**, one per
   platform folder.
2. **Create the directory** for the script (see "Where to put it").
3. **Write the script**: PowerShell for Windows (see "Windows script"), shell for macOS (see "macOS script").
4. **Write `README.md`** (see "README.md").
5. **Check, commit and push** the new directory only (see "Before finishing").

## Is a script the right tool? (step 0)

Scripts are the **last resort** in an enterprise tenant: they run once, are hard to audit, and drift is
invisible. Use this table and tell me when another tool fits better:

| The task is… | Better tool | Why |
|---|---|---|
| A setting that exists in the settings catalog, a CSP, an Apple payload or DDM | Configuration policy - `/new-configuration-policy` | Enforced continuously, reports per setting, reverts or conflicts are visible |
| "Keep X in this state" / check and fix again and again (**Windows**) | **Remediations** - `/new-remediation` | Detection + remediation on a schedule with reporting |
| "Keep X in this state" (**macOS**) | Shell script **with a Script frequency** (still this skill) | macOS has no Remediations; frequency re-runs the script |
| Install, update or remove software | Win32 app / LOB / PKG / DMG app | Detection rules, dependencies, supersedence, reporting |
| Only **read and report** a value (**macOS**) | **Custom attribute for macOS** (still this skill, see "Custom attribute variant") | Result is shown per device in the admin center, runs every 8 hours |
| Gate access on a value | Custom compliance (discovery script + JSON) - `/new-compliance-policy` | Feeds Conditional Access |

## Where to put it (step 2)

All platform scripts live under `Platform Scripts/` at the repo root (create it if missing). One
sub-directory per script, named after the task **in plain words, Title Case, with spaces, starting
with the action** (for example `Enable BitLocker`, `Set Time Zone`, `Remove Local Admin Rights`).

| Platform | Path | Files |
|---|---|---|
| Windows 10/11 | `Platform Scripts/<Task Name>/` | `<Verb>-<Noun>.ps1` + `README.md` |
| macOS | `Platform Scripts/MacOS/<Task Name>/` | `<kebab-case-name>.sh` (or `.zsh`) + `README.md` |

- The Windows scripts that already exist sit directly in `Platform Scripts/` (for example
  `Platform Scripts/Enable BitLocker/`). Keep new Windows scripts there so the folder stays consistent.
  If I ask to align it with `Compliance/` and `Configuration/`, move them into `Platform Scripts/Windows/`,
  but **never move existing folders without being asked**.
- A sub-directory holds **exactly two files**: the script and its `README.md`. Never two scripts in one
  folder, never a script directly in `Platform Scripts/` or `Platform Scripts/MacOS/`.
- If the sub-directory already exists, ask me before overwriting.
- If `Platform Scripts/.gitkeep` exists, delete it once the new sub-directory has real files.
- Match the style of existing scripts on the same platform (for example `Platform Scripts/Enable BitLocker/`
  for Windows). With no macOS script yet, follow the rules below.

## Enterprise security standards (both platforms)

- **No secrets, passwords, keys, tenant secrets or personal data** in scripts, logs or README.
  Use placeholders, and say where the real value must come from (for example an app registration
  certificate, a Key Vault, or a per-device value).
- **Least privilege**: run as user when the task only touches the user's profile; run as SYSTEM/root only
  when needed, and say why.
- **Downloads**: HTTPS only, from a pinned URL in the settings block, **verify the SHA-256 hash** before
  using the file, and never pipe remote content into an interpreter (`iex (iwr ...)`, `curl | sh`).
- **No device restarts, sign-outs or user-visible prompts** unless the task explicitly needs them.
  Log that a restart is required instead.
- **Idempotent**: check the current state first and change only what isn't already right. Scripts re-run
  (new users, edits, retries, frequency) and must be safe to run any number of times.
- **Logging**: timestamped, every action and its result, no personal data, and keep the log small
  (for example trim or roll over above 1 MB).
- **Clear exit codes**: `0` success, `1` failure. Intune treats **any non-zero** code as failed.
- **Windows signing**: in production, sign scripts with the organization's code-signing certificate and
  set *Enforce script signature check* = **Yes**. If App Control for Business is enforced, unsigned
  scripts run in **Constrained Language Mode**: avoid .NET type calls and `Add-Type`, or sign the script.
  Say in the README whether the script is CLM-safe.

## Windows script

### Facts (Microsoft Learn: "Use PowerShell scripts on Windows devices in Intune")

- Added in **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**.
- File **less than 200 KB**, **ASCII**.
- **Runs once** per device or user. Re-runs only when the script or policy changes. A device-assigned
  script runs again for **every new user** who signs in (not on multi-session SKUs).
- On failure the Intune Management Extension (IME) **retries 3 times** at the next three IME check-ins
  (IME checks in every **8 hours** and after reboot), then stops.
- **Times out after 30 minutes.** Runs **before Win32 apps**.
- Settings and defaults:
  - **Run this script using the logged on credentials**: default **Yes** (user). **No** runs as SYSTEM.
    User-context scripts for users with admin rights run elevated.
  - **Enforce script signature check**: default **Yes**.
  - **Run script in 64-bit PowerShell host**: default **No** (32-bit). **Set it to Yes when you create the
    policy.** Changing an *existing* policy from No to Yes makes Intune open the script **without running it**.
- Reported **failed** on a non-zero exit code **or** any output to the error stream (`Write-Error`,
  uncaught errors). Nothing that isn't a real failure may reach the error stream.
- Targeting: device or user security groups. **Microsoft Entra joined** or **hybrid joined** devices get
  scripts. **Entra registered (workplace joined)** devices only get scripts assigned to **device groups**
  (user targeting is ignored). Microsoft's troubleshooting page says registered-only devices don't
  receive scripts, so treat registered devices as unsupported until tested.
- Not supported: Windows Home, S mode, Surface Hub. Scripts fail if the device clock is far out of date.
- Antivirus can sandbox `AgentExecutor.exe`. A script can report success without doing anything.

### Rules for the `.ps1`

Name it `<Verb>-<Noun>.ps1` with an approved verb (`Set-TimeZone.ps1`, `Add-NetworkDrive.ps1`).
Don't reuse a built-in cmdlet name (`Enable-OSDriveBitLocker.ps1`, not `Enable-BitLocker.ps1`).

- **Comment-based help** (`.SYNOPSIS`, `.DESCRIPTION`, `.NOTES`): every action in order, exit codes,
  Intune settings (user/SYSTEM, 64-bit, signature check), log path, and whether it's CLM-safe.
- **Settings block at the top**: clearly commented variables (values, URLs + SHA-256 hashes, an
  `$ExcludeList` where it makes sense). No hard-coded values buried in the code.
- **Run context**: SYSTEM for machine settings, HKLM, Program Files, services and installs. User for HKCU,
  the user's profile, mapped drives and per-user apps (users aren't admins). If both are needed, prefer
  SYSTEM and write to each user's hive or the Default profile, or explain the split.
- **64-bit**: write for the 64-bit host. If it must also be safe in a 32-bit host, relaunch through
  `$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe` when
  `[Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess`.
- **Windows PowerShell 5.1 only**: no PowerShell 7 syntax, no modules that aren't built into Windows.
  ASCII only. For downloads, set `[Net.ServicePointManager]::SecurityProtocol` to include TLS 1.2.
- **Logging**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<Name>PlatformScript.log` (SYSTEM)
  or `$env:TEMP\<Name>PlatformScript.log` (user).
- **Errors**: main body in `try/catch`. Use `-ErrorAction Stop` where failure must stop the script and
  `-ErrorAction SilentlyContinue` for expected misses. In `catch` use `$_.Exception.Message`.
- **Time limit**: give long steps (downloads, installs, waits) their own timeout so the script finishes
  well under 30 minutes.
- **Exit codes**: `exit 0` / `exit 1`. Use `3010` only if a pending restart must be visible, and explain
  that Intune shows it as failed.
- End with one short summary line via `Write-Output`.

## macOS script

### Facts (Microsoft Learn: "Use shell scripts on macOS devices in Intune")

- Added in **Devices > By platform > macOS > Manage devices > Scripts > Add**.
- macOS **12.0 or later**, Intune-managed, **direct internet connection (proxies aren't supported)**.
- Script file **less than 1 MB**. Must start with a **shebang** (`#!/bin/zsh`, `#!/bin/bash`, `#!/bin/sh`).
- Runs through the **Microsoft Intune management agent** (`/Library/Intune/Microsoft Intune Agent.app`),
  installed automatically when a script or custom attribute is assigned. The agent checks in every
  **8 hours** (users can trigger it with Company Portal > the device > **Check settings**).
- Settings and defaults:
  - **Run script as signed-in user**: default **No** = **root**. Yes runs for **every signed-in user**,
    and only when a user is signed in.
  - **Hide script notifications on devices**: default No. Users then see "IT is configuring your computer".
  - **Script frequency**: default **Not configured** = run **once**. With a frequency the script also runs
    after each restart, and can run more often (full disk, cache deleted).
  - **Max number of times to retry if script fails**: default Not configured = **no retry**.
- Scripts run **in parallel** as separate processes. Don't depend on another script's order or files,
  and use a lock file if two runs could collide.
- **Stopped and reported failed after 60 minutes.**
- **Failed** = non-zero exit code or malformed script. Status is reported when it **changes**, and the
  timestamp refreshes every 7 days. A frequency script doesn't report every run.
- Assignments: device or user groups. User-group assignment applies to any user signing in to the Mac.
- Role permission: **Device configurations**.

### Rules for the `.sh` / `.zsh`

Name it in kebab case after the action (`remove-local-admin-rights.sh`, `disable-sharing-services.zsh`).

- **Header comment block**: what it does, every action in order, exit codes, Intune settings
  (root or user, frequency, retries, hide notifications), log path.
- **Settings block at the top** (variables in capitals, exclusion arrays, URLs + SHA-256).
- **Only built-in macOS tools** (`zsh`/`bash`/`sh`, `defaults`, `dscl`, `dseditgroup`, `profiles`,
  `systemsetup`, `launchctl`, `fdesetup`, `csrutil`, `spctl`, `socketfilterfw`, `plutil`, `shasum`).
  **No Python** (removed in macOS 12.3), no Homebrew, no `jq` unless the script installs and verifies it.
- `set -u` and explicit checks after each command. Don't use `set -e` blindly; it hides which step failed.
- **Root vs user**: root for system settings (default). To change something for the signed-in user from a
  root script, get the console user with `stat -f%Su /dev/console` (skip `root`/`loginwindow`/empty) and
  run as them with `launchctl asuser <uid> sudo -u <user> <command>`.
- **Privacy (TCC)**: commands that need **Full Disk Access** (for example `systemsetup` remote login,
  reading other users' data) fail silently unless the Intune agent has it through a **PPPC** configuration
  profile. Say so in the README and point to `/new-configuration-policy` for the PPPC profile.
- **Logging**: `/Library/Logs/Microsoft/IntuneScripts/<TaskName>/<TaskName>.log` (root) or
  `$HOME/Library/Logs/<TaskName>.log` (user). Create the folder, and timestamp every line.
- **Apple Silicon / Intel**: check `uname -m` when behaviour differs (Rosetta 2, binary paths).
- **Exit codes**: `exit 0` success, `exit 1` failure (retries only happen if the retry setting is set).
- End with one summary line on stdout.

### Custom attribute variant (macOS reporting)

When the task only **reports** a value, build a custom attribute script instead:
- Added in **Devices > By platform > macOS > Organize devices > Custom attributes for macOS > Add**.
- Data type **String**, **Integer** or **Date** (ISO-8601). The script must **echo only the value**,
  matching the data type, and the result must be **20 KB or less**.
- Runs **every 8 hours**. The result shows in the **Result** column of Device status.
- No logging to stdout other than the value (log to the log file instead).

## README.md (step 4)

Write for an Intune admin who has never seen the script. Sections, in order:

1. **Title and overview**: what it does and why. Say why a script (not a setting, app or Remediation)
   is the right tool.
2. **Files**: table of the two files.
3. **Typical actions**: when to use it (scenarios), and what the script does step by step in a table
   (action -> what happens -> when it is skipped).
4. **Settings in the script**: each variable, its default and how to change it, with a code example.
5. **How Intune runs it**: the platform facts above that matter for this script (run once / frequency,
   re-runs, retries, timeout, parallel runs on macOS, before Win32 apps on Windows).
6. **Prerequisites**: OS version and edition, enrollment and join type (Windows) or macOS 12+ with the
   Intune agent and no proxy (macOS), PPPC / Full Disk Access if needed, network access, permissions,
   licenses, signing certificate (if signed).
7. **Step-by-step: add the script in Intune**: exact path, Basics (Name, Description), Script settings
   with the value **for this script and why** (Windows: logged-on credentials, signature check, 64-bit =
   **Yes**; macOS: run as signed-in user, hide notifications, frequency, retries), Scope tags,
   Assignments (device or user group and why, pilot group first), Review + add.
8. **Step-by-step: check the results**: Device status / User status, what success and failure look like,
   and how to check the change on a device.
9. **Running it again**: Windows: upload a changed script, or remove and re-add the assignment (re-runs
   for new users automatically). macOS: change the frequency, or upload a changed script.
10. **Undo** (when the change can be reverted): how to reverse it.
11. **Troubleshooting**: the script's log. Windows: `IntuneManagementExtension.log` and `AgentExecutor.log`
    in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`, local test with `psexec -i -s powershell.exe`,
    antivirus sandboxing. macOS: agent logs in `/Library/Logs/Microsoft/Intune/`, Company Portal
    **Check settings**, local test with `sudo zsh ./script.sh`, TCC and Full Disk Access errors.
    Plus the common errors for this task and their fixes.
12. **Exit codes**: table.

Plain, practical language: short sentences, exact menu paths and setting values.

## Before finishing

- **Windows**: the script parses with no errors (use PowerShell 7's parser if Windows PowerShell isn't
  available, and download PowerShell 7 into the scratchpad if `pwsh` is missing). Run PSScriptAnalyzer if
  it's available. ASCII only, under 200 KB.
- **macOS**: `zsh -n` / `bash -n` passes, and `shellcheck` passes if available (`.zsh` isn't supported by
  shellcheck, so re-read it carefully). Under 1 MB, valid shebang, LF line endings.
- Test every helper function you can on its own with fake data, especially the "is it already done?"
  checks.
- Re-read the script for bugs:
  - Windows: `$_` in `catch`, error-stream output on success, 32/64-bit registry and Program Files paths,
    user/SYSTEM context mistakes.
  - macOS: quoting, paths with spaces, console-user detection, root vs user, TCC-protected commands.
  - Both: hard-coded secrets, unverified downloads.
- Commit **only the new script directory** (and any removed `.gitkeep`) with a clear message plus the
  session's commit trailer, and push to the current branch (create a branch first if on `main`).
- Don't include this skill file in a script's commit. The skill is versioned in the repo, so changes
  to it are committed on their own.
- Tell me: the platform identified (and from what), why a script is the right tool, the folder and files
  created, what was and wasn't tested (scripts can't run on Windows or macOS here), anything that needs
  manual handling (PPPC, signing, placeholders), and the exact Intune settings to use.
