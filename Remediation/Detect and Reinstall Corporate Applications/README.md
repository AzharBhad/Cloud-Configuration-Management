# Detect and Reinstall Corporate Applications

An Intune **Remediations** package that checks Windows 10 and Windows 11 devices for a list of required corporate applications and reinstalls any that are missing - for example after a user uninstalled them.

The list of required apps is `$RequiredApps` at the top of both scripts. **Edit it for your organization before deploying.**

## Files

| File | Purpose |
|---|---|
| `Detect-CorporateApps.ps1` | Detection script. Exits `1` when any app in `$RequiredApps` is missing, `0` when all are installed. |
| `Remediate-CorporateApps.ps1` | Remediation script. Runs only when detection exits `1`. Reinstalls missing apps with winget or an install command, or asks Intune to re-check its own app assignments. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If all required apps are installed, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which reinstalls the missing apps.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### The required apps list

Each entry in `$RequiredApps` says how to find the app and how to install it:

| Field | Meaning |
|---|---|
| `Name` | Name used in logs and `$ExcludeList` |
| `DetectType` | `Win32` - looked up by **DisplayName** in installed programs (HKLM, 64-bit and 32-bit). `Appx` - looked up by **package name** (installed for any user, or provisioned). |
| `DetectName` | The DisplayName or package name, wildcards allowed |
| `InstallType` | `Winget`, `Command` or `Intune` - see below |

The default list has two examples - **Microsoft Edge** (installed with winget) and **Company Portal** (deployed by Intune). Commented examples show an Intune-deployed Teams and an MSI on a file share:

```powershell
@{ Name = 'Contoso VPN'; DetectType = 'Win32'; DetectName = 'Contoso VPN Client*'
   InstallType = 'Command'; FilePath = 'msiexec.exe'; Arguments = '/i "\\fileserver\apps\ContosoVPN.msi" /qn /norestart' }
```

To find the right `DetectName`, look in **Settings > Apps > Installed apps** (Win32) or run `Get-AppxPackage -AllUsers | Select-Object Name` (Appx).

### How each app is reinstalled

| InstallType | What happens |
|---|---|
| `Winget` | `winget install --id <InstallId> --exact --source <Source> --silent --accept-package-agreements --accept-source-agreements` (plus `--scope machine` for the `winget` source). winget isn't on the PATH for SYSTEM, so `winget.exe` is found in the App Installer package folder. |
| `Command` | Runs `FilePath` with `Arguments` - for example `msiexec /i "\\server\share\app.msi" /qn /norestart`. The file share must allow the **computer account** to read it, because the script runs as SYSTEM. |
| `Intune` | For apps that Intune itself deploys: schedules a one-time restart of the **Microsoft Intune Management Extension** service 2 minutes later (after the script finishes). The service checks its required app assignments when it starts and reinstalls missing apps. It can't be restarted directly because it is the service running this script. |

Exit codes `0`, `3010` and `1641` count as success, and so do winget's "already installed" codes. Each install is stopped after 15 minutes (`$InstallTimeoutMinutes`). The device is never restarted.

`Intune` apps are reinstalled by the Intune Management Extension afterwards, so the remediation reports success once the re-check is scheduled; the next detection run confirms the app is back.

### Skipping apps (optional)

To stop checking an app, add its **Name** to `$ExcludeList` at the top of **both** scripts. `$RequiredApps` must also be the same in both scripts.

```powershell
$ExcludeList = @('Company Portal')
```

The settings at the top of the two scripts (`$ExcludeList`, `$RequiredApps`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- For `Winget` apps: **App Installer** (winget) on the devices - it is built into Windows 11 and current Windows 10.
- For `Intune` apps: the app assigned as **Required** to the device or user in Intune.
- For `Command` apps: the installer reachable by the computer account.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Reinstall Corporate Applications`
   - **Description**: `Reinstalls missing required corporate apps with winget, an install command, or an Intune re-check. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-CorporateApps.ps1`.
   - **Remediation script file**: upload `Remediate-CorporateApps.ps1`.
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

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Reinstall Corporate Applications**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see which apps were missing and which were reinstalled.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\CorporateAppsRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Winget install fails**: run the same `winget install` command on the device as an admin and read the error. Common causes: App Installer too old (update it from the Microsoft Store), no internet access to the winget source, or the package ID changed (`winget search <name>`).
- **"winget (App Installer) is not installed"**: install App Installer, or switch the app to `Command` or `Intune`.
- **An `Intune` app doesn't come back**: check the app's assignment is **Required** for this device or user, and look at its install status under **Apps > (app) > Device install status**. After a failed install, Intune waits before retrying (up to 24 hours).
- **A `Command` install fails with access denied**: give the computer account (`DOMAIN\COMPUTER$`, or **Domain Computers**) read access to the share.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | All required apps are installed. Remediation does not run. |
| Detection | `1` | One or more required apps are missing. Intune runs the remediation script. |
| Remediation | `0` | All missing apps were reinstalled (or, for Intune apps, a re-check was scheduled). |
| Remediation | `1` | One or more apps could not be installed. See the log. |
