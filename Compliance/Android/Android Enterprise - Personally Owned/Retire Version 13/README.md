# AND-BYOD-COMP-Retire Version 13

Intune compliance policy that retires **Android 13 and older** on **personally owned devices with a work profile** (BYOD). Devices below **Android 14** are:

- marked noncompliant **immediately**
- emailed **immediately** and again after **2 days**
- **added to the retire list** after **3 days**

## Purpose

- **Risk addressed:** Android 13 and older releases fall out of security support from Google and many OEMs. Personal devices on those releases keep corporate data in a work profile that no longer gets platform security fixes.
- **Lifecycle enforcement:** this is a version-retirement policy. It has one rule (minimum Android 14) and a stepped escalation:
  1. Access is blocked at once.
  2. The user is told to upgrade.
  3. If the device still isn't upgraded after 3 days, it is queued for retirement.
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a BYOD device on Android 13 or older loses access to Microsoft 365 and other Entra-protected apps immediately.
- **Works with** the [BYOD default policy](../Default%20Compliance%20Policy/README.md), which also requires 14.0 but adds the security settings and a 6-hour grace period without a retire step. A device is compliant only if **every** assigned policy passes, so this policy's *Immediate* block applies to version failures.

## Policy summary

| Item | Value |
|---|---|
| Display name | `AND-BYOD-COMP-Retire Version 13` (naming standard, as no name was given) |
| Platform | Android Enterprise |
| Profile type | Personally-owned work profile |
| Graph `@odata.type` | `#microsoft.graph.androidWorkProfileCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Retire-Version-13.json` |
| Assignment target | **User groups** of BYOD users (same scope as the BYOD default policy), plus an **excluded** group for approved exceptions |
| Noncompliance actions | **Mark device noncompliant** immediately. **Send email to end user** immediately. **Send email to end user** after 2 days. **Add device to retire list** after 3 days. |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint, where `androidWorkProfileCompliancePolicy` is documented. It also keeps all Android Enterprise policies on the same API version.

## Configuration description

Every setting not listed is **Not configured**. This policy checks the OS version only.

### Device Properties

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum OS version | `14.0` | `osMinimumVersion` | Any device below **Android 14** (Android 13 or older) is noncompliant. The user sees a link with upgrade information. |

### Actions for noncompliance

| # | Action | Schedule | Message template | Additional recipients | Graph |
|---|---|---|---|---|---|
| 1 | Mark device noncompliant | **Immediately** | – | None selected | `actionType: "block"`, `gracePeriodHours: 0` |
| 2 | Send email to end user | **Immediately** | Your template | None selected | `actionType: "notification"`, `gracePeriodHours: 0` |
| 3 | Send email to end user | **2 days** | Your template | None selected | `actionType: "notification"`, `gracePeriodHours: 48` |
| 4 | Add device to retire list | **3 days** | – | None selected | `actionType: "retire"`, `gracePeriodHours: 72` |

> [!WARNING]
> **Add device to retire list does not retire the device automatically.**
> - After 3 days the device appears in **Devices > Manage devices > Compliance > Retire noncompliant devices**.
> - It's retired only when an admin selects it, chooses **Retire selected devices**, and confirms.
> - On a personally owned work profile device, retiring **removes the work profile** (corporate apps and data) and removes the device from Intune management. Personal apps and data stay.
> - Use *Clear selected devices retire state* for devices that were upgraded or have an approved exception.

> [!NOTE]
> The email actions reference a **notification message template** by ID. The JSON contains the placeholder `<notification-template-id>`. Replace it (the import script does this), or pick the template in the admin center. A good template explains how to check for Android updates, what happens after 3 days, and who to contact if the phone can't be upgraded. Templates are under **Devices > Manage devices > Compliance > Notifications**.

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** per user. **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | **Android Enterprise personally-owned work profile**, enrolled through the **Company Portal** app. Intune must be connected to **Managed Google Play**. |
| OEM support | Users' models must have an Android 14 update from the OEM or carrier. Models that can't upgrade will fail permanently. Plan communication and an exception process. |
| Device administrator | **Not used.** Android device administrator is deprecated and unavailable on GMS devices. |
| Notification template | At least one template under **Devices > Manage devices > Compliance > Notifications** |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. Retiring devices from the list needs a role with the **Retire** permission. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All` and `DeviceManagementServiceConfig.Read.All` (templates). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Android Enterprise**. **Profile type**: select **Personally-owned work profile**. Select **Create**.
4. **Basics**: set **Name** to `AND-BYOD-COMP-Retire Version 13`, and paste the description from the JSON. Select **Next**.
5. **Compliance settings**: **Device Properties** > Minimum OS version = `14.0`. Leave everything else **Not configured**. Select **Next**.
6. **Actions for noncompliance**:
   1. Keep **Mark device noncompliant** with **Schedule** = **0** (Immediately).
   2. **Add** > **Send email to end user**. Set Schedule **0**, **Message template** = your template, no additional recipients.
   3. **Add** > **Send email to end user**. Set Schedule **2**, **Message template** = your template, no additional recipients.
   4. **Add** > **Add device to retire list**, with Schedule **3**.
   5. Select **Next**.
7. **Scope tags**: select your Android RBAC tag (or keep **Default**), then select **Next**.
8. **Assignments**: **Add groups** and select the BYOD user group. Under **Excluded groups**, add an exceptions group. Select **Next**.
9. **Review + create**: confirm the summary matches the tables above, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
# 1. Connect with rights to create compliance policies and read notification templates
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementServiceConfig.Read.All"

# 2. Resolve the email notification template
$templateName = "<your notification template name>"
$templates  = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/notificationMessageTemplates"
$templateId = ($templates.value | Where-Object displayName -eq $templateName).id
if (-not $templateId) { throw "Notification template not found" }

# 3. Load the JSON and insert the template ID
$body = (Get-Content ".\Retire-Version-13.json" -Raw) -replace '<notification-template-id>', $templateId

# 4. Create the policy (beta endpoint)
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body $body -ContentType "application/json"

# 5. Assign to the BYOD user group, excluding an exceptions group (replace both IDs)
$includeId = "<byod-user-group-id>"
$excludeId = "<byod-exceptions-group-id>"
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
> The `notificationMessageTemplates` lookup and the `exclusionGroupAssignmentTarget` type weren't re-verified on Microsoft Learn for this file. If either fails, create the policy with the JSON and finish the emails and assignment in the admin center.

## Tenant-wide compliance settings to review

Go to **Devices > Manage devices > Compliance > Compliance settings**:

| Setting | Recommended | Why |
|---|---|---|
| Mark devices with no compliance policy assigned as | **Not compliant** | Stops unassessed devices from passing Conditional Access |
| Compliance status validity period (days) | **30** (default) | A device that hasn't reported within this period becomes noncompliant |

## Conditional Access integration

1. Go to **Microsoft Entra admin center > Entra ID > Conditional Access > Policies > New policy**.
2. Set **Users** to BYOD users (or all users), and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
4. Under **Conditions > Device platforms**, include **Android**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first. Check how many BYOD devices are still on Android 13 or older before switching it **On**, because the block is immediate.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status: *Compliant* (Android 14+), *Not compliant* (13 or older), *Not evaluated* |
| **Devices > Android** (add the **OS version** column, filter by ownership *Personal*) | Inventory of BYOD devices still below 14 before and after assignment |
| **Devices > Manage devices > Compliance > Retire noncompliant devices** | Devices noncompliant for ≥ 3 days, waiting for an admin decision |
| **Devices > Android > (device) > Device compliance > (policy)** | *Minimum OS version* result for one device |
| On the device | **Settings > About phone > Android version** (must be 14+). **Company Portal > Devices > (this device) > Check device settings**. |
| Mail | The user receives the template email on day 0 and day 2 |

**Timing:** devices evaluate at check-in. After upgrading, open **Company Portal > Check device settings** to re-evaluate straight away.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or the user isn't in the assigned group | Open Company Portal > **Check device settings**. Check group membership. |
| **In grace period** | Not expected for the block, which is immediate | If shown, another assigned policy (e.g. the BYOD default, 6 h) is still in its grace period |
| Upgraded to Android 14 but still noncompliant | Device hasn't checked in since the upgrade (stale OS version reported) | Restart, then Company Portal > **Check device settings** |
| No Android 14 update offered | OEM/carrier doesn't support Android 14 for that model | Add the user to the exception group (temporarily) and plan a device change. Clear its retire state. |
| Device in the retire list after it was upgraded | Retire state stays until cleared | Select it, then **Clear selected devices retire state** |
| Device Health attestation "needs restart" | Not applicable. That's a Windows behaviour. | – |
| No emails received | Template missing, or the user has no mailbox | Check the template under **Compliance > Notifications** and the user's mailbox |
| Noncompliant and user can't fix it | User not licensed for Intune | Assign an Intune license |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Stop retirements:** open **Retire noncompliant devices** and choose **Clear all devices retire state**. Remove the *Add device to retire list* action, or raise its schedule.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: BYOD devices are then governed only by other assigned Android policies (e.g. the BYOD default, which still requires 14.0). **Devices already retired can't be rolled back**. Users must re-enroll through Company Portal to recreate the work profile.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Android Enterprise in Intune (personally owned work profile)](https://learn.microsoft.com/intune/device-security/compliance/ref-android-enterprise-settings#personally-owned-work-profile)
- [Configure actions for noncompliant devices (Add device to retire list)](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions#available-actions-for-noncompliance)
- [Device action: retire](https://learn.microsoft.com/intune/device-management/actions/retire)
- [androidWorkProfileCompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-androidworkprofilecompliancepolicy?view=graph-rest-beta)
