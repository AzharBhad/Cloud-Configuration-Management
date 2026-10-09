# AND-CORP-COMP-Retire Version 13

Intune compliance policy that retires **Android 13 and older** on **corporate-owned Android devices (COD)**: fully managed, dedicated, and corporate-owned work profile. Devices below **Android 14**, or without a **Numeric** (or stronger) password, are:

- marked noncompliant **immediately**
- emailed **immediately** and again after **2 days**
- **added to the retire list** after **3 days**

## Purpose

- **Risk addressed:** Android 13 and older releases fall out of security support from Google and many OEMs. Corporate devices on them hold full corporate access without current platform security fixes. A device without a screen lock exposes that access if lost.
- **Lifecycle enforcement:** this is a version-retirement policy. It requires Android 14 and a device password, with a stepped escalation:
  1. Access is blocked at once.
  2. The user is told to upgrade.
  3. If the device still isn't upgraded after 3 days, it is queued for retirement.
- **Corporate advantage:** IT can push the Android 14 upgrade with a **system update** policy, so most devices should comply before the retire step. The retire list then mainly catches hardware that can't upgrade, which is the trigger for device replacement.
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a corporate device on Android 13 or older loses access to Microsoft 365 and other Entra-protected apps immediately.
- **Works with** the [COD default policy](../Default%20Compliance%20Policy/README.md) (Android 14.0, numeric complex minimum 6, 6-hour grace). A device must pass **every** assigned policy, so the stricter default password rules still apply.

## Policy summary

| Item | Value |
|---|---|
| Display name | `AND-CORP-COMP-Retire Version 13` (naming standard, as no name was given) |
| Platform | Android Enterprise |
| Profile type | Fully managed, dedicated, and corporate-owned work profile |
| Graph `@odata.type` | `#microsoft.graph.androidDeviceOwnerCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Retire-Version-13.json` |
| Assignment target | **Device groups** of corporate Android devices (same scope as the COD default policy), plus an **excluded** group for approved exceptions |
| Noncompliance actions | **Mark device noncompliant** immediately. **Send email to end user** immediately. **Send email to end user** after 2 days. **Add device to retire list** after 3 days. |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint, where `androidDeviceOwnerCompliancePolicy` is documented.

## Configuration description

Every setting not listed is **Not configured**.

### Device Properties

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum OS version | `14.0` | `osMinimumVersion` | Any device below **Android 14** (Android 13 or older) is noncompliant. The user sees a link with upgrade information. |

### System Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require a password to unlock mobile devices | Require | `passwordRequired: true` | A device screen lock is set. Needed so the password type below is evaluated. |
| Required password type | **Numeric** (BYOD label: *At least numeric*) | `passwordRequiredType: "numeric"` | The password must be at least a numeric PIN. Stronger types also pass. |

> [!NOTE]
> "At least numeric" is the label in the personally owned profile. In the **corporate** profile the same option is labelled **Numeric** ("Password must only be numbers, such as 123456789"). Both map to Graph `numeric`. Simple PINs like `1111` are allowed here, but the COD default policy's *Numeric complex*, minimum 6 still applies when both policies are assigned.

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
> - Retiring **removes company data** and **removes the device from Intune management**.
> - For corporate hardware you'll normally reassign or wipe the device afterwards. Check Microsoft's retire guidance for what retire does on fully managed, dedicated and COPE devices before acting on the list.
> - Use *Clear selected devices retire state* for devices that were upgraded or have an approved exception.

> [!NOTE]
> - **Email template:** the email actions reference a **notification message template** by ID. The JSON contains the placeholder `<notification-template-id>`. Replace it (the import script does this), or pick the template in the admin center. Templates are under **Devices > Manage devices > Compliance > Notifications**.
> - **Dedicated (userless) devices** have no user to email, so only the block and retire-list actions affect them.

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** (per user, or Intune Device license for userless dedicated devices). **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | **Android Enterprise** fully managed, dedicated or corporate-owned work profile. Intune must be connected to **Managed Google Play**. |
| Upgrade path | A **system update** policy so devices reach Android 14. Each model must have an Android 14 release from the OEM. |
| Hardware plan | A replacement plan for models that can't run Android 14, and an exception group while they're replaced |
| Device administrator | **Not used.** Android device administrator is deprecated and unavailable on GMS devices. |
| Notification template | At least one template under **Devices > Manage devices > Compliance > Notifications** |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. Retiring from the list needs a role with the **Retire** permission. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All` and `DeviceManagementServiceConfig.Read.All` (templates). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Android Enterprise**. **Profile type**: select **Fully managed, dedicated, and corporate-owned work profile**. Select **Create**.
4. **Basics**: set **Name** to `AND-CORP-COMP-Retire Version 13`, and paste the description from the JSON. Select **Next**.
5. **Compliance settings**:
   1. **Device Properties**: Minimum OS version = `14.0`.
   2. **System Security**: Require a password to unlock mobile devices = **Require**, Required password type = **Numeric**.
   3. Leave everything else **Not configured**, then select **Next**.
6. **Actions for noncompliance**:
   1. Keep **Mark device noncompliant** with **Schedule** = **0** (Immediately).
   2. **Add** > **Send email to end user**. Set Schedule **0**, **Message template** = your template, no additional recipients.
   3. **Add** > **Send email to end user**. Set Schedule **2**, **Message template** = your template, no additional recipients.
   4. **Add** > **Add device to retire list**, with Schedule **3**.
   5. Select **Next**.
7. **Scope tags**: select your Android RBAC tag (or keep **Default**), then select **Next**.
8. **Assignments**: **Add groups** and select the corporate Android device group. Under **Excluded groups**, add an exceptions group. Select **Next**.
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

# 5. Assign to the corporate Android device group, excluding an exceptions group (replace both IDs)
$includeId = "<corporate-android-device-group-id>"
$excludeId = "<corporate-android-exceptions-group-id>"
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
2. Set **Users** to all users (or corporate Android users), and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
4. Under **Conditions > Device platforms**, include **Android**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first. Check how many corporate devices are still on Android 13 or older before switching it **On**, because the block is immediate.

> [!TIP]
> Exclude the **Microsoft Intune** cloud app from any CA policy that requires compliance for all cloud apps on Android. Microsoft notes that corporate Android enrollment authenticates through a Chrome tab, so re-enrolling a replacement device would otherwise be blocked.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status: *Compliant* (Android 14+ with a password), *Not compliant*, *Not evaluated* |
| **Devices > Android** (add the **OS version** column, filter by ownership *Corporate*) | Inventory of corporate devices still below 14 |
| **Devices > Manage devices > Compliance > Retire noncompliant devices** | Devices noncompliant for ≥ 3 days, waiting for an admin decision |
| **Devices > Android > (device) > Device compliance > (policy)** | *Minimum OS version* and *Required password type* results for one device |
| On the device | **Settings > About phone > Android version** (must be 14+). **Microsoft Intune app > Check compliance**. |
| Mail | The user receives the template email on day 0 and day 2 (not on userless dedicated devices) |

**Timing:** devices evaluate at check-in. After upgrading, use **Intune app > Check compliance**, or select **Sync** in the admin center.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or isn't in the assigned device group | Sync the device. Check group membership. |
| **In grace period** | Not expected for the block, which is immediate | If shown, another assigned policy (e.g. the COD default, 6 h) is still in its grace period |
| Upgraded to Android 14 but still noncompliant | Device hasn't checked in since the upgrade (stale OS version reported) | Restart, then Intune app > **Check compliance** |
| No Android 14 update offered | Model doesn't support Android 14, or the system update policy is blocking it | Check the OEM support list and the system update policy. Add to the exception group while replacing. |
| *Required password type* noncompliant | No screen lock (or pattern / swipe) | Set a numeric PIN or stronger |
| Device in the retire list after it was upgraded | Retire state stays until cleared | Select it, then **Clear selected devices retire state** |
| Device Health attestation "needs restart" | Not applicable. That's a Windows behaviour. | – |
| No emails | Dedicated (userless) device, template missing, or no mailbox | Expected for userless devices. Otherwise check the template and mailbox. |
| Noncompliant and user can't fix it | User or device not licensed for Intune | Assign an Intune user or device license |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Stop retirements:** open **Retire noncompliant devices** and choose **Clear all devices retire state**. Remove the *Add device to retire list* action, or raise its schedule.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: corporate devices are then governed only by the other assigned Android Enterprise corporate policies (e.g. the COD default, which still requires 14.0). **Devices already retired can't be rolled back**. They must be re-enrolled (usually after a factory reset) with the corporate enrollment profile.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Android Enterprise in Intune (fully managed, dedicated, corporate-owned work profile)](https://learn.microsoft.com/intune/device-security/compliance/ref-android-enterprise-settings#fully-managed,-dedicated,-and-corporate-owned-work-profile)
- [Configure actions for noncompliant devices (Add device to retire list)](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions#available-actions-for-noncompliance)
- [Device action: retire](https://learn.microsoft.com/intune/device-management/actions/retire)
- [Enroll Android Enterprise dedicated, fully managed, or corporate-owned work profile devices](https://learn.microsoft.com/intune/device-enrollment/android/ref-corporate-methods)
- [androidDeviceOwnerCompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-androiddeviceownercompliancepolicy?view=graph-rest-beta)
