# WIN-COMP – Windows 10 and 11 Security Baseline

Baseline Intune compliance policy for **Windows 10 and Windows 11** devices. It requires BitLocker, Secure Boot and code integrity, storage encryption, the firewall, a TPM, antivirus/antispyware, and Microsoft Defender Antimalware with real-time protection and current security intelligence. Devices must also run at least Windows 10 22H2.

## Purpose

- **Risk addressed:**
  - Lost or stolen devices exposing data (no encryption)
  - Boot-level tampering (no Secure Boot or code integrity)
  - Malware on unprotected endpoints (antivirus or real-time protection off, outdated signatures)
  - Unpatched, unsupported OS releases
- **Zero Trust role:** compliance is the "device is healthy" signal. Paired with the Conditional Access grant **Require device to be marked as compliant**, only devices that pass this policy can reach Microsoft 365 and other Entra-protected apps.
- **Scope:** one policy for all corporate Windows 10/11 devices. Stricter controls (Defender for Endpoint risk score, patch-level build ranges) can be layered on later. See the TIPs below.

## Policy summary

| Item | Value |
|---|---|
| Display name | `WIN-COMP-Windows 10 and 11 Security Baseline` |
| Platform | Windows 10 and later |
| Profile type | – (single profile for this platform) |
| Graph `@odata.type` | `#microsoft.graph.windows10CompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Windows-10-and-11-Security-Baseline.json` |
| Assignment target | **User groups** of licensed Windows users, or device groups of corporate Windows devices. Don't mix both for the same device. |
| Noncompliance actions | **Mark device noncompliant** after **1 day** (24-hour grace period) |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint. In Graph v1.0, `windows10CompliancePolicy` doesn't expose the firewall, TPM, antivirus, antispyware or Defender properties (`activeFirewallRequired`, `tpmRequired`, `antivirusRequired`, `antiSpywareRequired`, `defenderEnabled`, `signatureOutOfDate`, `rtpEnabled`). They exist only in beta. Microsoft supports Intune beta APIs, but they can change.

## Configuration description

### Device Health – Windows Health Attestation Service evaluation rules

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require BitLocker | Require | `bitLockerEnabled` | BitLocker on the OS volume, measured by Device Health Attestation **at boot**. Protects data on lost or stolen devices. |
| Require Secure Boot to be enabled on the device | Require | `secureBootEnabled` | The device boots only with trusted, signed boot components. Blocks bootkits. |
| Require code integrity | Require | `codeIntegrityEnabled` | Detects unsigned drivers or system files being loaded into the kernel |

> [!WARNING]
> Device Health Attestation settings are evaluated **only at boot**. A device that just finished BitLocker encryption stays noncompliant until it **restarts**. Tell users to reboot after encryption completes.

### Device Properties – Operating System Version

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum OS version | `10.0.19045.0` | `osMinimumVersion` | Blocks anything older than **Windows 10 22H2**, the last Windows 10 release. All Windows 11 releases (`10.0.22xxx`/`10.0.26xxx`) pass. |

> [!TIP]
> To enforce **patch level** rather than just feature release, use **Valid operating system builds** (`validOperatingSystemBuildRanges`). Add one row per supported release with a minimum build from the current month's cumulative update, using [Windows release information](https://learn.microsoft.com/windows/release-health/release-information). Update the rows monthly. This is left out of the baseline because a stale range causes mass noncompliance.

> [!NOTE]
> Windows 10 reached end of support on **October 14, 2025**. Windows 10 22H2 is allowed here only for devices enrolled in Extended Security Updates (ESU) during the migration to Windows 11. Raise the minimum to a Windows 11 build (for example `10.0.22631.0` or `10.0.26100.0`) once migration is complete.

### Configuration Manager Compliance

Not configured. It applies only to co-managed devices. Set **Require device compliance from Configuration Manager** if Configuration Manager baselines should count.

### System Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| *Password* | Not configured | – | Sign-in is handled by Windows Hello for Business / identity policies, not compliance. |
| Encryption of data storage on a device | Require | `storageRequireEncryption` | Generic OS-drive encryption check (BitLocker), reported without a reboot. Complements *Require BitLocker*. |
| Firewall | Require | `activeFirewallRequired` | Windows Firewall is on. A GPO that disables the firewall makes this noncompliant. |
| Trusted Platform Module (TPM) | Require | `tpmRequired` | The device reports a TPM (spec version > 0) |
| Antivirus | Require | `antivirusRequired` | An antivirus registered with Windows Security Center is on and up to date |
| Antispyware | Require | `antiSpywareRequired` | An antispyware registered with Windows Security Center is on and up to date |

### System Security – Defender

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Microsoft Defender Antimalware | Require | `defenderEnabled` | The Defender antimalware service is running |
| Microsoft Defender Antimalware minimum version | Not configured | – | Platform updates are managed by Defender update channels |
| Microsoft Defender Antimalware security intelligence up-to-date | Require | `signatureOutOfDate` | Security intelligence (signatures) is current |
| Real-time protection | Require | `rtpEnabled` | Real-time scanning is on |

> [!WARNING]
> If a third-party antivirus is the primary AV, Defender runs in passive mode. In that case, **don't** require *Microsoft Defender Antimalware* or *Real-time protection*. Keep only *Antivirus* and *Antispyware*, which accept any Windows Security Center–registered product.

### Microsoft Defender for Endpoint

Not configured in this baseline. Once the **Microsoft Defender for Endpoint connector** is enabled (Intune admin center > Endpoint security > Microsoft Defender for Endpoint), add:

| Setting (admin center name) | Value | Graph property |
|---|---|---|
| Require the device to be at or under the machine risk score | **Medium** | `deviceThreatProtectionEnabled: true`, `deviceThreatProtectionRequiredSecurityLevel: "medium"` |

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** per user (included in Microsoft 365 E3/E5, EMS). **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | Windows 10 22H2 / Windows 11 devices **enrolled in Intune** (Entra joined, hybrid joined via auto-enrollment, or co-managed) |
| Hardware | TPM 2.0 and UEFI Secure Boot (Windows 11 hardware requirement). Devices without TPM 2.0 can't pass the Secure Boot check. |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. **Conditional Access Administrator** for the CA policy. |
| Encryption | A BitLocker policy (Endpoint security > Disk encryption) that actually turns encryption on. Compliance only *checks* it. |
| Defender | Defender Antivirus policy (Endpoint security > Antivirus) for real-time protection and updates |
| Graph import | `Microsoft.Graph.Authentication` PowerShell module, delegated scope `DeviceManagementConfiguration.ReadWrite.All` |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Windows 10 and later**, then select **Create**.
4. **Basics**:
   - **Name**: `WIN-COMP-Windows 10 and 11 Security Baseline`
   - **Description**: paste the description from the JSON
   - Select **Next**.
5. **Compliance settings**: expand each category and set:
   1. **Device Health > Windows Health Attestation Service evaluation rules**:
      - Require BitLocker = **Require**
      - Require Secure Boot to be enabled on the device = **Require**
      - Require code integrity = **Require**
   2. **Device Properties > Operating System Version**: Minimum OS version = `10.0.19045.0`
   3. **System Security > Encryption**: Encryption of data storage on a device = **Require**
   4. **System Security > Device Security**:
      - Firewall = **Require**
      - Trusted Platform Module (TPM) = **Require**
      - Antivirus = **Require**
      - Antispyware = **Require**
   5. **System Security > Defender**:
      - Microsoft Defender Antimalware = **Require**
      - Microsoft Defender Antimalware security intelligence up-to-date = **Require**
      - Real-time protection = **Require**
   6. Leave **Password**, **Configuration Manager Compliance**, **Microsoft Defender for Endpoint** and **Windows Subsystem for Linux** as **Not configured**. Select **Next**.
6. **Actions for noncompliance**: the default action **Mark device noncompliant** is listed. Set its **Schedule (days after noncompliance)** to **1**.
   - *Optional:* **Add** > **Send email to end user**, schedule **0**, with a message template from **Devices > Manage devices > Compliance > Notifications**.
   - Select **Next**.
7. **Scope tags**: add the tags used by your Intune RBAC model (for example `Corp-Windows`), or keep **Default**. Select **Next**.
8. **Assignments**: **Add groups**, then select the pilot group first (for example `GRP-Pilot-Users`) and expand later. Select **Next**.
9. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
# 1. Connect with rights to create compliance policies
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

# 2. Create the policy from the JSON (beta endpoint - see the NOTE in "Policy summary")
$body   = Get-Content ".\Windows-10-and-11-Security-Baseline.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body $body -ContentType "application/json"
$policy.id                                            # keep the new policy ID

# 3. Assign it to a group (replace with your group's object ID)
$groupId = "<entra-group-object-id>"
$assign  = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $groupId } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"

# 4. Confirm
Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=assignments"
```

> [!TIP]
> The **Microsoft Graph Beta** SDK equivalent is `New-MgBetaDeviceManagementDeviceCompliancePolicy -BodyParameter ($body | ConvertFrom-Json -AsHashtable)` (PowerShell 7). `Invoke-MgGraphRequest` needs only the authentication module.

## Tenant-wide compliance settings to review

Go to **Devices > Manage devices > Compliance > Compliance settings**:

| Setting | Recommended | Why |
|---|---|---|
| Mark devices with no compliance policy assigned as | **Not compliant** | Stops unassessed devices from passing Conditional Access. Switch this only after every device is targeted by a policy. |
| Compliance status validity period (days) | **30** (default) | A device that hasn't reported within this period becomes noncompliant |

## Conditional Access integration

1. Go to **Microsoft Entra admin center > Entra ID > Conditional Access > Policies > New policy**.
2. Set **Users** to the same group as the assignment, and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
4. Under **Conditions > Device platforms**, include **Windows**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first. Review the sign-in logs for a week, then switch it **On**.

> [!WARNING]
> Turning CA on before devices report compliant blocks users. Wait until the compliance report shows the pilot devices as **Compliant**.

## Validation

| Where | What to check |
|---|---|
| **Devices > Monitor > Device compliance** / **Setting compliance** | Overall status and the per-setting pass/fail counts for this policy |
| **Devices > Manage devices > Compliance > Policies > (policy) > Device status** | Each assigned device: *Compliant*, *Not compliant*, *In grace period*, *Not evaluated* |
| **Devices > Windows > (device) > Device compliance** | Per-setting result for one device (e.g. *Require BitLocker: Not compliant*) |
| On the device | **Company Portal > Devices > (this PC) > Check status**, or **Settings > Accounts > Access work or school > (account) > Info > Sync** |
| On the device (logs) | `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log`. Run `dsregcmd /status` to confirm the device is joined and has a PRT. |
| Entra sign-in logs | **Device info** tab shows *Compliant: Yes* and the CA policy result |

**Timing:**
- Devices evaluate at check-in, roughly every 8 hours, and sooner when a monitored setting changes (firewall, antivirus, BitLocker, Defender, OS build, real-time protection, Secure Boot).
- To force an evaluation, select **Sync** on the device or in the admin center.
- After enabling BitLocker, **restart** the device.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or the user/device isn't in the assigned group | Sync the device. Check group membership and assignment type (user vs. device). |
| **In grace period** | Device failed a setting less than 24 hours ago | Expected. Fix the failing setting before the grace period ends. |
| *Require BitLocker* noncompliant although encrypted | Device Health Attestation measures at boot only | Restart the device, then sync |
| *Require Secure Boot* noncompliant | Secure Boot off in UEFI, legacy BIOS mode, or TPM 2.0 missing | Enable Secure Boot in firmware, or convert MBR to GPT (`mbr2gpt`) |
| *Minimum OS version* noncompliant | Device on Windows 10 21H2 or older (stale OS) | Upgrade with a Windows feature update policy |
| *Firewall* noncompliant despite Intune firewall policy | A GPO turns the firewall off or allows all inbound | Remove the conflicting GPO setting |
| *Firewall* shows **Error** after reboot / sleep | Device synced before the firewall reported status | Sync again |
| *Antivirus* / *Real-time protection* noncompliant | Third-party AV disabled Defender (passive mode), or AV out of date | Update AV. For third-party AV, remove the Defender-specific requirements (see WARNING above). |
| Device shows noncompliant and user can't fix it | User not licensed for Intune, or device enrolled under another user | Assign an Intune license. Check the device's primary user. |
| All devices noncompliant after creating the policy | Device Health settings pending reboot, or *Mark devices with no compliance policy* misread | Restart a pilot device, check the per-setting report, and roll out in waves |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only** first, so users are not blocked while you change compliance.
2. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups. Devices drop this policy at the next check-in.
3. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: if no other policy targets the device, its state is governed by *Mark devices with no compliance policy assigned as*. If that is **Not compliant**, CA-protected access is still blocked, so keep CA in report-only until a replacement policy is assigned.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Windows in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-windows-settings)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [windows10CompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windows10compliancepolicy?view=graph-rest-beta)
- [Monitor results of your compliance policies](https://learn.microsoft.com/intune/device-security/compliance/monitor-policy)
- [Require device compliance with Conditional Access](https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-device-compliance)
- [Windows release information](https://learn.microsoft.com/windows/release-health/release-information)
