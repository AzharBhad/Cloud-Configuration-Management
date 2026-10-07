# Enable BitLocker

An Intune **platform script** that turns on BitLocker for the Windows (OS) drive on Windows 10 and Windows 11 devices.

Why use it:

- **Encrypts the OS drive.** Everything on the drive is unreadable without the device's TPM or the recovery key.
- **Protects company data if a device is lost or stolen.** Pulling the drive out or booting another operating system doesn't expose the data.
- **Stores the recovery key centrally.** The recovery key is saved to **Microsoft Entra ID** (Entra joined devices) and/or **Active Directory** (hybrid / domain joined devices) *before* encryption starts, so IT can always unlock the device.
- **Helps meet compliance requirements.** Intune compliance policies (Require BitLocker / Require encryption of data storage on device), ISO 27001, GDPR, HIPAA, Cyber Essentials and similar standards expect encrypted devices with recoverable keys.

## Files

| File | Purpose |
|---|---|
| `Enable-OSDriveBitLocker.ps1` | The platform script you upload to Intune. |
| `README.md` | This document. |

## Typical actions

### When to use this script

| Scenario | Why this script helps |
|---|---|
| **New device setup** (Autopilot or manual enrollment) | Turns BitLocker on as soon as the device is managed, before users store data on it. |
| **Devices enrolled without encryption** | One-time fix for a group of existing devices that were never encrypted. |
| **After a migration** (for example from Configuration Manager or another MDM) | Makes sure every migrated device ends up encrypted, with its key in Entra ID. |
| **After hardware repair or BIOS/TPM work** | Turns protection back on when it was left suspended. |
| **Compliance clean-up** | Fixes devices that show as non-compliant for "Require BitLocker". |

> A platform script runs **once**. If you need BitLocker checked and fixed **again and again** (for example if users or other tools turn it off), use the **Detect and Enable BitLocker** remediation in `Remediation/` as well. It runs on a schedule. Your Intune **disk encryption policy** (Endpoint security > Disk encryption) remains the place to define BitLocker settings.

### What the script does on the device

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | 64-bit check | Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit (the BitLocker commands only exist in 64-bit). | Already 64-bit. |
| 2 | Exclusions | Stops with success if the computer name matches `$ExcludeList`. | Name not in the list. |
| 3 | Read state | Reads the OS drive's BitLocker state. **Stops with failure** if the drive is being decrypted or in an unknown state. | - |
| 4 | TPM check | `Get-Tpm`: the TPM must be present and ready, so the drive can unlock at startup without user input. **Stops with failure** if not. | BitLocker already on. |
| 5 | TPM protector | Adds a TPM protector (`Add-BitLockerKeyProtector -TpmProtector`). | BitLocker already on, or the drive already has a TPM-based protector (TPM, TPM+PIN, ...). |
| 6 | Recovery password | Adds a recovery password protector (`Add-BitLockerKeyProtector -RecoveryPasswordProtector`). | The drive already has one. |
| 7 | Save the recovery key | Saves every recovery password to **Entra ID** (`BackupToAAD-BitLockerKeyProtector`) and/or **Active Directory** (`Backup-BitLockerKeyProtector`), based on how the device is joined. If nothing could be saved, **stops with failure and does not encrypt**. | Never - it always makes sure the key is saved. |
| 8 | Turn BitLocker on | **Not encrypted:** `manage-bde -on C: -UsedSpaceOnly -SkipHardwareTest -EncryptionMethod <method>`. **Suspended:** `Resume-BitLocker`. **Paused:** `manage-bde -resume`. | BitLocker already on. |
| 9 | Confirm | Re-reads the state for up to 30 seconds and reports the result. | - |

Notes:
- **Encryption method:** the method set by your Intune or Group Policy BitLocker settings is used. If none is set, `$DefaultEncryptionMethod` (XTS-AES 128, the Windows default) is used.
- **Used space only:** only space that holds data is encrypted, which is much faster. New data is encrypted as it is written.
- **Background encryption:** encryption keeps running after the script ends. Users can keep working, and the device is **never restarted**.

## Settings in the script

At the top of `Enable-OSDriveBitLocker.ps1`:

| Setting | Default | What it does |
|---|---|---|
| `$ExcludeList` | `@()` | Computer names to skip (wildcards allowed). |
| `$RequireKeyBackup` | `$true` | Only encrypt after the recovery key is saved. **Leave this on**: a drive encrypted without a saved key can be lost for good after a firmware or hardware change. |
| `$DefaultEncryptionMethod` | `'xts_aes128'` | Used when no policy sets the method. `xts_aes128`, `xts_aes256`, `aes128` or `aes256`. |
| `$CommandTimeoutSeconds` | `300` | Time limit for each `manage-bde` command. |

Example:

```powershell
$ExcludeList = @('KIOSK-*', 'LAB-PC01')
$RequireKeyBackup = $true
$DefaultEncryptionMethod = 'xts_aes256'
```

## How Intune runs it

| Intune behavior | What it means for this script |
|---|---|
| **Runs once** per device | BitLocker is turned on once. If someone turns it off later, this script won't notice - use the **Detect and Enable BitLocker** remediation for that. |
| **Re-runs after you change the script** | Safe: every step checks the current state first, so an already encrypted device only gets its recovery key saved again. |
| **Re-runs for every new user** who signs in (device assignment) | Safe for the same reason. |
| **Retries 3 times** at the next three check-ins after a failure | Devices that weren't ready (no network to save the key, TPM not ready) get three more chances. After that, fix the cause and re-run (see *Running it again*). |
| **30-minute time limit** | The script normally takes under a minute; each `manage-bde` call is limited to 5 minutes. Encryption itself runs in the background and is not limited. |
| **Runs before Win32 apps** | BitLocker starts early on new devices, before apps are installed. |

## Prerequisites

- **Windows 10 or Windows 11 Pro, Enterprise or Education.** BitLocker is not available on Windows Home.
- Devices **enrolled in Intune** and **Microsoft Entra joined** or **hybrid joined**. Devices that are only Entra *registered* don't receive platform scripts.
- A **TPM 1.2 or 2.0**, turned on in the device firmware (BIOS/UEFI).
- **Network access** to Microsoft Entra ID (Entra joined) or a domain controller (hybrid joined) when the script runs, so the recovery key can be saved. For AD, BitLocker recovery information backup to AD DS must be allowed.
- No BitLocker policy that **requires a startup PIN** or startup key - a script can't set those silently. Those devices will fail with a message about the authentication method.
- An Intune role that can add platform scripts, such as **Intune Administrator** or **Policy and Profile Manager**.

## Step-by-step: add the script in Intune

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**.
3. **Basics**
   - **Name**: `Enable BitLocker`
   - **Description**: `Turns on BitLocker for the OS drive and saves the recovery key to Entra ID / AD.`
   - Select **Next**.
4. **Script settings**
   - **Script location**: browse to `Enable-OSDriveBitLocker.ps1`.
   - **Run this script using the logged on credentials**: **No**. The script must run as **SYSTEM**: turning on BitLocker and saving the recovery key need admin rights, which users usually don't have.
   - **Enforce script signature check**: **No** (unless you sign the script with a certificate your devices trust).
   - **Run script in 64-bit PowerShell host**: **Yes**. The BitLocker commands only exist in 64-bit PowerShell. (The script also relaunches itself in 64-bit if this is left at No.)
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select a **device group** - for example all Windows 10/11 corporate devices, or an Autopilot device group. BitLocker is a device setting, so assign to devices, not users. Start with a small **pilot group**.
   - Select **Next**.
7. **Review + add**: check the settings and select **Add**.

The script runs at the device's next Intune Management Extension check-in, after a restart, or within about an hour.

## Step-by-step: check the results

1. Go to **Devices > Scripts and remediations > Platform scripts** and open **Enable BitLocker**.
2. Open **Device status** (and **User status**) to see each device:
   - **Success** - BitLocker is on or encrypting, and the recovery key is saved.
   - **Failed** - see the reason in the device's log file (below). Intune retries 3 times.
3. Check the recovery key was saved: **Devices > All devices > (device) > Recovery keys**, or in the Microsoft Entra admin center under **Devices > All devices > (device) > BitLocker keys**.
4. Check encryption on the device:
   ```powershell
   Get-BitLockerVolume -MountPoint C: | Select-Object VolumeStatus, ProtectionStatus, EncryptionPercentage, EncryptionMethod, KeyProtector
   manage-bde -status C:
   ```
5. Check compliance: **Devices > Monitor > Encryption report** shows each device's encryption state.

## Running it again

- **For all assigned devices:** edit the script (any change, even a comment), then upload the new version in the script's **Properties > Script settings**. Intune runs it again on every assigned device.
- **For specific devices:** remove them from the assigned group, wait for the next check-in, then add them back. Or assign the script to a new group containing just those devices.
- **New users:** a device-assigned script automatically runs again when a new user signs in. That is safe here; an encrypted device only gets its recovery key saved again.

## Undo

To turn BitLocker off on a device (for example for troubleshooting), run as an administrator:

```powershell
Disable-BitLocker -MountPoint C:
```

The drive is decrypted in the background. To stop BitLocker temporarily instead - for example for a BIOS update - use `Suspend-BitLocker -MountPoint C: -RebootCount 1`. Protection resumes after one restart.

Remove the script's assignment first, or it may run again. If the **Detect and Enable BitLocker** remediation or a disk encryption policy is assigned, it will turn BitLocker back on.

## Troubleshooting

- **Script log on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\EnableBitLockerPlatformScript.log` lists every step: the state found, the TPM check, the join state, each protector added, each backup and the `manage-bde` output.
- **Intune Management Extension logs** in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`:
  - `IntuneManagementExtension.log` - when the script was received and run, and its result.
  - `AgentExecutor.log` - the PowerShell run itself, including exit code and any error output.
- **BitLocker event log**: Event Viewer > Applications and Services Logs > Microsoft > Windows > BitLocker-API > Management.

| Message | Cause and fix |
|---|---|
| `Stopped: TPM not ready` | The TPM is off or not initialized. Turn it on in the firmware (BIOS/UEFI), or clear and re-initialize it in `tpm.msc`, then re-run. |
| `Stopped: the recovery key could not be saved...` | **Entra joined:** `dsregcmd /status` must show `AzureAdJoined : YES`, and the device must reach Microsoft Entra ID. **Hybrid joined:** a domain controller must be reachable, and AD backup of BitLocker recovery information must be allowed. The script retries at the next check-ins. |
| `manage-bde ... exit code` not 0, mentioning an authentication method or PIN | A BitLocker policy requires a startup PIN or key, so TPM-only can't be used. Change the policy, or turn BitLocker on with user interaction instead. |
| `Stopped: ... is being decrypted` | Someone or a policy is turning BitLocker off. Find the cause (BitLocker-API event log, recent policy changes) before turning it back on. |
| `BitLocker is on, but the recovery key could not be saved` | The drive is protected, but the key isn't saved in Entra ID / AD yet. Fix the connectivity issue above; the retry saves it. |
| Script shows **Failed** but the log looks fine | Something wrote to the error stream or the exit code wasn't 0 - check `AgentExecutor.log`. |

**Test on one device without Intune:** run the script as SYSTEM with [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec):

```cmd
psexec -i -s powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Enable-OSDriveBitLocker.ps1
```

## Exit codes

| Exit code | Meaning | What Intune does |
|---|---|---|
| `0` | BitLocker is on (or encryption has started) and the recovery key is saved, or the device is excluded. | Reports **Success**. Doesn't run again unless the script changes or a new user signs in. |
| `1` | Stopped or failed: TPM not ready, recovery key not saved, drive being decrypted, or BitLocker couldn't be turned on. See the log. | Reports **Failed** and retries at the next three check-ins. |
