# iOS - Compliance Policy - Default - COD

Default Intune compliance policy for **corporate-owned (COD) iPhones and iPads**. It requires:

- No jailbreak
- iOS/iPadOS **18.0** or later
- **TikTok** and **TikTok Lite** not installed
- A passcode: simple passcodes blocked, minimum 6, numeric or stronger, the last 5 can't be reused, passcode required **immediately** after screen lock, screen locks after **5 minutes**

Devices are marked noncompliant after **0.25 days (6 hours)**. Users get push notifications and emails **immediately** and again after **2 days**.

## Purpose

- **Risk addressed:** corporate iPhones and iPads carry full corporate access. This policy blocks access from devices that:
  - are jailbroken
  - run an outdated iOS release
  - have no or a weak passcode
  - have prohibited apps (TikTok, TikTok Lite) installed, because of data-privacy concerns
- **Stricter than BYOD:** the passcode is required **immediately** after the screen locks (BYOD allows 5 minutes). A corporate device that's picked up while locked always needs the passcode.
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a corporate device that fails any check loses access to Microsoft 365 and other Entra-protected apps once the 6-hour grace period ends.
- **User experience:** a push notification through Company Portal and an email tell the user straight away what to fix. A reminder follows on day 2.
- **Related:** [BYOD default policy](../Default%20BYOD%20Compliance%20Policy/README.md).

## Policy summary

| Item | Value |
|---|---|
| Display name | `iOS - Compliance Policy - Default - COD` |
| Description | *(not shown in the source screenshot; left empty)* |
| Platform | iOS/iPadOS |
| Profile type | – (single profile for this platform) |
| Graph `@odata.type` | `#microsoft.graph.iosCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Default-COD-Compliance-Policy.json` |
| Assignment target | **Device groups** of corporate iOS/iPadOS devices (e.g. a dynamic group on the ADE enrollment profile), or user groups with an assignment **filter** on `deviceOwnership -eq "Corporate"` |
| Noncompliance actions | **Mark device noncompliant** after 0.25 days. **Send push notification** immediately and after 2 days. **Send email** immediately and after 2 days. |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint, where `iosCompliancePolicy` (including `restrictedApps`) is documented.

## Configuration description

Every setting not listed is **Not configured**. That includes maximum OS version, OS build versions, password expiration, managed email profile, and *Microsoft Defender for Endpoint* / device threat level.

### Device Health

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Jailbroken devices | Block | `securityBlockJailbrokenDevices: true` | Jailbroken devices are noncompliant |

### Device Properties

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum OS version | `18.0` | `osMinimumVersion` | Devices below **iOS/iPadOS 18** are noncompliant. The user sees a link with upgrade information. |

### System Security – Device Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Restricted apps | **TikTok** (`com.zhiliaoapp.musically`), **TikTok Lite** (`com.ss.iphone.ugc.tiktok.lite`) | `restrictedApps` (`appListItem`: `name`, `appId`) | If an app with one of these bundle IDs is installed, the device is noncompliant. Applies to **unmanaged** apps installed outside management. |

> [!TIP]
> On **corporate** iOS devices Intune inventories **all installed apps** (except system apps), so *Restricted apps* has full visibility. On supervised (ADE) devices you can also **prevent** these apps from running with a **Settings catalog > Restrictions > Blocked App Bundle IDs** policy. Compliance only *detects* them.

### System Security – Password

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require a password to unlock mobile devices | Require | `passcodeRequired: true` | A device passcode is set |
| Simple passwords | Block | `passcodeBlockSimple: true` | Blocks simple passcodes such as `1234` or `1111` |
| Minimum password length | 6 | `passcodeMinimumLength: 6` | At least 6 characters |
| Required password type | At least numeric | `passcodeRequiredType: "numeric"` | A numeric passcode is the minimum. Alphanumeric also passes. |
| Maximum minutes after screen lock before password is required | **Immediately** | `passcodeMinutesOfInactivityBeforeLock: 0` | The passcode is required as soon as the screen locks |
| Maximum minutes of inactivity until screen locks | 5 minutes | `passcodeMinutesOfInactivityBeforeScreenTimeout: 5` | The screen auto-locks after 5 minutes idle |
| Number of previous passwords to prevent reuse | 5 | `passcodePreviousPasscodeBlockCount: 5` | The last 5 passcodes can't be reused (supported on iOS 17.0 and later) |

### Actions for noncompliance

| # | Action | Schedule | Message template | Additional recipients | Graph |
|---|---|---|---|---|---|
| 1 | Mark device noncompliant | **0.25 days** (6 hours) | – | None selected | `actionType: "block"`, `gracePeriodHours: 6` |
| 2 | Send push notification to end user | **Immediately** | – (Intune-generated) | None selected | `actionType: "pushNotification"`, `gracePeriodHours: 0` |
| 3 | Send push notification to end user | **2 days** | – (Intune-generated) | None selected | `actionType: "pushNotification"`, `gracePeriodHours: 48` |
| 4 | Send email to end user | **Immediately** | Selected (your template) | None selected | `actionType: "notification"`, `gracePeriodHours: 0` |
| 5 | Send email to end user | **2 days** | Selected (your template) | None selected | `actionType: "notification"`, `gracePeriodHours: 48` |

> [!NOTE]
> - **Push notifications** are generated by Intune, can't be customized, and are delivered through Company Portal. Microsoft **doesn't guarantee delivery**, which is why email is configured too.
> - **Email** actions reference a notification message template by ID. The JSON contains the placeholder `<notification-template-id>`. Replace it (the import script does this), or pick the template in the admin center.
> - **Userless** (shared or kiosk) iPads have no user to notify. Only the block action affects them.

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** (per user, or Intune Device license for userless devices). **Microsoft Entra ID P1** for Conditional Access. |
| Apple MDM | **Apple MDM push certificate** configured and valid |
| Enrollment | Corporate devices enrolled with **Automated Device Enrollment** (Apple Business Manager, supervised), or as corporate-owned devices. Users need **Company Portal** for compliance status and push notifications. |
| OS updates | A **software update** policy (DDM) to keep devices on iOS/iPadOS 18+ |
| Notification template | At least one template under **Devices > Manage devices > Compliance > Notifications** |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All` and `DeviceManagementServiceConfig.Read.All` (templates). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **iOS/iPadOS**, then select **Create**.
4. **Basics**: set **Name** to `iOS - Compliance Policy - Default - COD`, then select **Next**.
5. **Compliance settings**:
   1. **Device Health**: Jailbroken devices = **Block**.
   2. **Device Properties**: Minimum OS version = `18.0`.
   3. **System Security > Password**:
      - Require a password to unlock mobile devices = **Require**
      - Simple passwords = **Block**
      - Minimum password length = **6**
      - Required password type = **At least numeric**
      - Maximum minutes after screen lock before password is required = **Immediately**
      - Maximum minutes of inactivity until screen locks = **5 minutes**
      - Number of previous passwords to prevent reuse = **5**
   4. **System Security > Device Security > Restricted apps**: add these two entries.
      - App name `TikTok`, App bundle ID `com.zhiliaoapp.musically`
      - App name `TikTok Lite`, App bundle ID `com.ss.iphone.ugc.tiktok.lite`
   5. Leave everything else **Not configured**, then select **Next**.
6. **Actions for noncompliance**:
   1. On **Mark device noncompliant**, set **Schedule** = **0.25**.
   2. **Add** > **Send push notification to end user**, with Schedule **0**.
   3. **Add** > **Send push notification to end user**, with Schedule **2**.
   4. **Add** > **Send email to end user**. Set Schedule **0**, **Message template** = your template, no additional recipients.
   5. **Add** > **Send email to end user**. Set Schedule **2**, **Message template** = your template, no additional recipients.
   6. Select **Next**.
7. **Scope tags**: select your iOS RBAC tag (or keep **Default**), then select **Next**.
8. **Assignments**: **Add groups** and select the corporate iOS device group (pilot first). Select **Next**.
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
$body = (Get-Content ".\Default-COD-Compliance-Policy.json" -Raw) -replace '<notification-template-id>', $templateId

# 4. Create the policy (beta endpoint)
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body $body -ContentType "application/json"

# 5. Assign it to the corporate iOS device group (replace with your group's object ID)
$groupId = "<corporate-ios-device-group-id>"
$assign  = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $groupId } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"

# 6. Confirm settings, restricted apps, actions and assignment
Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=assignments,scheduledActionsForRule(`$expand=scheduledActionConfigurations)"
```

> [!NOTE]
> - The `notificationMessageTemplates` lookup in step 2 wasn't re-verified on Microsoft Learn for this file. If it fails, remove the two `notification` (email) actions from the JSON, create the policy, then add the emails in the admin center.
> - "Immediately" is stored as `0` minutes. Confirm in the admin center after import that the setting shows **Immediately**.

## Tenant-wide compliance settings to review

Go to **Devices > Manage devices > Compliance > Compliance settings**:

| Setting | Recommended | Why |
|---|---|---|
| Mark devices with no compliance policy assigned as | **Not compliant** | Stops unassessed devices from passing Conditional Access |
| Compliance status validity period (days) | **30** (default) | A device that hasn't reported within this period becomes noncompliant |

## Conditional Access integration

1. Go to **Microsoft Entra admin center > Entra ID > Conditional Access > Policies > New policy**.
2. Set **Users** to all users (or corporate iOS users), and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
4. Under **Conditions > Device platforms**, include **iOS**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first, then switch it **On** once devices show **Compliant**.

> [!WARNING]
> Make sure BYOD and COD policies don't both target the same device (e.g. one by user group, one by device group). A device must pass **every** assigned policy, so it would get the stricter combination. Use ownership filters to keep them separate.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status counts: *Compliant*, *In grace period*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | Per-setting pass/fail, especially *Restricted apps*, *Minimum OS version* and the password settings |
| **Devices > iOS/iPadOS > (device) > Device compliance > (policy)** | Per-setting result for one device |
| **Apps > Monitor > Discovered apps** | Corporate devices with TikTok / TikTok Lite installed |
| On the device | **Company Portal > Devices > (this device) > Check Settings**. **Settings > Face ID & Passcode > Require Passcode** = *Immediately*, and **Auto-Lock** ≤ 5 minutes. |
| Notifications | A push notification through Company Portal and the template email on day 0 and day 2 |

**Timing:** devices evaluate at check-in. To force an evaluation, use **Company Portal > Check Settings**, or select **Sync** for the device in the admin center.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or isn't in the assigned group | Sync the device. Check group membership and ownership filters. |
| **In grace period** | A setting failed less than 6 hours ago | Expected. Fix the setting before the 6 hours end. The user has already been notified. |
| *Restricted apps* noncompliant | TikTok or TikTok Lite installed | Uninstall the app. On supervised devices, block it with a Settings catalog policy. |
| *Maximum minutes after screen lock* noncompliant | **Require Passcode** set to anything other than *Immediately* | Settings > Face ID & Passcode > Require Passcode = **Immediately**. Enforce it with a device restrictions policy. |
| *Jailbroken devices* noncompliant | Jailbreak detected | Wipe the device and re-enroll through ADE |
| *Minimum OS version* noncompliant | Device on iOS 17 or older (stale OS) | Push the update with a software update policy. Replace hardware that can't run iOS 18. |
| *Password* noncompliant | Passcode shorter than 6, simple, reused, or auto-lock over 5 minutes | Set a compliant passcode. Enforce it with a passcode configuration policy. |
| No push notification | Delivery isn't guaranteed, or notifications are off for Company Portal | Rely on the email action |
| Device Health attestation "needs restart" | Not applicable. That's a Windows behaviour. | – |
| Noncompliant and user can't fix it | User or device not licensed for Intune | Assign an Intune user or device license |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Relax specific settings:** set *Maximum minutes after screen lock* back to a few minutes, remove a restricted app, or lengthen the grace period, without removing the policy.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: corporate iOS devices are then governed only by other iOS policies that target them. If none remain, *Mark devices with no compliance policy assigned as* decides, and if that is **Not compliant**, CA-protected access is blocked. Nothing changes on the device itself.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for iOS/iPadOS in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-ios-ipados-settings)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [Intune discovered apps](https://learn.microsoft.com/intune/app-management/discovered-apps)
- [iosCompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-ioscompliancepolicy?view=graph-rest-beta)
- [Bundle IDs for built-in iOS/iPadOS apps](https://learn.microsoft.com/intune/device-configuration/templates/ref-bundle-ids-ios)
