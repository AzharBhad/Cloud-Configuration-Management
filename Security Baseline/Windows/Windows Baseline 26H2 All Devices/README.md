# Security Baseline for Windows 10 and later - All Devices

Intune **Security Baseline for Windows 10 and later, version 26H2**, with **Microsoft's recommended default settings** (no customizations), rolled out to **all corporate Windows devices** through a pilot ring first.

## Purpose

Windows devices ship with settings that favour compatibility over security. The Windows security baseline applies Microsoft's recommended hardening in one profile:

- **Credential protection**: Credential Guard, LSA protection, virtualization-based security (VBS) and memory integrity (HVCI).
- **Network hardening**: SMB signing, SMB 3.0 minimum, NTLMv2 only, SMBv1 off.
- **Microsoft Defender Antivirus and attack surface reduction (ASR) rules**, network protection, firewall on for all profiles.
- **Account and sign-in controls**: UAC, local account restrictions, 14-character local passwords, idle lock.
- **Legacy features off**: AutoRun, Internet Explorer, Digest authentication, and audit policy for investigations.

**Why a baseline and not individual policies:** the Windows security team maintains these settings and updates the baseline with each Windows release. One profile replaces dozens of settings catalog policies, and Intune reports per-setting status for the whole set. Using the **defaults** follows Microsoft's recommendation exactly and makes version upgrades simple: there are no customizations to carry forward.

**Zero Trust:** this profile hardens the device. Microsoft Entra ID Conditional Access *Require device to be marked as compliant* checks devices through a separate compliance policy, for example [Security Baseline compliance](../../../Compliance/Windows/Windows%2010%20and%2011/Security%20Baseline).

## Policy summary

| Item | Value |
|---|---|
| Profile name | `Security Baseline for Windows 10 and later - All Devices` (as requested) |
| Baseline type | Security Baseline for Windows 10 and later |
| **Baseline version** | **Version 26H2**: the latest on Microsoft Learn *Use security baselines > Available security baselines*, checked 2026-10-23 |
| Platform | Windows 10 and later |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm` |
| Template family | `baseline` (template ID looked up in your tenant, see the Graph steps) |
| File | `Windows-Baseline-26H2-All-Devices.json` |
| Scope tags | Windows Admin (`<windows-admin-scope-tag-id>`, same as the other Windows policies in this repo) |
| Recommended assignment | **Devices**: pilot device group first, then **All devices** with an assignment filter for corporate Windows devices (excluding Cloud PCs). See *Assignment*. |
| Supported OS | Windows 11 Pro, Enterprise, Education. Windows 10 reached end of support on 2025-10-14. Some settings (Credential Guard) apply only to Enterprise and Education. |
| JSON status | **Metadata-only** (`"settings": []`). See the warning below. |

> [!WARNING]
> **The JSON is metadata-only.** A baseline profile created through Graph needs every setting instance of the template, with setting IDs that Microsoft Learn doesn't publish. Importing this JSON creates the profile **shell** only. Create the profile in the admin center (it fills in all Microsoft defaults automatically), then export it and **replace this JSON with the export**.

## Configuration settings

All settings use the **Microsoft defaults for Security Baseline for Windows, version 26H2**. Full list: [Windows MDM security baseline settings reference (version 26H2)](https://learn.microsoft.com/intune/device-security/security-baselines/ref-windows-mdm-settings?pivots=mdm-26h2).

### Customizations

None: Microsoft defaults. Don't change any setting in this profile. If a default conflicts with another policy, change the **other** policy (see *Conflicts*), so this profile stays a pure Microsoft baseline.

### High-impact defaults to review

Test these in the pilot ring before widening the assignment.

| Setting (category) | Baseline default | Who / what it affects |
|---|---|---|
| Credential Guard (Device Guard) | Enabled **with UEFI lock** | Unassigning the baseline won't turn it off; removal needs a manual step per device. Breaks NTLMv1, MS-CHAPv2 / PEAP Wi-Fi and VPN with saved credentials, and unconstrained Kerberos delegation. |
| Configure LSA Protected Process (Local Security Authority) | Enabled **with UEFI lock** | Unsigned LSA plug-ins, smart card or password-filter drivers fail to load. Can't be reverted from Intune alone. |
| Hypervisor Enforced Code Integrity (Virtualization Based Technology) | Enabled **with UEFI lock** | Old or incompatible kernel drivers (VPN clients, docks, antivirus, hardware tools) fail to load. |
| Deny Access From Network / Deny Remote Desktop Services Log On (User Rights) | *Local account* (S-1-5-113) | The LAPS-managed local Administrator (`Windows - Enable Local Administrator Account`) works at the console only, not over the network or RDP. Plan help-desk remote support. |
| Min SMB 2 Dialect (Lanman Workstation / Server) | SMB 3.0.0 | Old NAS devices, scan-to-folder printers and legacy file servers on SMB 2.x stop working. |
| SMB signing always; LAN Manager authentication level | Enabled; *Send NTLMv2 responses only. Refuse LM and NTLM* | Devices that can't sign SMB, and apps that need NTLMv1, fail. |
| Device Enumeration Policy (DMA Guard); Allow Direct Memory Access (Data Protection) | Block all; Block | Thunderbolt/USB4 docks and external GPUs may not work before sign-in, or at all on hardware without Kernel DMA Protection. |
| Deny write access to removable drives not protected by BitLocker (BitLocker > Removable Data Drives) | Enabled | **USB drives become read-only** until the user encrypts them with BitLocker To Go. Your BitLocker policy leaves this Not configured on purpose, so this is a new behavior for users. |
| Interactive Logon Machine Inactivity Limit | 900 seconds | Devices lock after 15 minutes idle. **Conflicts** with the repo's 600-second policy (see *Conflicts*). |
| Min Device Password Length (Device Lock) | 14 characters | Local account passwords must be 14+ characters. The repo's LAPS password length is 14, so LAPS is fine. |
| ASR: Block untrusted and unsigned processes that run from USB; Block process creations from PSExec and WMI | Block; **Audit** | Different modes from the repo's ASR policies (see *Conflicts*). |

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 (included in Microsoft 365 E3/E5 and EMS E3/E5). Microsoft Entra ID P1 for dynamic groups and Conditional Access. |
| Windows edition | Windows 11 Pro, Enterprise or Education. Credential Guard is enforced on Enterprise and Education only. Not Home. |
| Hardware | TPM 2.0, UEFI with Secure Boot and virtualization support for VBS, Credential Guard and HVCI |
| Enrollment | Intune-enrolled devices, Microsoft Entra joined or Microsoft Entra hybrid joined |
| Groups and filters | A Microsoft Entra ID **pilot device group** (for example `SG-Intune-Baseline-Pilot-Devices`) and an Intune **assignment filter** for corporate Windows devices (see *Assignment*) |
| Role | Endpoint Security Manager or Intune Administrator |
| Before production | Resolve the conflicts listed below |

## Step-by-step: create the security baseline profile

1. Sign in to the **Microsoft Intune admin center**.
2. Go to **Endpoint security > Security baselines > Security Baseline for Windows 10 and later**.
3. Select **Versions** and check the latest is **26H2**. Then select **Create policy**.
4. **Basics**:
   - **Name**: `Security Baseline for Windows 10 and later - All Devices`
   - **Description**: `Security Baseline for Windows 10 and later, version 26H2, Microsoft default settings for all corporate Windows devices. No customizations.`
   - Select **Next**.
5. **Configuration settings**: review the categories, but **don't change anything**. Every setting stays at its Microsoft default. Select **Next**.
6. **Scope tags**: **Windows Admin**. Select **Next**.
7. **Assignments** (pilot first):
   - **Included groups** > **Add groups** > the pilot device group (`SG-Intune-Baseline-Pilot-Devices`).
   - Select **Next**.
8. **Review + create** > **Create**. Intune pushes the profile to the pilot devices straight away.
9. After the pilot (see *Assignment*), open the profile > **Properties** > **Assignments** > **Edit**:
   - Under **Included groups**, select **Add all devices**.
   - Set **Filter mode** to **Include filtered devices in assignment** and select the filter `Windows - Corporate Devices`.
   - Remove the pilot group (it's now covered by All devices) and select **Review + save**.

**Create the assignment filter** (once, before step 9): **Tenant administration > Filters > Create > Managed devices**, platform **Windows 10 and later**, name `Windows - Corporate Devices`, rule:

```text
(device.deviceOwnership -eq "Corporate") and (device.model -notStartsWith "Cloud PC")
```

This keeps personal (BYOD) devices out, and leaves Windows 365 Cloud PCs out because they have their own **Windows 365 Security Baseline**. Use **Preview devices** on the filter to check which devices match.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
# Works in Windows PowerShell 5.1 and PowerShell 7 (Microsoft.Graph.Authentication module).
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

# 1. Find the template ID of Security Baseline for Windows 10 and later, version 26H2
$t = Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates?`$filter=templateFamily eq 'baseline'"
$t.value | Select-Object id, displayName, displayVersion, lifecycleState | Format-Table -AutoSize

# 2. Replace <baseline-template-id-from-tenant> and <windows-admin-scope-tag-id> in the JSON, then create the profile
$file   = ".\Windows-Baseline-26H2-All-Devices.json"
$policy = Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" `
  -Body (Get-Content $file -Raw) -ContentType "application/json"

# 3a. Pilot: assign to the pilot device group
$pilot = @{ assignments = @(
  @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = "<pilot-device-group-object-id>" } }
) } | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assign" `
  -Body $pilot -ContentType "application/json"

# 3b. Production: All devices + include filter (replaces the pilot assignment)
$all = @{ assignments = @(
  @{ target = @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget";
                 deviceAndAppManagementAssignmentFilterId = "<corporate-windows-filter-id>";
                 deviceAndAppManagementAssignmentFilterType = "include" } }
) } | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assign" `
  -Body $all -ContentType "application/json"

# 4. Export the finished profile and save it over the JSON
$export = Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)?`$expand=settings"
$export | ConvertTo-Json -Depth 100 | Set-Content $file -Encoding UTF8
# Then remove read-only properties: id, createdDateTime, lastModifiedDateTime, settingCount,
# isAssigned, creationSource, @odata.context and the templateReference display fields.
```

> [!WARNING]
> With the metadata-only JSON, step 2 creates a profile shell without settings, and Graph may reject a baseline body with no setting instances. Create the profile in the admin center instead (it fills in all defaults), then use step 4 to store the full body in this repo. The `/assign` call **replaces** all assignments, so 3b removes the pilot assignment.

## Assignment & conflict guidance

### Assignment (Microsoft recommendation)

Microsoft recommends testing a baseline on a pilot group before wide deployment, and assigning baselines to user **or** device groups based on the settings' scope. This baseline is almost all **device** scope, so:

| Ring | Target | When to move on |
|---|---|---|
| 1. Pilot | `SG-Intune-Baseline-Pilot-Devices`: 5-10% of devices, including IT and each hardware model and line-of-business app team | 1-2 weeks with no blocking issues in *Per setting status* and help-desk tickets |
| 2. Production | **All devices** + include filter `Windows - Corporate Devices` | After the conflicts below are resolved |

- **All devices** is Intune's built-in virtual group. It only reaches Windows devices here because the profile is a Windows profile; the filter keeps out personal devices and Cloud PCs.
- Optional middle ring: a dynamic Microsoft Entra device group, for example `(device.deviceOSType -eq "Windows") and (device.deviceOwnership -eq "Company")`, for one department before *All devices*.
- **Exclusions**: kiosks or specialised devices that can't run Credential Guard or need SMB 2 can go in an excluded device group (don't mix user and device groups across include and exclude).
- Don't assign this profile and another Windows baseline profile to the same devices.

### Conflicts found in this repo

Rule: **one setting, one owner**. Because this profile keeps Microsoft defaults, fix conflicts in the **other** policy: set it to the baseline value, or set it to *Not configured* there.

| Repo policy | Setting | Repo value | Baseline 26H2 default | Action |
|---|---|---|---|---|
| [Inactivity Timeout](../../../Configuration/Windows/Windows%2010%20and%2011/Inactivity%20Timeout) (`Windows Inactivity Timeout 10 Minutes`) | Interactive Logon Machine Inactivity Limit | 600 | 900 | **Conflict.** If 10 minutes is your company standard, keep that policy and this setting reports *Conflict*; or retire that policy and accept 15 minutes. CIS and the Azure Windows baseline recommend 900 or less, so both values meet that. |
| [Block Untrusted EXE from USB](../../../Configuration/Windows/Windows%2010%20and%2011/Block%20Untrusted%20EXE%20from%20USB) (`Windows - ASR - USB_untrusted_EXE`) | Block untrusted and unsigned processes that run from USB | Warn | Block | **Conflict.** Set the ASR policy to Block (or Not configured), or accept the conflict until the Warn period ends. |
| [ASR PSExec WMI Process Creation](../../../Configuration/Windows/Windows%2010%20and%2011/ASR%20PSExec%20WMI%20Process%20Creation) | Block process creations originating from PSExec and WMI commands | Block | Audit | **Conflict.** See the note below the table. |
| [Defender Antivirus Configuration](../../../Configuration/Windows/Windows%2010%20and%2011/Defender%20Antivirus%20Configuration) (`Windows - Defender Antivirus Configuration`) | Submit Samples Consent | Send safe samples automatically | Send all samples automatically | **Conflict.** Choose one; the repo chose *safe samples* to avoid uploading documents with business data. |
| [BitLocker Configuration](../../../Configuration/Windows/Windows%2010%20and%2011/BitLocker%20Configuration) | Deny write access to removable drives not protected by BitLocker | Not configured (on purpose) | Enabled | No conflict state, but **new behavior**: USB drives become read-only until encrypted. Communicate it, or this needs a customization in the baseline (not requested). |
| Other ASR policies (Obfuscated Scripts, Office Win32 API Calls, Office Child Processes, JS VBScript, Adobe Reader, Office Executable Content, Office Code Injection) | Matching ASR rules | Block | Block | Same value, two owners. No conflict. |
| [Firewall Configuration Global](../../../Configuration/Windows/Windows%2010%20and%2011/Firewall%20Configuration%20Global), [LAPS Profile](../../../Configuration/Windows/Windows%2010%20and%2011/LAPS%20Profile), [Edge Configuration](../../../Configuration/Windows/Windows%2010%20and%2011/Edge%20Configuration) | Firewall profiles, LAPS backup directory, SmartScreen | Same values for the settings checked | Same | Overlap only. Watch *Per setting status* in the pilot. |
| [Enable Credential Guard](../../../Platform%20Scripts/Enable%20Credential%20Guard) platform script | Credential Guard / VBS | Turned on by script | Enabled with UEFI lock | Overlap. The baseline makes the script unnecessary on these devices. |

> [!NOTE]
> The PSExec row: the cleanest result is one owner. Either set the rule to **Audit** in the ASR policy (follow the baseline), or keep **Block** there and accept a known *Conflict* for that one setting. Decide before ring 2.

Other sources of conflict:

- **Microsoft Defender for Endpoint baseline**: sets many of the same Defender, ASR, firewall and BitLocker settings with different defaults. Don't assign both baselines to the same devices without comparing them.
- **Group Policy** on hybrid joined devices: remove overlapping GPO settings, or configure **ControlPolicyConflict / MDMWinsOverGP** so MDM wins.

### Version upgrades

When Microsoft releases a newer version, use **Update version** on this profile. The update copies the profile **without assignments**: assign the new version to the pilot group, then move *All devices* from this profile to the new one, so no device gets both. Keep this folder until the old profile is retired and add a new folder for the new version.

## Validation

**Admin center**

- **Endpoint security > Security baselines > Security Baseline for Windows 10 and later > Profiles > Security Baseline for Windows 10 and later - All Devices**: **Device status**, **Per setting status**, **Device assignment status**.
- **Devices > All devices > *device* > Device configuration > this profile**: per-setting results, with **Source profiles** for any conflict.
- Data can take up to 24 hours after the first assignment and up to 6 hours after changes.

**On a device**

- **Settings > Accounts > Access work or school > *work account* > Info > Sync**; **Export management log files** for support.
- Event Viewer: *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*.
- `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.
- Credential Guard / VBS / HVCI: `msinfo32` > *Virtualization-based security* rows. Defender: `Get-MpComputerStatus`, `Get-MpPreference`.
- Idle lock: `reg query HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v InactivityTimeoutSecs`.

**Microsoft Defender portal** (with Defender Vulnerability Management): **Security baselines assessment** and **Microsoft Secure Score** show the security effect across devices.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | Device hasn't checked in | Sync from the device or the admin center; check it's online and enrolled. |
| **Not applicable** | Wrong OS, edition (Home) or version | Use Windows 11 Pro/Enterprise/Education; check the CSP's OS support. |
| **Conflict** on a setting | Same setting owned by another policy with a different value (inactivity limit, USB and PSExec ASR rules, sample submission) | Device > Device configuration > setting > **Source profiles**; fix the other policy (see *Conflicts*). |
| **Error** on a setting | CSP rejected the value (for example Credential Guard on Pro, or no VBS support) | Check the CSP applicability; exclude unsupported devices. |
| Device not in the assignment | Filter rule doesn't match (ownership not *Corporate*, or model starts with *Cloud PC*) | Check the device's **Ownership** and **Model**; use **Preview devices** on the filter. |
| USB drives read-only | Baseline default *Deny write access to removable drives not protected by BitLocker* | Expected; encrypt the drive with BitLocker To Go, or plan a customization. |
| Docks or Thunderbolt devices don't work before sign-in | DMA protection defaults | Expected; test docks in the pilot. |
| VPN, Wi-Fi or file shares stop working | Credential Guard (MS-CHAPv2/PEAP), SMB 3.0 minimum, NTLMv2 only | Move to certificate-based Wi-Fi/VPN; upgrade SMB devices. |
| Changes need a restart | Credential Guard, LSA protection, HVCI | Restart the device. |
| Can't change settings in the profile | Profile uses an older baseline version (read-only) | **Update version** to the latest. |

## Rollback

- **Unassign or delete** the profile. Microsoft Learn: when a baseline no longer applies, settings **might not revert**; each CSP handles removal differently.
- To roll back a specific setting, deploy the opposite value with a settings catalog policy, confirm on devices, then remove that policy.
- **UEFI-locked** settings (Credential Guard, LSA protection, HVCI) stay on after unassigning and need a manual per-device procedure to turn off.
- During ring 2, roll back by removing *All devices* from the assignment and adding the pilot group back.

## References

- [Use security baselines to help secure Windows devices you manage with Microsoft Intune](https://learn.microsoft.com/intune/device-security/security-baselines/overview)
- [Manage security baseline profiles in Microsoft Intune](https://learn.microsoft.com/intune/device-security/security-baselines/configure-baselines)
- [Monitor security baselines and profiles in Microsoft Intune](https://learn.microsoft.com/intune/device-security/security-baselines/monitor-baselines)
- [Windows MDM security baseline settings reference (version 26H2)](https://learn.microsoft.com/intune/device-security/security-baselines/ref-windows-mdm-settings?pivots=mdm-26h2)
- [Attack surface reduction rules reference](https://learn.microsoft.com/defender-endpoint/attack-surface-reduction-rules-reference)
- [Policy CSP - LocalPoliciesSecurityOptions](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-localpoliciessecurityoptions)
- [deviceManagementConfigurationPolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfigv2-devicemanagementconfigurationpolicy?view=graph-rest-beta)
- [deviceManagementConfigurationPolicyTemplate resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfigv2-devicemanagementconfigurationpolicytemplate?view=graph-rest-beta)
- [Use filters when assigning apps, policies and profiles in Intune](https://learn.microsoft.com/intune/intune-service/fundamentals/filters)
- [Dynamic membership rules for groups in Microsoft Entra ID](https://learn.microsoft.com/entra/identity/users/groups-dynamic-membership)
- [Configure Credential Guard](https://learn.microsoft.com/windows/security/identity-protection/credential-guard/configure)
