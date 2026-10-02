# Detect and Remove Adobe Packages

An Intune **Remediations** package that finds Adobe software on Windows 10 and Windows 11 devices and silently removes it. Intune runs it every 7 days, so Adobe software that users reinstall is removed again on the next run.

## Files

| File | Purpose |
|---|---|
| `Detect-AdobePackages.ps1` | Detection script. Exits `1` if any Adobe package is found, `0` if none. |
| `Remediate-AdobePackages.ps1` | Remediation script. Runs only when detection exits `1`, and removes every Adobe package it finds. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If no Adobe software is found, the device is reported as **Without issues** and nothing else happens.
3. If Adobe software is found, Intune runs the **remediation script**, which uninstalls it.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What counts as an Adobe package

Anything whose **Publisher** or **Display name** starts with `Adobe`, found in:

- **Installed programs (Win32 / MSI)**: the 64-bit and 32-bit uninstall registry keys under `HKLM`.
- **Per-user installed programs**: the uninstall registry keys of every signed-in user (`HKU`).
- **Microsoft Store apps (AppX / MSIX)**: installed for any user, plus provisioned packages in the Windows image (so they aren't installed for new users).

Examples: Adobe Acrobat, Acrobat Reader, Creative Cloud and its apps (Photoshop, Illustrator, etc.), Adobe Express and other Adobe Store apps.

### How each package is removed

| Package type | Method |
|---|---|
| MSI | `msiexec.exe /x {ProductCode} /qn /norestart` |
| Program with a silent uninstall command (`QuietUninstallString`) | That command is run as-is |
| Adobe Creative Cloud desktop app | `Creative Cloud Uninstaller.exe -u` |
| Store (AppX / MSIX) app | `Remove-AppxPackage -AllUsers` and `Remove-AppxProvisionedPackage -Online` |
| Any other EXE uninstaller | **Skipped and logged** - no silent switch is known, so running it could show a prompt and hang |

Creative Cloud apps are removed before the Creative Cloud desktop app. Each uninstall is stopped if it runs longer than 15 minutes (`$UninstallTimeoutMinutes`), so the script finishes inside Intune's time limit. The device is **not** restarted; some uninstalls finish at the next restart.

### Keeping some Adobe software (optional)

To keep a product, for example Acrobat Reader, add its display name to `$ExcludeList` at the top of **both** scripts. Wildcards are allowed:

```powershell
$ExcludeList = @('Adobe Acrobat Reader*', 'Adobe Acrobat (64-bit)')
```

The two lists must match. Otherwise detection keeps finding a product that remediation won't remove, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Remove Adobe Packages`
   - **Description**: `Detects all Adobe software and silently removes it. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-AdobePackages.ps1`.
   - **Remediation script file**: upload `Remediate-AdobePackages.ps1`.
   - **Run this script using the logged-on credentials**: **No** (runs as SYSTEM, which is needed to uninstall software).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes** (needed to see 64-bit programs and Store apps).
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select the device or user groups to target. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Remove Adobe Packages**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see which Adobe packages were found and what was removed.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeRemediation.log`. Both scripts write each package found, the command used to remove it and the result.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Device reports "Failed"**: look in `AdobeRemediation.log` for lines starting with `Failed`, `Timed out` or `Skipped`.
  - *Skipped* means the program has no known silent uninstall method. Remove it another way (for example with Adobe's uninstaller from the Adobe Admin Console) or add it to `$ExcludeList`.
  - *Exit code 1618* means another installation was running. The next scheduled run usually succeeds.
- **Adobe software keeps coming back**: check for another Intune app assignment, a Configuration Manager deployment or a Store app policy that reinstalls it.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | No Adobe packages found. Remediation does not run. |
| Detection | `1` | Adobe packages found. Intune runs the remediation script. |
| Remediation | `0` | All Adobe packages removed. |
| Remediation | `1` | One or more packages could not be removed. See the log. |
