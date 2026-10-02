# Detect and Install Windows Updates

An Intune **Remediations** package for Windows 10 and Windows 11 devices. It refreshes Group Policy with `gpupdate /force`, finds Windows updates that are released to the device but not installed yet, and installs them silently. Intune runs it every 7 days, so devices that fall behind are brought up to date on the next run.

## Files

| File | Purpose |
|---|---|
| `Detect-WindowsUpdates.ps1` | Detection script. Runs `gpupdate /force`, then exits `1` if any update is waiting to be installed, `0` if none. |
| `Remediate-WindowsUpdates.ps1` | Remediation script. Runs only when detection exits `1`. Runs `gpupdate /force`, then downloads and installs the pending updates. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script**. It runs `gpupdate /force`, then scans for pending updates.
2. If nothing is pending, the device is reported as **Without issues** and nothing else happens.
3. If updates are pending, Intune runs the **remediation script**. It runs `gpupdate /force` again, then downloads and installs the updates.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### Why gpupdate runs in both scripts

Intune only runs the remediation script when detection finds something. Putting `gpupdate /force` in the detection script as well makes it run on **every** scheduled run, even when the device is already up to date. Running it before the scan also means the latest Windows Update policy is used for the scan (WSUS server, deferral and target-version settings from Group Policy).

`gpupdate /force` refreshes **domain Group Policy** and local policy. On devices that are only Microsoft Entra joined (not hybrid joined), there is no domain Group Policy to download, so it does very little. Intune's own policies, such as update rings, are applied by Intune sync, not by `gpupdate`.

### What counts as a pending update

The scripts ask the Windows Update Agent for updates matching:

```
IsInstalled=0 and Type='Software' and IsHidden=0
```

That means software updates (cumulative updates, security updates, .NET, Microsoft Defender security intelligence, servicing stack and so on) that the device has been offered but has not installed. Notes:
- **Driver updates are not included.**
- **Updates an admin has hidden are ignored.**
- **The scan uses the update source the device is set up for:** Windows Update, Windows Update for Business or WSUS. The scripts install what that source offers; they do not bypass deferrals or approvals set in Intune update rings or WSUS.

### How updates are installed

| Step | What happens |
|---|---|
| Refresh policy | `echo N \| gpupdate.exe /force`. The `N` answers the log off / restart prompt so it never waits for input. Stopped after 10 minutes. |
| Scan | Same query as the detection script, minus anything in `$ExcludeList`. |
| Filter | Updates that need user input are **skipped and logged**. License terms (EULAs) of the remaining updates are accepted. |
| Download and install | Through the Windows Update Agent, silently. Scan, download and install are stopped after 40 minutes (`$UpdateTimeoutMinutes`), so the script finishes inside Intune's 60-minute limit. Updates not installed in time are picked up on the next run. |
| Restart | **Never forced.** Updates that need a restart are reported as *restart pending* and finish at the user's next restart. |

### Leaving out some updates (optional)

To stop a specific update from being installed, add its KB number or title to `$ExcludeList` at the top of **both** scripts. Wildcards are allowed:

```powershell
$ExcludeList = @('KB5034441', '*Preview*')
```

The two lists must match. Otherwise detection keeps finding an update that remediation won't install, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.
- The **Windows Update** service (`wuauserv`) must not be disabled on the devices.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Install Windows Updates`
   - **Description**: `Runs gpupdate /force, detects pending Windows updates and installs them silently. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-WindowsUpdates.ps1`.
   - **Remediation script file**: upload `Remediate-WindowsUpdates.ps1`.
   - **Run this script using the logged-on credentials**: **No** (runs as SYSTEM, which is needed to install updates).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes**.
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select **All devices**, or a device group of your Windows 10/11 devices. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days. Set **1** day if you want `gpupdate /force` and the update check to run every day.
     - **Start time**: a time devices are usually on but not busy, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Install Windows Updates**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see which updates were pending and what was installed.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WindowsUpdatesRemediation.log`. Both scripts log the `gpupdate` result, each pending update, and whether each one installed, failed or was skipped.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Windows Update log**: run `Get-WindowsUpdateLog` in PowerShell on the device to create a readable `WindowsUpdate.log` on the desktop.
- **Device reports "Failed" with "restart pending" in the output**: the updates are installed but need a restart. Some updates still show as not installed until the device restarts, so detection may report them again. They clear after the restart.
- **Device reports "Failed" with "timed out"**: a large update (for example a feature update) took longer than 40 minutes. The next run continues where it stopped.
- **"Needs user input"**: the update can't be installed silently. Install it through Settings > Windows Update or add it to `$ExcludeList`.
- **"gpupdate /force" failed**: run `gpupdate /force` on the device by hand and check the error, usually no connection to a domain controller on hybrid joined devices.
- **Conflicts with update rings**: if Windows Update for Business update rings or WSUS also manage these devices, the scripts install only what those already offer. Check the ring's deferral and pause settings if expected updates are not found.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | No pending updates. Remediation does not run. |
| Detection | `1` | Pending updates found. Intune runs the remediation script. |
| Remediation | `0` | All pending updates installed (some may need a restart to finish). |
| Remediation | `1` | One or more updates were not installed, the install timed out, or `gpupdate /force` failed. See the log. |
