# AND-BYOD-COMP-Security Patch Level

Intune compliance policy for **personally owned Android devices with a work profile** (BYOD). It requires Android **security patch level 2025-01-05** or later. Devices below it are marked noncompliant after **0.25 days (6 hours)**, and users are emailed **immediately** and again after **2 days**.

## Purpose

- **Risk addressed:** Android devices that don't install monthly security updates stay exposed to publicly disclosed vulnerabilities, some of which allow remote code execution or privilege escalation. A minimum patch level blocks corporate access from devices that are far behind.
- **Why a separate policy:** keeping the patch level in its own policy lets you raise the date regularly (e.g. every quarter) without editing the [BYOD default policy](../Default%20Compliance%20Policy/README.md). A device is compliant only if **every** assigned policy passes, so both policies apply together.
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a BYOD device below the patch level loses access to Microsoft 365 and other Entra-protected apps once the 6-hour grace period ends.
- **User experience:** the immediate email explains how to install the update (**Settings > Security / System > Software update**). The 2-day email reminds users who haven't updated yet.

## Policy summary

| Item | Value |
|---|---|
| Display name | `AND-BYOD-COMP-Security Patch Level` (naming standard, as no name was given) |
| Platform | Android Enterprise |
| Profile type | Personally-owned work profile |
| Graph `@odata.type` | `#microsoft.graph.androidWorkProfileCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Security-Patch-Level.json` |
| Assignment target | **User groups** of BYOD users (same scope as the BYOD default policy) |
| Noncompliance actions | **Mark device noncompliant** after **0.25 days** (6 h). **Send email to end user** **immediately**. **Send email to end user** after **2 days**. |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint, where `androidWorkProfileCompliancePolicy` and `minAndroidSecurityPatchLevel` are documented. It also keeps all Android Enterprise policies on the same API version.

## Configuration description

Every setting not listed is **Not configured**. This policy checks the security patch level only.

### Device Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum security patch level | `2025-01-05` | `minAndroidSecurityPatchLevel` | The oldest Android security patch level a device can have. Devices with an older patch level are noncompliant. The date must be in **YYYY-MM-DD** format and should match an [Android Security Bulletin](https://source.android.com/security/bulletin/) level (`-01` or `-05`). |

> [!WARNING]
> **The date is old.** `2025-01-05` is roughly 21 months behind today (October 2026), so it only blocks severely outdated devices.
> - Consider a rolling target, e.g. **no older than 3 months**, and raise the date on a schedule.
> - Before raising it, check that the OEMs and carriers your users have actually ship that patch. Microsoft notes that Android patch delivery depends on OEMs and carriers, so a date that's too recent blocks users who can't update.

### Actions for noncompliance

| Action | Schedule | Message template | Additional recipients | Graph |
|---|---|---|---|---|
| Mark device noncompliant | **0.25 days** (6 hours) | – | None selected | `actionType: "block"`, `gracePeriodHours: 6` |
| Send email to end user | **Immediately** | Your template | None selected | `actionType: "notification"`, `gracePeriodHours: 0` |
| Send email to end user | **2 days** | Your template | None selected | `actionType: "notification"`, `gracePeriodHours: 48` |

> [!NOTE]
> The email actions reference a **notification message template** by ID. The JSON contains the placeholder `<notification-template-id>`. Replace it with your template's ID (the import script does this), or pick the template in the admin center. A good template names the required patch level and links to update instructions. Templates are under **Devices > Manage devices > Compliance > Notifications**.

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** per user. **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | **Android Enterprise personally-owned work profile**, enrolled through the **Company Portal** app. Intune must be connected to **Managed Google Play**. |
| OEM updates | Users' device models must still receive security updates from the OEM or carrier. End-of-support models can never become compliant. |
| Device administrator | **Not used.** Android device administrator is deprecated and unavailable on GMS devices. |
| Notification template | At least one template under **Devices > Manage devices > Compliance > Notifications** |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All` and `DeviceManagementServiceConfig.Read.All` (templates). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Android Enterprise**. **Profile type**: select **Personally-owned work profile**. Select **Create**.
4. **Basics**: set **Name** to `AND-BYOD-COMP-Security Patch Level`, and paste the description from the JSON. Select **Next**.
5. **Compliance settings**: expand **System Security > Device Security** and set **Minimum security patch level** = `2025-01-05`. Leave everything else **Not configured**. Select **Next**.
6. **Actions for noncompliance**:
   1. On **Mark device noncompliant**, set **Schedule** = **0.25**.
   2. **Add** > **Send email to end user**. Set Schedule **0**, **Message template** = your template, no additional recipients.
   3. **Add** > **Send email to end user**. Set Schedule **2**, **Message template** = your template, no additional recipients.
   4. Select **Next**.
7. **Scope tags**: select your Android RBAC tag (or keep **Default**), then select **Next**.
8. **Assignments**: **Add groups** and select the BYOD user group (pilot first). Select **Next**.
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
$body = (Get-Content ".\Security-Patch-Level.json" -Raw) -replace '<notification-template-id>', $templateId

# 4. Create the policy (beta endpoint)
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body $body -ContentType "application/json"

# 5. Assign it to the BYOD user group (replace with your group's object ID)
$groupId = "<byod-user-group-object-id>"
$assign  = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $groupId } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"

# 6. Later: raise the patch level without recreating the policy
Invoke-MgGraphRequest -Method PATCH `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)" `
  -Body (@{ "@odata.type" = "#microsoft.graph.androidWorkProfileCompliancePolicy"; minAndroidSecurityPatchLevel = "2026-07-01" } | ConvertTo-Json) `
  -ContentType "application/json"
```

> [!NOTE]
> The `notificationMessageTemplates` lookup in step 2 wasn't re-verified on Microsoft Learn for this file. If it fails, remove the two `notification` actions from the JSON, create the policy, then add the emails in the admin center.

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
6. Set **Enable policy** to **Report-only** first. Check how many devices fail the patch level before switching it **On**.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status counts: *Compliant*, *In grace period*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | *Minimum security patch level* pass/fail across devices |
| **Devices > Android > (device) > Hardware** | The device's reported **security patch level** |
| On the device | **Settings > About phone > Android version > Android security update** shows the patch date. **Company Portal > Devices > (this device) > Check device settings** shows the failing setting. |
| Mail | The user receives the template email on day 0 and day 2 |

**Timing:** devices evaluate at check-in. After updating, open **Company Portal > Check device settings** to re-evaluate straight away.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or the user isn't in the assigned group | Open Company Portal > **Check device settings**. Check group membership. |
| **In grace period** | Patch level failed less than 6 hours ago | Expected. Install the update before the 6 hours end. |
| Noncompliant but no update is offered | OEM/carrier hasn't released the patch for that model, or the model is out of support | Confirm with the OEM. Replace end-of-support devices. Consider an exception group while the OEM catches up. |
| Updated but still noncompliant | Device hasn't checked in since updating (stale OS / patch level reported) | Restart, then Company Portal > **Check device settings** |
| Many devices fail at once | Patch date set newer than OEMs have shipped | Move the date back to a level your fleet has received, then raise it gradually |
| Device Health attestation "needs restart" | Not applicable. That's a Windows behaviour. | – |
| No emails received | Template missing, or the user has no mailbox | Check the template under **Compliance > Notifications** and the user's mailbox |
| Noncompliant and user can't fix it | User not licensed for Intune | Assign an Intune license |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Relax the date:** move `minAndroidSecurityPatchLevel` to an older date (PATCH call above or admin center). This is quicker than unassigning.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: BYOD devices are then governed only by the other assigned Android policies (e.g. the BYOD default policy). Nothing changes on the device itself.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Android Enterprise in Intune (personally owned work profile)](https://learn.microsoft.com/intune/device-security/compliance/ref-android-enterprise-settings#personally-owned-work-profile)
- [Android Enterprise personally-owned work profile security configurations](https://learn.microsoft.com/intune/device-security/security-configurations/android-personally-owned)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [androidWorkProfileCompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-androidworkprofilecompliancepolicy?view=graph-rest-beta)
