# Detect and Rotate BitLocker Recovery Keys

An Intune **Remediations** package that rotates the BitLocker recovery password of the Windows (OS) drive on Windows 10 and Windows 11 devices every 90 days. The new recovery password is saved to Microsoft Entra ID or Active Directory **before** the old one is removed, so the drive always has a recovery password that is saved somewhere.

Rotating recovery keys limits the damage when a key has been shown to a user or helpdesk agent, or exposed in a ticket.

> Intune can also rotate a single device's key on demand (**Devices > (device) > ... > BitLocker key rotation**). This remediation does it on a schedule for every device.

## Files

| File | Purpose |
|---|---|
| `Detect-BitLockerKeyRotation.ps1` | Detection script. Exits `1` when the recovery password is due for rotation, `0` when it is current. |
| `Remediate-BitLockerKeyRotation.ps1` | Remediation script. Runs only when detection exits `1`. Adds a new recovery password, backs it up, then removes the old ones. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If the recovery password is current, the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which rotates the recovery password.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

Only devices where the OS drive is BitLocker protected (fully encrypted with protection On, or encryption in progress) are checked. Other devices are reported as compliant - turning BitLocker on is done by the **Detect and Enable BitLocker** remediation.

The OS drive needs rotation when:

| Condition | Output |
|---|---|
| The drive has no recovery password protector | `No recovery password protector` |
| This remediation has never rotated the key on this device | `Never rotated by this remediation` - so the **first run rotates every device once** |
| The last rotation was more than `$RotationDays` days ago (default **90**) | `Last rotated N days ago` |

The time of the last rotation is stored in `HKLM\SOFTWARE\IntuneRemediation\BitLockerKeyRotation` (value `LastRotation`).

### How the key is rotated

| Step | What happens |
|---|---|
| 1. Add | `Add-BitLockerKeyProtector -RecoveryPasswordProtector` adds a **new** recovery password. |
| 2. Back up | The new recovery password is saved to **Microsoft Entra ID** (`BackupToAAD-BitLockerKeyProtector`) on Entra joined devices, and to **Active Directory** (`Backup-BitLockerKeyProtector`) on domain or hybrid joined devices. |
| 3a. Backup worked | The **old** recovery password protectors are removed and the rotation time is recorded. |
| 3b. Backup failed | The new protector is removed again and the old ones are kept. The device reports **Failed** and tries again on the next run. |

The drive stays encrypted the whole time. Nothing is decrypted, the user isn't interrupted, and the device is not restarted. In Entra ID, old keys stay listed against the device; the newest one is the one that works.

### Skipping devices (optional)

To leave specific devices alone, add their **computer names** to `$ExcludeList` at the top of **both** scripts. Wildcards are allowed. To change how often keys are rotated, change `$RotationDays` in the **detection** script.

```powershell
$ExcludeList = @('KIOSK-*', 'LAB-PC01')
$RotationDays = 180
```

The settings at the top of the two scripts (`$ExcludeList`) must match. Otherwise detection keeps reporting something that remediation won't fix, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- The OS drive encrypted with BitLocker.
- Devices must be able to reach Microsoft Entra ID (or a domain controller for hybrid joined devices) when the remediation runs.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Rotate BitLocker Recovery Keys`
   - **Description**: `Rotates the BitLocker recovery password of the OS drive every 90 days, saving the new key to Entra ID / AD before removing the old one. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-BitLockerKeyRotation.ps1`.
   - **Remediation script file**: upload `Remediate-BitLockerKeyRotation.ps1`.
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

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Rotate BitLocker Recovery Keys**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see why rotation was due and the ID of the new recovery password.
   Then check the new key was saved: open the device under **Devices > All devices > (device) > Recovery keys**.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerKeyRotationRemediation.log`. Both scripts log what they found and what they changed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Check the protectors yourself**:
  ```powershell
  (Get-BitLockerVolume -MountPoint C:).KeyProtector | Select-Object KeyProtectorType, KeyProtectorId
  Get-ItemProperty HKLM:\SOFTWARE\IntuneRemediation\BitLockerKeyRotation
  ```
- **"Rotation skipped: the new recovery password could not be backed up"**: on Entra joined devices, check that `dsregcmd /status` shows `AzureAdJoined : YES` and that the device can reach Microsoft Entra ID. On hybrid joined devices, check that a domain controller can be reached and that AD backup of BitLocker keys is allowed.
- **"old protectors could not be removed"**: the new key is saved and works. Remove the old protector by hand with `Remove-BitLockerKeyProtector`, or let the next run try again after the rotation interval.
- **BitLocker event log**: Event Viewer > Applications and Services Logs > Microsoft > Windows > BitLocker-API > Management.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | The recovery password is current, or the OS drive is not BitLocker protected. Remediation does not run. |
| Detection | `1` | Rotation is due. Intune runs the remediation script. |
| Remediation | `0` | Recovery password rotated and backed up; old protectors removed. |
| Remediation | `1` | Rotation skipped (backup failed) or old protectors could not be removed. The drive still has a working, saved recovery password. See the log. |
