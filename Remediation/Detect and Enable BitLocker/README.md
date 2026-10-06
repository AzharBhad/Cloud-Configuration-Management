# Detect and Enable BitLocker

An Intune **Remediations** package that finds Windows 10 and Windows 11 devices where BitLocker is not protecting the Windows (OS) drive and turns it on. The recovery key is saved to Microsoft Entra ID or Active Directory **before** encryption starts. Intune runs it every 7 days, so a device where BitLocker was turned off, suspended or never finished is protected again on the next run.

> Use this alongside an Intune **disk encryption policy** (Endpoint security > Disk encryption), not instead of it. The policy sets how BitLocker should be configured; this remediation catches devices where it didn't take effect or was turned off later.

## Files

| File | Purpose |
|---|---|
| `Detect-BitLocker.ps1` | Detection script. Exits `1` if BitLocker is off, suspended, paused or decrypting on the OS drive, `0` if it is protected. |
| `Remediate-BitLocker.ps1` | Remediation script. Runs only when detection exits `1`. Saves the recovery key, then turns BitLocker on. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If BitLocker is protecting the OS drive (or encryption is in progress), the device is reported as **Without issues** and nothing else happens.
3. Otherwise Intune runs the **remediation script**, which turns BitLocker on.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### What it detects

The BitLocker state of the OS drive (`%SystemDrive%`, normally `C:`):

| State | Reported as | Fixed by remediation |
|---|---|---|
| Fully encrypted, protection **On** | Compliant | - |
| Encryption **in progress** | Compliant (it will finish on its own) | - |
| **Not encrypted** | `NotEncrypted` | Yes - encryption is started |
| Encrypted, protection **suspended** (also "waiting for activation") | `ProtectionSuspended` | Yes - protection is resumed |
| Encryption **paused** | `EncryptionPaused` | Yes - encryption is resumed |
| **Being decrypted** | `Decrypting` | No - **skipped**, see below |

Only the OS drive is checked. For fixed data drives and removable drives, use the data-drive settings in your Intune disk encryption policy.

### How BitLocker is turned on

The remediation script works through these steps in order and stops at the first one that fails:

| Step | What happens |
|---|---|
| 1. TPM check | `Get-Tpm`. The TPM must be present and ready. Without it, BitLocker can't unlock the drive at startup without the user typing something, so the device is **skipped**. |
| 2. Key protectors | Adds a **TPM** protector and a **recovery password** protector if the drive doesn't have them. |
| 3. Recovery key backup | Saves each recovery password to **Microsoft Entra ID** (`BackupToAAD-BitLockerKeyProtector`) on Entra joined devices, and to **Active Directory** (`Backup-BitLockerKeyProtector`) on domain or hybrid joined devices. |
| 4. Turn on | Not encrypted: `manage-bde -on C: -UsedSpaceOnly -SkipHardwareTest -EncryptionMethod <method>`. Suspended: `Resume-BitLocker`. Paused: `manage-bde -resume`. |
| 5. Confirm | Re-reads the drive state for up to 30 seconds and reports the result. |

**The drive is never encrypted unless the recovery key is saved first.** If the backup fails in step 3 (for example no connection to Entra ID or a domain controller), the script stops without encrypting and reports **Failed**. It tries again on the next run. This is controlled by `$RequireKeyBackup` (default `$true`). Turning it off is not recommended: a drive encrypted without a saved recovery key can be lost for good after a firmware or hardware change.

**Encryption method**: if your Intune or Group Policy BitLocker settings set an encryption method for OS drives, that method is used. Otherwise `$DefaultEncryptionMethod` (default `xts_aes128`, the Windows default) is used.

**Used space only**: only the space that holds data is encrypted, which is much faster. New data is encrypted as it's written.

Encryption keeps running in the background after the script ends. The user can keep working, and **the device is not restarted**. Each `manage-bde` command has a 5-minute limit (`$CommandTimeoutSeconds`).

### Why "being decrypted" is skipped

A drive being decrypted means someone or something is deliberately turning BitLocker off: an admin, a policy, or a tool such as a firmware updater. Re-encrypting it automatically would fight that. The device reports **Failed** so you can find the cause.

### Skipping devices (optional)

To leave specific devices alone, for example kiosks or lab machines, add their **computer names** to `$ExcludeList` at the top of **both** scripts. Wildcards are allowed:

```powershell
$ExcludeList = @('KIOSK-*', 'LAB-PC01')
```

The two lists must match. Otherwise detection keeps reporting a device that remediation won't fix, and it shows as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11 Enterprise, Professional or Education**. BitLocker is not available on Windows Home.
- A **TPM 1.2 or 2.0** turned on in the device firmware.
- Devices enrolled in Intune and **Microsoft Entra joined** or **hybrid joined**, so the recovery key can be saved.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.
- If your BitLocker policy **requires a startup PIN**, this remediation can't turn BitLocker on silently (a PIN must come from the user). Those devices will report **Failed**.

## Step-by-step: create the remediation in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Enable BitLocker`
   - **Description**: `Detects when BitLocker is off on the OS drive, saves the recovery key to Entra ID / AD and turns BitLocker on. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-BitLocker.ps1`.
   - **Remediation script file**: upload `Remediate-BitLocker.ps1`.
   - **Run this script using the logged-on credentials**: **No** (runs as SYSTEM, which is needed to manage BitLocker).
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes** (the BitLocker cmdlets are 64-bit only).
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select **All devices**, or a device group of your Windows 10/11 devices. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days. Set **1** day if you want unprotected devices caught faster.
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open **Detect and Enable BitLocker**.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see the BitLocker state before and after.
4. **Check the recovery key was saved**: open the device under **Devices > All devices > (device) > Recovery keys**, or in the Microsoft Entra admin center under **Devices > All devices > (device) > BitLocker keys**.
5. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerRemediation.log`. Both scripts log the drive state; the remediation also logs the TPM check, join state, each protector added, each backup and the `manage-bde` output.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **Check BitLocker yourself**:
  ```powershell
  Get-BitLockerVolume -MountPoint C: | Select-Object VolumeStatus, ProtectionStatus, EncryptionPercentage, EncryptionMethod, KeyProtector
  manage-bde -status C:
  Get-Tpm
  ```
- **BitLocker event log**: Event Viewer > Applications and Services Logs > Microsoft > Windows > BitLocker-API > Management.
- **"TPM not ready"**: turn the TPM on in the device firmware (BIOS/UEFI), or clear and re-initialize it, then let the next run fix the device.
- **"The recovery key could not be backed up"**: on Entra joined devices, check the device can reach Microsoft Entra ID and that `dsregcmd /status` shows `AzureAdJoined : YES`. On hybrid joined devices, check the device can reach a domain controller and that AD backup of BitLocker keys is allowed.
- **manage-bde error about a startup PIN or authentication method**: your BitLocker policy requires a startup PIN or key, so TPM-only can't be used. Turn BitLocker on through the disk encryption policy with user interaction instead, or add the device to `$ExcludeList`.
- **"Being decrypted"**: find out who or what started decryption (BitLocker-API event log, recent policy changes, firmware update tools) before turning BitLocker back on.
- **Device shows "Failed" after a successful run**: encryption may not have reported "in progress" yet. The next run will show the device as compliant.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | BitLocker is protecting the OS drive, or encryption is in progress. Remediation does not run. |
| Detection | `1` | BitLocker is off, suspended, paused or decrypting. Intune runs the remediation script. |
| Remediation | `0` | BitLocker is on (or encryption has started), and the recovery key was saved. |
| Remediation | `1` | Skipped (TPM not ready, recovery key not saved, drive being decrypted) or BitLocker could not be turned on. See the log. |
