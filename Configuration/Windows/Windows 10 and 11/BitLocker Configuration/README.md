# BitLocker Configuration

**Silent BitLocker** encryption for Windows 10 and 11: OS and fixed drives encrypted with XTS-AES 256, TPM-only startup, recovery passwords escrowed to Microsoft Entra ID and rotated after use. Delivered as an Intune **Endpoint security > Disk encryption > BitLocker** policy.

## Purpose

Encrypting every corporate device protects data if a laptop is lost or stolen. It's also what your compliance policies check: [Require BitLocker](../../../../Compliance/Windows/Windows%2010%20and%2011/Require%20BitLocker) and [Device Storage Encryption](../../../../Compliance/Windows/Windows%2010%20and%2011/Device%20Storage%20Encryption).

This policy encrypts **silently**:
- there are no prompts, and standard users are supported;
- it uses the strongest ciphers;
- the recovery password must be **backed up to Microsoft Entra ID before encryption starts**;
- a recovery password is **rotated after it's used**, so a password read out by the help desk can't be reused.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - Bitlocker Configuration` (as shown in the screenshot) |
| Description | Silent BitLocker: require encryption, no third-party warning, standard-user encryption, XTS-AES 256, TPM-only startup, recovery password escrow to Entra ID + rotation. |
| Platform | Windows 10 and later |
| Profile type | Endpoint security > Disk encryption > **BitLocker** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. Tenants that manage devices through Defender for Endpoint security settings management show `mdm,microsoftSense`. |
| File | `BitLocker-Configuration.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: all corporate Windows devices (Entra joined or hybrid joined). |
| Supported OS | Windows 10 1909 or later / Windows 11 (Pro, Enterprise, Education). TPM 1.2+/2.0, UEFI and Secure Boot for silent encryption. |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the **BitLocker template ID** or the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### BitLocker

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Require Device Encryption | **Enabled** | `./Device/Vendor/MSFT/BitLocker/RequireDeviceEncryption` = 1 | Turns on encryption. |
| Allow Warning For Other Disk Encryption | **Disabled** | `./Device/Vendor/MSFT/BitLocker/AllowWarningForOtherDiskEncryption` = 0 | Required for **silent** encryption (no prompt about third-party encryption). |
| Allow Standard User Encryption | **Enabled** | `./Device/Vendor/MSFT/BitLocker/AllowStandardUserEncryption` = 1 | Encryption works when the signed-in user isn't an admin. |
| Configure Recovery Password Rotation | **Refresh on for both Entra ID-joined and hybrid-joined devices** | `./Device/Vendor/MSFT/BitLocker/ConfigureRecoveryPasswordRotation` = 2 | A new recovery password is generated after one is used. |

### BitLocker Drive Encryption

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Choose drive encryption method and cipher strength | **Enabled**: OS **XTS-AES 256**, Fixed **XTS-AES 256**, Removable **AES-CBC 256** | `./Device/Vendor/MSFT/BitLocker/EncryptionMethodByDriveType` | Strongest ciphers. AES-CBC for removable drives keeps them readable on older Windows. Only applies when encryption **starts**. |

### Operating System Drives

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Enforce drive encryption type on operating system drives | **Enabled: Used Space Only encryption** | `./Device/Vendor/MSFT/BitLocker/SystemDrivesEncryptionType` | Fast encryption for new and Autopilot devices. Use *Full* for re-used devices that held unencrypted data. |
| Require additional authentication at startup | **Enabled** | `./Device/Vendor/MSFT/BitLocker/SystemDrivesRequireStartupAuthentication` | Enabled so the TPM options can be set **for silent encryption**. |
|   > Allow BitLocker without a compatible TPM | **False** | (sub-setting) | TPM is required. |
|   > Configure TPM startup | **Allow TPM** | (sub-setting) | TPM-only unlock. |
|   > Configure TPM startup PIN | **Do not allow startup PIN with TPM** | (sub-setting) | A PIN would block silent encryption. |
|   > Configure TPM startup key | **Do not allow startup key with TPM** | (sub-setting) | Required for silent encryption. |
|   > Configure TPM startup key and PIN | **Do not allow startup key and PIN with TPM** | (sub-setting) | Required for silent encryption. |
| Choose how BitLocker-protected operating system drives can be recovered | **Enabled** | `./Device/Vendor/MSFT/BitLocker/SystemDrivesRecoveryOptions` | Controls recovery and escrow. |
|   > Configure user storage of BitLocker recovery information | **Allow 48-digit recovery password**; recovery key **Do not allow 256-bit recovery key** | (sub-setting) | Recovery password only. |
|   > Allow data recovery agent | **False** | (sub-setting) | No certificate DRA. |
|   > Omit recovery options from the BitLocker setup wizard | **True** | (sub-setting) | Users don't choose recovery options. |
|   > Save BitLocker recovery information to AD DS | **True**: Store recovery passwords and key packages | (sub-setting) | Escrow (Entra ID for cloud-joined devices, AD DS for hybrid). |
|   > Do not enable BitLocker until recovery information is stored to AD DS | **True** | (sub-setting) | No encryption without escrow. Also required for password rotation. |

### Fixed Data Drives

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Choose how BitLocker-protected fixed drives can be recovered | **Enabled** (same options as the OS drive) | `./Device/Vendor/MSFT/BitLocker/FixedDrivesRecoveryOptions` | Escrow and rotation for secondary internal drives. |

> [!WARNING]
> - **Third-party encryption.** *Allow Warning For Other Disk Encryption = Disabled* lets BitLocker run even when other disk encryption software is present, which can cause data loss or boot failures. Confirm no third-party encryption is installed before deploying.
> - **Security baselines.** The **Defender for Endpoint baseline** can enable TPM startup PIN or key, which **blocks silent encryption**. Exclude those settings for these devices.
> - **Removable drives.** *Deny write access to removable drives not protected by BitLocker* is left **Not configured** on purpose: it has high user impact, and with a startup key it conflicts with silent encryption. Add it separately if your data-protection policy needs it.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Intune Plan 1. **Windows Enterprise E3/E5** (or A3/A5, included in Microsoft 365 E3/E5/F3) is needed for the BitLocker CSP settings other than *Require Device Encryption*. |
| Hardware | TPM 1.2 or 2.0, UEFI with **Secure Boot**, and Windows Recovery Environment (WinRE) enabled |
| Join type | Microsoft Entra joined (silent escrow to Entra ID) or hybrid joined |
| Software | No third-party disk encryption |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag. Reading recovery keys needs *Read BitLocker keys* permission. |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Disk encryption > Create Policy**. Set **Platform** to **Windows** and **Profile** to **BitLocker**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - Bitlocker Configuration`
   - **Description**: Silent BitLocker: require encryption, no third-party warning, standard-user encryption, XTS-AES 256, TPM-only startup, recovery password escrow to Entra ID + rotation.
   - Select **Next**.
4. **Configuration settings**: set each setting in the tables above. Summary:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Require Device Encryption | Enabled |
   | 2 | Allow Warning For Other Disk Encryption | Disabled |
   | 3 | Allow Standard User Encryption | Enabled |
   | 4 | Configure Recovery Password Rotation | Refresh on for both Azure AD-joined and hybrid-joined devices |
   | 5 | Choose drive encryption method and cipher strength | Enabled; XTS-AES 256 / XTS-AES 256 / AES-CBC 256 |
   | 6 | Enforce drive encryption type on OS drives | Enabled; Used Space Only |
   | 7 | Require additional authentication at startup | Enabled; without TPM False; TPM startup Allow; PIN, key, and key+PIN **Do not allow** |
   | 8 | Choose how OS drives can be recovered | Enabled; allow 48-digit password; don't allow 256-bit key; DRA False; omit options True; save to AD DS True; don't enable until stored True |
   | 9 | Choose how fixed drives can be recovered | Enabled; same options |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add all corporate Windows **device** groups. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag and template)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates").value |
    Where-Object displayName -like "*BitLocker*" | Select-Object id, displayName, templateFamily, platforms, technologies

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - Bitlocker Configuration'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\BitLocker-Configuration.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\BitLocker-Configuration.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -Body $body -ContentType "application/json"

# 4. Assign to a device group
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = "<windows-device-group-id>" } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assign" -Body $assign -ContentType "application/json"
```

## Assignment & conflict guidance

- **One BitLocker policy per device.** Endpoint protection templates, settings catalog BitLocker settings, and the **Windows** / **Defender for Endpoint security baselines** all overlap. Different values cause **conflicts** and can block silent encryption.
- **Compliance.** The *Require BitLocker* and *Device Storage Encryption* compliance policies **check** encryption. They don't configure it, so there's no conflict. This policy makes devices compliant.
- **Windows 365 Cloud PCs** don't support BitLocker. Exclude them with a filter `(device.model -contains "Cloud PC") or (device.model -contains "Windows 365")`.
- **GPO.** On hybrid devices, remove BitLocker GPOs (*Computer Configuration > Administrative Templates > Windows Components > BitLocker Drive Encryption*).

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Check **Reports > Endpoint security > Encryption report** for encryption status and readiness. Recovery keys are under **Devices >** a device **> Recovery keys**, and in the Entra admin center.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Check status with `manage-bde -status` or `Get-BitLockerVolume`. Expect `VolumeStatus = FullyEncrypted`, `EncryptionMethod = XtsAes256`, and a `KeyProtector` of **Tpm** + **RecoveryPassword**.
3. Check events in Event Viewer under *Applications and Services Logs > Microsoft > Windows > BitLocker-API > Management*. Event **845** means the recovery password was backed up to Entra ID.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | No TPM, legacy BIOS, Windows Home, or a Cloud PC | Upgrade the OS or edition. |
| **Conflict** | A security baseline or another BitLocker policy (for example one enabling a TPM PIN) | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Silent encryption prerequisites not met (TPM, Secure Boot, WinRE) or a third-party encryption product | Fix the value and re-sync. |
| Encryption prompts the user | TPM PIN or startup key allowed or required by another policy | Set all TPM PIN and key options to *Do not allow* and remove the conflicting baseline settings. |
| "Un-allowed DMA capable bus/device(s) detected" | External DMA-capable ports | Confirm with the OEM, and allow-list only internal buses. |
| Already-encrypted devices still use XTS-AES 128 | The cipher only applies at encryption time | Decrypt and re-encrypt if you must change the cipher. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

No restart is needed to start silent encryption. It runs in the background.

## Rollback

- **Unassign or delete** the policy. Drives **stay encrypted** (not reverted); only the policy enforcement is removed.
- To decrypt, run `manage-bde -off C:` on the device. That isn't recommended, and devices then fail the BitLocker compliance policies.

## References

- [Encrypt Windows devices with BitLocker using Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/encrypt-bitlocker-windows)
- [Disk encryption policy for endpoint security](https://learn.microsoft.com/intune/device-configuration/endpoint-security/disk-encryption)
- [BitLocker CSP](https://learn.microsoft.com/windows/client-management/mdm/bitlocker-csp)
- [Configure BitLocker](https://learn.microsoft.com/windows/security/operating-system-security/data-protection/bitlocker/configure)
- [Troubleshoot BitLocker policies from the client side](https://learn.microsoft.com/troubleshoot/mem/intune/device-protection/troubleshoot-bitlocker-policies)
