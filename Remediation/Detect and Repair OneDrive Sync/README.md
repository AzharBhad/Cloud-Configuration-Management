# Detect and Repair OneDrive Sync

An Intune **Remediations** package that finds users on Windows 10 and Windows 11 devices whose OneDrive for work or school isn't syncing - not running, not signed in, or with its sync folder missing - and repairs it.

It runs **as the signed-in user**, because OneDrive runs separately for each user.

## Files

| File | Purpose |
|---|---|
| `Detect-OneDriveSync.ps1` | Detection script. Exits `1` when OneDrive is not installed, not signed in, missing its folder or not running, `0` when healthy. |
| `Remediate-OneDriveSync.ps1` | Remediation script. Runs only when detection exits `1`. Starts OneDrive, lets it sign in silently, and optionally resets it. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If OneDrive is installed, signed in, its folder exists and it is running, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which repairs OneDrive.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

Checked in this order; the first problem found is reported:

| Issue | Meaning |
|---|---|
| `NotInstalled` | `OneDrive.exe` not found (per-machine in Program Files or per-user in `%LOCALAPPDATA%`) |
| `NotSignedIn` | No work or school account in OneDrive (`HKCU\Software\Microsoft\OneDrive\Accounts\Business1` has no `UserEmail`) |
| `SyncFolderMissing` | The account is set up but its sync folder no longer exists |
| `NotRunning` | OneDrive is not running in the user's session |

### How each problem is fixed

| Issue | Fix |
|---|---|
| `NotRunning` | Starts `OneDrive.exe /background`. |
| `NotSignedIn` | Starts OneDrive. If the policy **Silently sign in users to the OneDrive sync app with their Windows credentials** (`SilentAccountConfig`) is on, OneDrive signs in by itself. If it is off, the user must sign in - **skipped**. |
| `SyncFolderMissing` | Resets OneDrive (`OneDrive.exe /reset`) and starts it again - **only when `$AllowReset` is `$true`** (off by default). A reset doesn't delete files, but OneDrive re-syncs everything, which can take a long time and use a lot of bandwidth. |
| `NotInstalled` | **Skipped.** Deploy OneDrive with Intune - it ships with Windows and Microsoft 365 Apps. |

After a fix, the script waits up to 60 seconds for OneDrive to start and sign in. No files are deleted and the device is not restarted.

### Skipping users or allowing a reset (optional)

To leave specific users alone, add their **user names** to `$ExcludeList` at the top of **both** scripts. To let the remediation reset OneDrive when the sync folder is missing, set `$AllowReset` to `$true` in the **remediation** script.

```powershell
$ExcludeList = @('kiosk*', 'svc_*')
$AllowReset = $true
```

The settings at the top of the two scripts (`$ExcludeList`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- OneDrive installed on the devices.
- Recommended: the Intune policy **Silently sign in users to the OneDrive sync app with their Windows credentials** (Settings catalog > OneDrive), so users who aren't signed in are fixed without their help.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Repair OneDrive Sync`
   - **Description**: `Repairs OneDrive for work or school sync: starts OneDrive, signs users in silently and optionally resets it. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-OneDriveSync.ps1`.
   - **Remediation script file**: upload `Remediate-OneDriveSync.ps1`.
   - **Run this script using the logged-on credentials**: **Yes** (runs as the signed-in user - OneDrive runs per user and SYSTEM can't see or start a user's OneDrive).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes**.
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select a **user group** (or **All users**) - the scripts run for whoever is signed in. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days. The scripts only run while a user is signed in.
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Repair OneDrive Sync**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see the user, their OneDrive account and folder, and the problem found.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `%TEMP%\OneDriveSyncRemediation.log (in the user's profile)`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **The log is in the user's profile**, not the Intune log folder (users can't write there): `%TEMP%\OneDriveSyncRemediation.log`.
- **"OneDrive is not signed in and the SilentAccountConfig policy is off"**: turn on silent sign-in in Intune (Settings catalog > OneDrive > **Silently sign in users to the OneDrive sync app with their Windows credentials**), or ask the user to sign in.
- **"the OneDrive sync folder is missing"**: the user may have moved or deleted the folder. Reset OneDrive by hand (`%LOCALAPPDATA%\Microsoft\OneDrive\OneDrive.exe /reset`) or set `$AllowReset = $true`.
- **"OneDrive still has a problem"** right after a fix: signing in can take longer than 60 seconds. The next run checks again.
- **Sync errors inside OneDrive** (files that won't upload, name conflicts) aren't detected - check the OneDrive icon in the taskbar, or the OneDrive sync health report in the Microsoft 365 Apps admin center.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | OneDrive is healthy for the signed-in user. Remediation does not run. |
| Detection | `1` | A OneDrive problem was found. Intune runs the remediation script. |
| Remediation | `0` | OneDrive repaired. |
| Remediation | `1` | A problem remains (not installed, user must sign in, reset not allowed, or still signing in). See the log. |
