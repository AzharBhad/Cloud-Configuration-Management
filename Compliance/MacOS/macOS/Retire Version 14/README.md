# macOS - Retire Version 14

Intune compliance policy that retires **macOS 14 (Sonoma) and older**. Macs below **macOS 15** are:

- marked noncompliant **immediately**
- emailed **immediately** and again after **2 days**
- **added to the retire list** after **3 days**

## Purpose

- **Risk addressed:** Macs on macOS 14 or older miss security fixes that only ship for current releases. Keeping them out of corporate resources reduces exposure to known, patched vulnerabilities.
- **Lifecycle enforcement:** this is a version-retirement policy. It has one rule (minimum OS 15) and a stepped escalation:
  1. Access is blocked at once.
  2. The user is told what to do.
  3. If the Mac still isn't upgraded after 3 days, it is queued for retirement.
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a Mac on macOS 14 loses access to Microsoft 365 and other Entra-protected apps immediately.
- **Works with** the [Default Compliance Policy](../Default%20Compliance%20Policy/README.md), which also requires macOS 15.0 but adds the security settings, a 6-hour grace period and no retire step. A Mac is compliant only if **every** assigned policy passes, so this policy's *Immediate* block applies to version failures.

## Policy summary

| Item | Value |
|---|---|
| Display name | `macOS - Retire Version 14` |
| Description | *(empty, as in the source policy)* |
| Platform | macOS |
| Profile type | Mac compliance policy |
| Graph `@odata.type` | `#microsoft.graph.macOSCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies`. The settings are valid on v1.0 too. Beta is used to set the scope tag. |
| File | `Retire-Version-14.json` |
| Scope tags | **Mac Admin** |
| Assignment target | Not visible in the source screenshot. Recommended: **all corporate Macs** (a device group, or user groups of Mac users). |
| Noncompliance actions | **Mark device noncompliant** immediately. **Send email to end user** immediately. **Send email to end user** after 2 days. **Add device to retire list** after 3 days. |

## Configuration description

Every setting not listed is **Not configured**. Device Health, System Security, Password and Defender for Endpoint are all unset. This policy checks the OS version only.

### Device Properties

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum OS version | `15` | `osMinimumVersion` | Any Mac below **macOS 15 (Sequoia)**, i.e. macOS 14 Sonoma or older, is noncompliant. The user sees a link with upgrade information. |

### Actions for noncompliance

| # | Action | Schedule | Message template | Additional recipients | Graph |
|---|---|---|---|---|---|
| 1 | Mark device noncompliant | **Immediately** | – | None selected | `actionType: "block"`, `gracePeriodHours: 0` |
| 2 | Send email to end user | **Immediately** | Selected (your template) | None selected | `actionType: "notification"`, `gracePeriodHours: 0` |
| 3 | Send email to end user | **2 days** | Selected (your template) | None selected | `actionType: "notification"`, `gracePeriodHours: 48` |
| 4 | Add device to retire list | **3 days** | – | None selected | `actionType: "retire"`, `gracePeriodHours: 72` |

> [!WARNING]
> **Add device to retire list does not retire the Mac automatically.**
> - After 3 days the Mac appears in **Devices > Manage devices > Compliance > Retire noncompliant devices**.
> - It's retired only when an admin selects it and chooses **Retire selected devices**, then confirms.
> - Retiring **removes all company data** (apps, profiles, email) and **removes the Mac from Intune management**.
> - Use *Clear selected devices retire state* for any Mac that was upgraded or has an approved exception.

> [!NOTE]
> The email actions reference a **notification message template** by ID. The JSON contains the placeholder `<notification-template-id>`. Replace it with your template's ID (the import script does this), or pick the template in the admin center. The template name wasn't visible in the screenshot. A good template explains how to upgrade to macOS 15 and the 3-day retire deadline. Templates are under **Devices > Manage devices > Compliance > Notifications**.

### Scope tags

| Item | Value | Graph |
|---|---|---|
| Scope tags | Mac Admin | `roleScopeTagIds` (tag **ID**, resolved by the import script) |

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1**. **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | Macs **enrolled in Intune** (Automated Device Enrollment or Company Portal). Users need **Company Portal** to see status. |
| Hardware | Every in-scope Mac must **support macOS 15**. Hardware that can't upgrade will fail this policy permanently, so plan replacement or an exception group before assignment. |
| Upgrade path | A macOS **software update** policy (Declarative Device Management) or user-initiated upgrade, so users can comply within 3 days |
| Notification template | At least one template under **Devices > Manage devices > Compliance > Notifications** |
| Scope tag | **Mac Admin** exists under **Tenant administration > Roles > Scope (tags)** |
| Roles | **Intune Administrator** or **Policy and Profile Manager** with the *Mac Admin* scope tag. Retiring devices from the list needs a role with the **Retire** permission. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All`, `DeviceManagementServiceConfig.Read.All` (templates) and `DeviceManagementRBAC.Read.All` (scope tags). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **macOS**, then select **Create**.
4. **Basics**: set **Name** to `macOS - Retire Version 14`. Leave **Description** empty or add one. Select **Next**.
5. **Compliance settings**: **Device Properties** > Minimum OS version = `15`. Leave everything else **Not configured**. Select **Next**.
6. **Actions for noncompliance**:
   1. Keep **Mark device noncompliant** with **Schedule** = **0** (Immediately).
   2. **Add** > **Send email to end user**. Set Schedule **0**, **Message template** = your template, **Additional recipients** = none.
   3. **Add** > **Send email to end user**. Set Schedule **2**, **Message template** = your template, **Additional recipients** = none.
   4. **Add** > **Add device to retire list**, with Schedule **3**.
   5. Select **Next**.
7. **Scope tags**: **Select scope tags**, tick **Mac Admin**, then **Select**. Select **Next**.
8. **Assignments**: **Add groups**, select your corporate Mac group, and add an **excluded** group for approved exceptions (e.g. Macs that can't run macOS 15). Select **Next**.
9. **Review + create**: confirm the summary matches the tables above, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
# 1. Connect with rights to create compliance policies, read templates and scope tags
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementServiceConfig.Read.All","DeviceManagementRBAC.Read.All"

# 2. Resolve the notification template and the "Mac Admin" scope tag
$templateName = "<your notification template name>"
$templates  = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/notificationMessageTemplates"
$templateId = ($templates.value | Where-Object displayName -eq $templateName).id
$tags  = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags"
$tagId = ($tags.value | Where-Object displayName -eq "Mac Admin").id
if (-not $templateId -or -not $tagId) { throw "Notification template or scope tag not found" }

# 3. Load the JSON, insert the template ID and scope tag (PowerShell 7)
$raw        = (Get-Content ".\Retire-Version-14.json" -Raw) -replace '<notification-template-id>', $templateId
$policyBody = $raw | ConvertFrom-Json -AsHashtable
$policyBody.roleScopeTagIds = @($tagId)

# 4. Create the policy
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body ($policyBody | ConvertTo-Json -Depth 10) -ContentType "application/json"

# 5. Assign to your Mac group, excluding an exceptions group (replace both IDs)
$includeId = "<corporate-mac-group-id>"
$excludeId = "<mac-exceptions-group-id>"
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget";          groupId = $includeId } },
    @{ target = @{ "@odata.type" = "#microsoft.graph.exclusionGroupAssignmentTarget"; groupId = $excludeId } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"

# 6. Confirm settings, actions and assignment
Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=assignments,scheduledActionsForRule(`$expand=scheduledActionConfigurations)"
```

> [!NOTE]
> These parts weren't re-verified on Microsoft Learn for this file:
> - the `notificationMessageTemplates` and `roleScopeTags` lookups
> - the `exclusionGroupAssignmentTarget` type
>
> If any step fails, create the policy with the JSON and finish the emails, scope tag and assignment in the admin center.

## Tenant-wide compliance settings to review

Go to **Devices > Manage devices > Compliance > Compliance settings**:

| Setting | Recommended | Why |
|---|---|---|
| Mark devices with no compliance policy assigned as | **Not compliant** | Stops unassessed Macs from passing Conditional Access |
| Compliance status validity period (days) | **30** (default) | A Mac that hasn't reported within this period becomes noncompliant |

## Conditional Access integration

1. Go to **Microsoft Entra admin center > Entra ID > Conditional Access > Policies > New policy**.
2. Set **Users** to all users (or Mac users), and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
4. Under **Conditions > Device platforms**, include **macOS**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first. Check how many Macs are still on macOS 14 before switching it **On**, because the block is immediate.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status: *Compliant* (macOS 15+), *Not compliant* (macOS 14 or older), *Not evaluated* |
| **Devices > macOS** (add the **OS version** column) | Inventory of Macs still below 15 before and after assignment |
| **Devices > Manage devices > Compliance > Retire noncompliant devices** | Macs noncompliant for ≥ 3 days, waiting for an admin decision |
| **Devices > macOS > (device) > Device compliance > (policy)** | *Minimum OS version* result for one Mac |
| On the Mac | `sw_vers -productVersion` (must be 15.x or later). **Company Portal > (this Mac) > Check status**. |
| Mail | The user receives the template email on day 0 and day 2 |

**Timing:** Macs evaluate at MDM check-in. To force an evaluation after upgrading, open **Company Portal > Check status**, or select **Sync** for the device.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Mac hasn't checked in since assignment, or isn't in the assigned group | Sync from Company Portal or the admin center. Check group membership. |
| **In grace period** | Not expected for the block, which is immediate | If shown, another assigned policy (e.g. *Default*, 6 h) is still in its grace period |
| Mac upgraded to macOS 15 but still noncompliant | Mac hasn't checked in since the upgrade (stale OS version reported) | Open Company Portal > **Check status**, or Sync, then confirm the OS version in Intune |
| Mac can't upgrade to macOS 15 | Unsupported hardware | Add it to the exception group and plan replacement. Clear its retire state. |
| Mac shows in the retire list after it was upgraded | Retire state stays until cleared | Select it, then **Clear selected devices retire state** |
| Device Health attestation "needs restart" | Not applicable. That's a Windows DHA behaviour. | – |
| No emails received | Template missing, or user has no mailbox | Check the template under **Compliance > Notifications** and the user's mailbox |
| Noncompliant and user can't fix it | User not licensed for Intune, or Mac enrolled under another user | Assign an Intune license. Check the primary user. |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Stop retirements:** open **Retire noncompliant devices** and choose **Clear all devices retire state**. Remove the *Add device to retire list* action, or raise its schedule.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: Macs are then governed only by other macOS policies (e.g. *Default*, which still requires 15.0). If none remain, *Mark devices with no compliance policy assigned as* decides. **Macs already retired can't be rolled back**. They must be re-enrolled in Intune.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for macOS in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-macos-settings)
- [Configure actions for noncompliant devices (Add device to retire list)](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions#available-actions-for-noncompliance)
- [Device action: retire](https://learn.microsoft.com/intune/device-management/actions/retire)
- [macOSCompliancePolicy resource type](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-macoscompliancepolicy?view=graph-rest-1.0)
- [deviceComplianceActionItem resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-devicecomplianceactionitem?view=graph-rest-beta)
