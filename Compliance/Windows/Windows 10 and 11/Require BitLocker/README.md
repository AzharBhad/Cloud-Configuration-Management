# Windows-Compliance-AllDevices-Bitlocker-5days

Intune compliance policy for **all Windows 10 and Windows 11 devices**. It requires **BitLocker** (verified by Device Health Attestation) and marks a device noncompliant only after a **5-day** grace period, so newly provisioned devices have time to finish encryption, restart and pass the DHA check.

## Purpose

- **Risk addressed:** data on a lost or stolen Windows device can be read if the OS drive isn't encrypted. BitLocker protects data at rest, with keys sealed by the TPM.
- **Why a 5-day delay:** *Require BitLocker* is measured by **Device Health Attestation (DHA) at boot**. A new device (Autopilot / fresh enrollment) encrypts *after* provisioning and only reports BitLocker as on after its **next restart**. The 5-day grace period ("evaluation delay for newly provisioned devices passing DHA check") prevents Conditional Access from blocking users on day one.
- **Zero Trust role:** with the CA grant **Require device to be marked as compliant**, an unencrypted device loses access to Microsoft 365 and other Entra-protected apps once the 5 days are up.
- **Design:** a dedicated, single-setting policy. It runs alongside other Windows compliance policies (e.g. [Security Baseline](../Security%20Baseline/README.md), which is immediate) without delaying their checks. A device is compliant only when **every** assigned policy is compliant.

## Policy summary

| Item | Value |
|---|---|
| Display name | `Windows-Compliance-AllDevices-Bitlocker-5days` |
| Description | `Evaluation delay for newly provisioned devices passing DHA check` |
| Platform | Windows 10 and later |
| Profile type | Windows 10/11 compliance policy |
| Graph `@odata.type` | `#microsoft.graph.windows10CompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies`. The body is also valid on v1.0. Beta is used so the scope tag can be set in the same call. |
| File | `Require-BitLocker.json` |
| Scope tags | **Windows Admin** |
| Assignment target | **All Devices** (Included groups). No filter, no excluded groups. |
| Noncompliance actions | **Mark device noncompliant** after **5 days** (120 hours). No message template, no additional recipients. |

## Configuration description

Every setting not listed is **Not configured**.

### Device Health – Windows Health Attestation Service evaluation rules

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require BitLocker | Require | `bitLockerEnabled` | BitLocker Drive Encryption is on for the OS volume, as reported by DHA at boot. The TPM verifies the device state before releasing keys, so data stays protected if the device is lost, stolen or tampered with. |

> [!WARNING]
> DHA measures BitLocker **only at boot**. A device that has just finished encrypting stays **noncompliant (in grace period)** until it **restarts** and syncs. That's why this policy has the 5-day delay. Tell users to restart after setup.

### Actions for noncompliance

| Action | Schedule | Message template | Additional recipients | Graph |
|---|---|---|---|---|
| Mark device noncompliant | **5 days** | – | None selected | `actionType: "block"`, `gracePeriodHours: 120` |

### Scope tags and assignments

| Item | Value | Graph |
|---|---|---|
| Scope tags | Windows Admin | `roleScopeTagIds: ["<Windows Admin tag ID>"]`. Scope tags are set by **ID**, so the import script looks it up. |
| Included groups | All Devices (Status: Active, Filter: None, Filter mode: None) | `/assign` with an **All devices** assignment target |
| Excluded groups | None | – |

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** (included in Microsoft 365 E3/E5, EMS). **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | Windows 10 / Windows 11 devices **enrolled in Intune** (Autopilot, Entra joined, hybrid joined via auto-enrollment, or co-managed) |
| Hardware | **TPM 2.0** (or 1.2) and UEFI. DHA requires a TPM. |
| Encryption | A BitLocker policy that **turns encryption on**: **Endpoint security > Disk encryption > Create policy > Windows > BitLocker**, with silent encryption and recovery-key escrow to Entra ID. This compliance policy only **checks** BitLocker. It doesn't enable it. |
| Scope tag | Scope tag **Windows Admin** exists: **Tenant administration > Roles > Scope (Tags)** |
| Roles | **Intune Administrator** or **Policy and Profile Manager** with the *Windows Admin* scope tag. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` PowerShell module. Scopes `DeviceManagementConfiguration.ReadWrite.All` and `DeviceManagementRBAC.Read.All` (to read scope tags). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Windows 10 and later**, then select **Create**.
4. **Basics**:
   - **Name**: `Windows-Compliance-AllDevices-Bitlocker-5days`
   - **Description**: `Evaluation delay for newly provisioned devices passing DHA check`
   - Select **Next**.
5. **Compliance settings**:
   - Expand **Device Health > Windows Health Attestation Service evaluation rules** and set **Require BitLocker** = **Require**.
   - Leave everything else **Not configured**, then select **Next**.
6. **Actions for noncompliance**: on the default action **Mark device noncompliant**, set **Schedule (days after noncompliance)** = **5**. Leave the message template empty and additional recipients as *None selected*. Select **Next**.
7. **Scope tags**: select **Select scope tags**, tick **Windows Admin**, then **Select**. Remove **Default** if it is listed and your RBAC model requires it. Select **Next**.
8. **Assignments**: under **Included groups**, select **Add all devices**. Don't add a filter or excluded groups. Select **Next**.
9. **Review + create**: confirm the summary matches the tables above, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
# 1. Connect with rights to create compliance policies and read scope tags
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 2. Look up the ID of the "Windows Admin" scope tag
$tags = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags"
$tagId = ($tags.value | Where-Object displayName -eq "Windows Admin").id
if (-not $tagId) { throw "Scope tag 'Windows Admin' not found" }

# 3. Load the policy JSON and add the scope tag ID
$policyBody = Get-Content ".\Require-BitLocker.json" -Raw | ConvertFrom-Json -AsHashtable   # PowerShell 7
$policyBody.roleScopeTagIds = @($tagId)

# 4. Create the policy (beta, so roleScopeTagIds is accepted)
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body ($policyBody | ConvertTo-Json -Depth 10) -ContentType "application/json"
$policy.id

# 5. Assign to All Devices (no filter)
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"

# 6. Confirm settings, scope tag and assignment
Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=assignments,scheduledActionsForRule(`$expand=scheduledActionConfigurations)"
```

> [!NOTE]
> The `allDevicesAssignmentTarget` type and the `roleScopeTags` list endpoint could not be re-verified on Microsoft Learn when this file was written, because Learn was unreachable. If step 2 or 5 fails, check the current Graph reference and set the scope tag or assignment in the admin center instead (steps 7–8 above).

## Tenant-wide compliance settings to review

Go to **Devices > Manage devices > Compliance > Compliance settings**:

| Setting | Recommended | Why |
|---|---|---|
| Mark devices with no compliance policy assigned as | **Not compliant** | Stops unassessed devices from passing Conditional Access. This policy targets All Devices, so every enrolled Windows device is assessed. |
| Compliance status validity period (days) | **30** (default) | A device that hasn't reported within this period becomes noncompliant |

## Conditional Access integration

1. Go to **Microsoft Entra admin center > Entra ID > Conditional Access > Policies > New policy**.
2. Set **Users** to all users, and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
4. Under **Conditions > Device platforms**, include **Windows**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first, then switch it **On** once devices report compliant.

During the 5-day grace period a device is **In grace period**. CA treats it as **compliant**, so users keep access while BitLocker finishes and the device restarts.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status counts: *Compliant*, *In grace period*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | *Require BitLocker* pass/fail across all devices |
| **Devices > Windows > (device) > Device compliance > (policy)** | Per-setting result for one device |
| **Devices > Monitor > Encryption report** | Encryption readiness and status, plus the TPM version per device |
| On the device | `manage-bde -status C:` shows *Protection On*. **Company Portal > Devices > (this PC) > Check status**. **Settings > Accounts > Access work or school > Info > Sync**. |
| On the device (logs) | `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log`. Run `dsregcmd /status` to confirm the device is joined. |

**Timing:** devices evaluate at check-in. BitLocker status from DHA updates only after a **restart**. After encryption completes, **restart, then Sync**.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment | Sync the device from Company Portal or the admin center |
| **In grace period** | BitLocker not yet reported on, less than 5 days since detection | Expected for new devices. Make sure encryption completes, then restart. |
| *Require BitLocker* still noncompliant although `manage-bde` shows Protection On | DHA measures at boot. The device hasn't restarted since encryption finished. | Restart, then Sync |
| *Require BitLocker* noncompliant, BitLocker **suspended** | Protection suspended (firmware/BIOS update, `Suspend-BitLocker`) | `Resume-BitLocker -MountPoint C:`, then restart |
| Device never encrypts | No BitLocker policy, missing TPM, or a non-admin user and silent encryption not configured | Assign an **Endpoint security > Disk encryption** policy with silent encryption. Check the TPM in the Encryption report. |
| DHA errors on older hardware | TPM 1.2 / legacy BIOS mode | Switch to UEFI, update the TPM firmware, or replace the device |
| Device noncompliant on an old Windows build | Unsupported or stale OS version | Update Windows with a feature update policy |
| Noncompliant and user can't fix it | User not licensed for Intune, or device enrolled under another user | Assign an Intune license. Check the device's primary user. |
| Admin can't see or edit the policy | Admin's role assignment doesn't include the *Windows Admin* scope tag | Add the scope tag to the admin's role assignment |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Lengthen the delay:** raise **Mark device noncompliant** from 5 days if more devices need time, without removing the policy.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove **All devices**.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: devices stop being evaluated for BitLocker by this policy. Their compliance then depends on the other assigned policies, or on *Mark devices with no compliance policy assigned as* if none remain. Encryption on the device is **not** reversed, because only the BitLocker configuration policy controls that.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Windows in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-windows-settings)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [windows10CompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windows10compliancepolicy?view=graph-rest-beta)
- [Use scope tags to filter policies](https://learn.microsoft.com/intune/fundamentals/role-based-access-control/scope-tags)
- [Monitor results of your compliance policies](https://learn.microsoft.com/intune/device-security/compliance/monitor-policy)
- [Encrypt Windows devices with BitLocker in Intune](https://learn.microsoft.com/intune/protect/encrypt-devices)
