# WIN-COMP-Device Storage Encryption

Intune compliance policy for **Windows 10 and Windows 11** devices. It requires **encryption of data storage**, **Microsoft Defender Antimalware** and **real-time protection**. Devices are marked noncompliant after **0.25 days (6 hours)**.

## Purpose

- **Risk addressed:**
  - Data on an unencrypted drive can be read if the device is lost or stolen.
  - A device with Defender or real-time scanning turned off is exposed to malware.
- **Why this check, not Require BitLocker:**
  - *Encryption of data storage on a device* checks encryption through the DeviceStatus CSP **without needing a restart**. Device Health Attestation (*Require BitLocker*) only reports after a reboot.
  - So this policy reacts within hours, not after the next boot.
- **Why 6 hours:** a short grace period covers transient states, such as encryption in progress or Defender restarting after an update. It still closes access the same working day if protection stays off.
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a device without encryption or active antimalware loses access to Microsoft 365 and other Entra-protected apps.

## Policy summary

| Item | Value |
|---|---|
| Display name | `WIN-COMP-Device Storage Encryption` |
| Platform | Windows 10 and later |
| Profile type | Windows 10/11 compliance policy |
| Graph `@odata.type` | `#microsoft.graph.windows10CompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Device-Storage-Encryption.json` |
| Assignment target | **All devices**, or a device group of corporate Windows devices. Don't mix user and device assignment for the same devices. |
| Noncompliance actions | **Mark device noncompliant** after **0.25 days** (6 hours) |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint. `storageRequireEncryption` exists in v1.0, but `defenderEnabled` and `rtpEnabled` (Microsoft Defender Antimalware and Real-time protection) exist only in the beta schema of `windows10CompliancePolicy`. Microsoft supports Intune beta APIs, but they can change.

## Configuration description

Every setting not listed is **Not configured**.

### System Security – Encryption

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Encryption of data storage on a device | Require | `storageRequireEncryption` | Checks that the OS drive is encrypted, through DeviceStatus CSP `DeviceStatus/Compliance/EncryptionCompliance`. Intune currently checks **BitLocker** only. Reported without a reboot. |

### System Security – Defender

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Microsoft Defender Antimalware | Require | `defenderEnabled` | The Microsoft Defender anti-malware service is turned on and can't be turned off by users |
| Real-time protection | Require | `rtpEnabled` | Real-time scanning for malware, spyware and unwanted software is on (Policy CSP `Defender/AllowRealtimeMonitoring`) |

> [!WARNING]
> If a third-party antivirus is the primary AV, Defender runs in passive mode. Those devices fail **Microsoft Defender Antimalware** and **Real-time protection** within 6 hours. Exclude them, or give them a separate policy that uses *Antivirus* / *Antispyware* instead.

### Actions for noncompliance

| Action | Schedule | Graph |
|---|---|---|
| Mark device noncompliant | **0.25 days** (6 hours) | `actionType: "block"`, `gracePeriodHours: 6` |

> [!NOTE]
> The admin center accepts schedules in **0.25-day steps** (0.25 = 6 hours, 0.5 = 12 hours). Other fractions, such as 8 hours, can only be set through Microsoft Graph (`gracePeriodHours`).

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** (included in Microsoft 365 E3/E5, EMS). **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | Windows 10 / Windows 11 devices **enrolled in Intune** (Autopilot, Entra joined, hybrid joined via auto-enrollment, or co-managed) |
| Encryption | A BitLocker policy that **turns encryption on**: **Endpoint security > Disk encryption > Create policy > Windows > BitLocker**, with silent encryption and recovery keys escrowed to Entra ID. This compliance policy only **checks** encryption. |
| Defender | A Defender Antivirus policy: **Endpoint security > Antivirus > Create policy > Windows > Microsoft Defender Antivirus**, with *Allow Realtime Monitoring* = Allowed and *Disable Local Admin Merge* to stop users turning it off |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` PowerShell module, delegated scope `DeviceManagementConfiguration.ReadWrite.All` |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Windows 10 and later**, then select **Create**.
4. **Basics**:
   - **Name**: `WIN-COMP-Device Storage Encryption`
   - **Description**: paste the description from the JSON
   - Select **Next**.
5. **Compliance settings**:
   1. **System Security > Encryption**: Encryption of data storage on a device = **Require**.
   2. **System Security > Defender**:
      - Microsoft Defender Antimalware = **Require**
      - Real-time protection = **Require**
   3. Leave everything else **Not configured**, then select **Next**.
6. **Actions for noncompliance**: on **Mark device noncompliant**, set **Schedule (days after noncompliance)** = **0.25**. Select **Next**.
7. **Scope tags**: add your RBAC tag (for example *Windows Admin*) or keep **Default**, then select **Next**.
8. **Assignments**: under **Included groups**, select **Add all devices** (or add a pilot device group first). Select **Next**.
9. **Review + create**: confirm the summary matches the tables above, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
# 1. Connect with rights to create compliance policies
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

# 2. Create the policy from the JSON (beta endpoint - see the NOTE in "Policy summary")
$body   = Get-Content ".\Device-Storage-Encryption.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body $body -ContentType "application/json"
$policy.id                                            # keep the new policy ID

# 3. Assign it to a device group (replace with your group's object ID)
$groupId = "<entra-group-object-id>"
$assign  = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $groupId } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"

# 4. Confirm settings, schedule and assignment
Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=assignments,scheduledActionsForRule(`$expand=scheduledActionConfigurations)"
```

## Tenant-wide compliance settings to review

Go to **Devices > Manage devices > Compliance > Compliance settings**:

| Setting | Recommended | Why |
|---|---|---|
| Mark devices with no compliance policy assigned as | **Not compliant** | Stops unassessed devices from passing Conditional Access |
| Compliance status validity period (days) | **30** (default) | A device that hasn't reported within this period becomes noncompliant |

## Conditional Access integration

1. Go to **Microsoft Entra admin center > Entra ID > Conditional Access > Policies > New policy**.
2. Set **Users** to all users (or a pilot group), and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
4. Under **Conditions > Device platforms**, include **Windows**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first, then switch it **On** once devices report compliant.

During the 6-hour grace period a device shows **In grace period**, and CA still treats it as compliant.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status counts: *Compliant*, *In grace period*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | Pass/fail per setting: *Encryption of data storage*, *Defender Antimalware*, *Real-time protection* |
| **Devices > Windows > (device) > Device compliance > (policy)** | Per-setting result for one device |
| **Devices > Monitor > Encryption report** | Encryption status and readiness per device |
| On the device | `manage-bde -status C:` (*Protection On*). `Get-MpComputerStatus \| Select AMServiceEnabled, AntivirusEnabled, RealTimeProtectionEnabled` (all *True*). **Company Portal > Devices > (this PC) > Check status**. |
| On the device (logs) | `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log`. Run `dsregcmd /status` to confirm the device is joined. |

**Timing:**
- Devices evaluate at check-in.
- Firewall, antivirus, BitLocker, Defender status and real-time protection are also monitored in real time. A change triggers a check-in, so compliance updates faster.
- To force an evaluation, select **Sync** on the device or in the admin center.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment | Sync the device from Company Portal or the admin center |
| **In grace period** | A setting failed less than 6 hours ago | Fix the setting (finish encryption, turn on Defender / RTP) before the 6 hours end |
| *Encryption of data storage* noncompliant | BitLocker not enabled, still encrypting, or suspended | Assign a BitLocker policy. Wait for encryption. `Resume-BitLocker -MountPoint C:` if suspended. |
| Encrypted but still noncompliant | Status not yet reported, or the device uses non-BitLocker encryption | Sync. Intune checks **BitLocker only**, so third-party disk encryption isn't recognised. |
| *Microsoft Defender Antimalware* / *Real-time protection* noncompliant | Third-party AV made Defender passive, Defender disabled by GPO, or turned off by a local admin | Remove the conflicting GPO. Enforce with an Antivirus policy and tamper protection. Use a separate policy for third-party AV devices. |
| Expected a Device Health Attestation restart issue | Not applicable here | This policy doesn't use DHA settings, so no restart is required. Use [Require BitLocker](../Require%20BitLocker/README.md) for TPM-level checks. |
| Old Windows build noncompliant or not reporting | Stale, unsupported OS version without the current Defender platform | Update Windows and the Defender platform |
| Noncompliant and user can't fix it | User not licensed for Intune, or device enrolled under another user | Assign an Intune license. Check the device's primary user. |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Lengthen the grace period:** raise **Mark device noncompliant** from 0.25 to 1 day (or more) if devices need more time, without removing the policy.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: devices are no longer checked for encryption or Defender by this policy. Their compliance then depends on the other assigned policies, or on *Mark devices with no compliance policy assigned as* if none remain. Encryption and Defender settings on the device are **not** changed.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Windows in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-windows-settings)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [windows10CompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windows10compliancepolicy?view=graph-rest-beta)
- [Monitor results of your compliance policies](https://learn.microsoft.com/intune/device-security/compliance/monitor-policy)
- [DeviceStatus CSP](https://learn.microsoft.com/windows/client-management/mdm/devicestatus-csp)
