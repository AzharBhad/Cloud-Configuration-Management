# Detect and Fix Device Encryption Settings

An Intune **Remediations** package that finds non-compliant BitLocker settings on Windows 10 and Windows 11 devices and fixes them: missing key protectors, recovery passwords that aren't saved, fixed data drives that aren't encrypted or don't unlock automatically.

> This package works alongside **Detect and Enable BitLocker**, which turns BitLocker on for the OS drive. This one fixes the settings around it, and covers fixed data drives. Your Intune **disk encryption policy** (Endpoint security > Disk encryption) remains the place where the required settings are defined.

## Files

| File | Purpose |
|---|---|
| `Detect-EncryptionSettings.ps1` | Detection script. Exits `1` when any drive has non-compliant encryption settings, `0` when all are compliant. |
| `Remediate-EncryptionSettings.ps1` | Remediation script. Runs only when detection exits `1`. Adds missing protectors (backing up recovery passwords), encrypts fixed data drives and turns on auto-unlock. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If all drives have compliant encryption settings, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which fixes the settings it can.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

| Drive | Issue | Meaning |
|---|---|---|
| OS drive | `MissingTpmProtector` | No TPM key protector (the drive needs another way to unlock at startup) |
| OS drive | `MissingRecoveryPassword` | No recovery password - the drive can't be recovered if the TPM fails |
| Any | `WeakEncryptionMethod:<method>` | Encryption method not in `$AllowedEncryptionMethods` (default XTS-AES 128 and XTS-AES 256) |
| Fixed data drive | `NotEncrypted` | BitLocker is off |
| Fixed data drive | `EncryptionPaused` | Encryption was paused |
| Fixed data drive | `Decrypting` | The drive is being decrypted |
| Fixed data drive | `MissingRecoveryPassword` | No recovery password |
| Fixed data drive | `AutoUnlockOff` | The drive doesn't unlock automatically when Windows starts |
| Fixed data drive | `Locked` | The drive is locked, so it can't be checked |

The OS drive is only checked when it is already encrypted or encrypting. Removable drives (USB) are not checked.

### How each issue is fixed

| Issue | Fix |
|---|---|
| `MissingTpmProtector` | `Add-BitLockerKeyProtector -TpmProtector` |
| `MissingRecoveryPassword` | Adds a recovery password, then saves it to **Microsoft Entra ID** and/or **Active Directory**. If the backup fails, the new password is removed again. |
| `NotEncrypted` | Only when the OS drive is protected. Adds and backs up a recovery password **first**, then `manage-bde -on <drive> -UsedSpaceOnly` with the data-drive encryption method from your Intune / Group Policy settings (or `$DefaultEncryptionMethod`, XTS-AES 128), then turns on auto-unlock. A drive is never encrypted without a saved recovery password. |
| `EncryptionPaused` | `manage-bde -resume` |
| `AutoUnlockOff` | `Enable-BitLockerAutoUnlock` (needs the OS drive protected) |
| `WeakEncryptionMethod` | **Skipped.** Changing the method needs a full decrypt and re-encrypt; do it by hand during a maintenance window. |
| `Decrypting` | **Skipped.** Someone or a policy is turning BitLocker off on purpose. |
| `Locked` | **Skipped.** Unlock the drive first. |

The OS drive is fixed first, so data drives can use auto-unlock. Encryption runs in the background; the device is never restarted.

### Skipping drives or changing the allowed methods (optional)

To leave a drive alone, add its **mount point** to `$ExcludeList` at the top of **both** scripts. To accept other encryption methods, change `$AllowedEncryptionMethods` in **both** scripts.

```powershell
$ExcludeList = @('E:')
$AllowedEncryptionMethods = @('XtsAes128', 'XtsAes256', 'Aes256')
```

The settings at the top of the two scripts (`$ExcludeList`, `$AllowedEncryptionMethods`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- A TPM turned on in the device firmware, and the OS drive encrypted (use **Detect and Enable BitLocker** for that).
- Devices must be able to reach Microsoft Entra ID (or a domain controller for hybrid joined devices) so recovery passwords can be saved.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Fix Device Encryption Settings`
   - **Description**: `Fixes non-compliant BitLocker settings: missing protectors, unsaved recovery passwords, unencrypted fixed data drives and auto-unlock. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-EncryptionSettings.ps1`.
   - **Remediation script file**: upload `Remediate-EncryptionSettings.ps1`.
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

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Fix Device Encryption Settings**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see each drive and issue found, and which were fixed.
   Check new recovery keys under **Devices > All devices > (device) > Recovery keys**.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\EncryptionSettingsRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Check BitLocker yourself**:
  ```powershell
  Get-BitLockerVolume | Select-Object MountPoint, VolumeType, VolumeStatus, ProtectionStatus, EncryptionMethod, AutoUnlockEnabled, KeyProtector
  manage-bde -status
  ```
- **`WeakEncryptionMethod` keeps the device Failed**: either re-encrypt the drive by hand (`manage-bde -off`, wait for decryption, then let this remediation or your policy encrypt it again) or add the method to `$AllowedEncryptionMethods`.
- **Data drive "skipped: encrypt the OS drive first"**: deploy **Detect and Enable BitLocker** or your disk encryption policy so the OS drive is protected; the next run encrypts the data drive.
- **Backup failures**: check `dsregcmd /status` shows `AzureAdJoined : YES` (or a domain controller is reachable for hybrid joined devices).
- **BitLocker event log**: Event Viewer > Applications and Services Logs > Microsoft > Windows > BitLocker-API > Management.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | All checked drives have compliant encryption settings. Remediation does not run. |
| Detection | `1` | One or more settings are non-compliant. Intune runs the remediation script. |
| Remediation | `0` | All issues fixed. |
| Remediation | `1` | One or more issues were skipped (weak method, decrypting, locked) or could not be fixed. See the log. |
