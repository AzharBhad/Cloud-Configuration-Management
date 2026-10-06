# Detect and Clear Temporary Files

An Intune **Remediations** package that finds Windows 10 and Windows 11 devices where old temporary files and caches take up more than 1 GB, and deletes them to free disk space.

## Files

| File | Purpose |
|---|---|
| `Detect-TempFiles.ps1` | Detection script. Exits `1` when old temporary files add up to more than `$ThresholdMB` MB, `0` when below. |
| `Remediate-TempFiles.ps1` | Remediation script. Runs only when detection exits `1`. Deletes old temporary files and caches, and empty folders left behind. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If old temporary files are below the threshold, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which deletes the old files.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

Files older than `$MinFileAgeDays` days (default **7**) in:

| Location | Path |
|---|---|
| Windows temp | `C:\Windows\Temp` |
| Each user's temp | `C:\Users\<user>\AppData\Local\Temp` |
| Each user's Internet cache | `...\AppData\Local\Microsoft\Windows\INetCache` |
| Each user's Edge and Chrome caches | `...\User Data\<profile>\Cache` and `Code Cache` |
| Each user's crash dumps | `...\AppData\Local\CrashDumps` |
| Windows Update download cache | `C:\Windows\SoftwareDistribution\Download` |
| Delivery Optimization cache | `C:\Windows\ServiceProfiles\NetworkService\...\DeliveryOptimization\Cache` |

The device is reported when they add up to more than `$ThresholdMB` MB (default **1024**). The output lists the folders using 100 MB or more.

Only files older than 7 days count, so files that apps are using right now are left alone.

### How files are removed

| Step | What happens |
|---|---|
| Delivery Optimization | `Delete-DeliveryOptimizationCache -Force` |
| Each location | Deletes files older than `$MinFileAgeDays` days, then removes sub-folders left empty. The top folders themselves are kept. |
| Files in use | Skipped silently - that is normal. They are tried again on the next run. |
| Time limit | Stops after `$TimeoutMinutes` minutes (default 40) so the script finishes inside Intune's 60-minute limit. |

**Junctions and symbolic links are never followed**, so nothing outside these folders can be deleted. Documents, Downloads, Desktop and the Recycle Bin are not touched. No restart is needed.

### Skipping folders or changing the limits (optional)

To leave a folder alone, add its path to `$ExcludeList` at the top of **both** scripts (wildcards allowed). To change what counts as old or the size limit, change `$MinFileAgeDays` and `$ThresholdMB` in **both** scripts.

```powershell
$ExcludeList = @('*\Google\Chrome\*', 'C:\Users\svc_*')
$MinFileAgeDays = 14
$ThresholdMB = 2048
```

The settings at the top of the two scripts (`$ExcludeList`, `$MinFileAgeDays`, `$ThresholdMB`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Clear Temporary Files`
   - **Description**: `Deletes temporary files and caches older than 7 days when they use more than 1 GB. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-TempFiles.ps1`.
   - **Remediation script file**: upload `Remediate-TempFiles.ps1`.
   - **Run this script using the logged-on credentials**: **No** (runs as SYSTEM, which is needed to make these changes).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes**.
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select **All devices**, or a device group of your Windows 10/11 devices. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days.
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Clear Temporary Files**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see how much space old temporary files used, the largest folders, and how much was freed.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TempFilesRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **"still above the threshold"**: many files were in use (for example a browser cache while the browser is open) or the time limit was reached. The next run continues.
- **Disk still full after cleanup**: the space is used elsewhere. Check with `Get-ChildItem C:\ -Directory | ForEach-Object { ... }` or a tool such as Storage settings (**Settings > System > Storage**). Turning on **Storage Sense** through Intune (Settings catalog > Storage) helps keep space free between runs.
- **A browser cache is rebuilt quickly**: that is normal; browsers recreate their caches as users browse.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | Old temporary files are below the threshold. Remediation does not run. |
| Detection | `1` | Old temporary files are above the threshold. Intune runs the remediation script. |
| Remediation | `0` | Old temporary files are now below the threshold. |
| Remediation | `1` | Still above the threshold (files in use, or the time limit was reached). See the log. |
