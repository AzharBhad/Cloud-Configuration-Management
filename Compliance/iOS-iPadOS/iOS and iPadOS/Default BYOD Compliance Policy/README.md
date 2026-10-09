# iOS - Compliance Policy - Default - BYOD

Default Intune compliance policy for **personally owned (BYOD) iPhones and iPads**. It requires:

- No jailbreak
- iOS/iPadOS **18.0** or later
- **TikTok** and **TikTok Lite** not installed
- A passcode: simple passcodes blocked, minimum 6, numeric or stronger, the last 5 can't be reused, screen locks and passcode required after **5 minutes**

Devices are marked noncompliant after **0.25 days (6 hours)**. Users get push notifications and emails **immediately** and again after **2 days**.

## Purpose

- **Risk addressed:** personal iPhones and iPads access corporate email, Teams and files. This policy blocks access from devices that:
  - are jailbroken, which bypasses iOS sandboxing
  - run an outdated iOS release
  - have no or a weak passcode
  - have apps the organization has prohibited (TikTok, TikTok Lite) because of data-privacy concerns
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a BYOD device that fails any check loses access to Microsoft 365 and other Entra-protected apps once the 6-hour grace period ends.
- **User experience:** a push notification through Company Portal and an email tell the user straight away what to fix. A reminder follows on day 2.

## Policy summary

| Item | Value |
|---|---|
| Display name | `iOS - Compliance Policy - Default - BYOD` |
| Description | *(not shown in the source screenshot; left empty)* |
| Platform | iOS/iPadOS |
| Profile type | – (single profile for this platform) |
| Graph `@odata.type` | `#microsoft.graph.iosCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Default-BYOD-Compliance-Policy.json` |
| Assignment target | **User groups** of BYOD users. Exclude corporate (ADE) devices with a filter on ownership if they have their own policy. |
| Noncompliance actions | **Mark device noncompliant** after 0.25 days. **Send push notification** immediately and after 2 days. **Send email** immediately and after 2 days. |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint, where `iosCompliancePolicy` (including `restrictedApps`) is documented. It also keeps all mobile policies on the same API version.

## Configuration description

Every setting not listed is **Not configured**. That includes maximum OS version, OS build versions, password expiration, managed email profile, and *Microsoft Defender for Endpoint* / device threat level.

### Device Health

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Jailbroken devices | Block | `securityBlockJailbrokenDevices: true` | Jailbroken devices are noncompliant. Jailbreaking removes iOS sandboxing and code-signing protections. |

### Device Properties

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum OS version | `18.0` | `osMinimumVersion` | Devices below **iOS/iPadOS 18** are noncompliant. The user sees a link with upgrade information. |

### System Security – Device Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Restricted apps | **TikTok** (`com.zhiliaoapp.musically`), **TikTok Lite** (`com.ss.iphone.ugc.tiktok.lite`) | `restrictedApps` (`appListItem`: `name`, `appId`) | If an app with one of these bundle IDs is installed, the device is noncompliant. Applies to **unmanaged** apps installed outside management. |

> [!NOTE]
> **Restricted apps and privacy on BYOD.** On personally owned iOS devices Intune normally inventories only managed apps. When the *Restricted apps* setting is used, Intune **collects but doesn't store** the full app inventory so it can evaluate the list. Explain this in your BYOD privacy statement. Verify bundle IDs before adding them: a wrong ID simply never matches.

### System Security – Password

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require a password to unlock mobile devices | Require | `passcodeRequired: true` | A device passcode is set |
| Simple passwords | Block | `passcodeBlockSimple: true` | Blocks simple passcodes such as `1234` or `1111` |
| Minimum password length | 6 | `passcodeMinimumLength: 6` | At least 6 characters |
| Required password type | At least numeric | `passcodeRequiredType: "numeric"` | A numeric passcode is the minimum. Alphanumeric also passes. |
| Maximum minutes after screen lock before password is required | 5 minutes | `passcodeMinutesOfInactivityBeforeLock: 5` | The passcode is required once the screen has been locked for 5 minutes |
| Maximum minutes of inactivity until screen locks | 5 minutes | `passcodeMinutesOfInactivityBeforeScreenTimeout: 5` | The screen auto-locks after 5 minutes idle |
| Number of previous passwords to prevent reuse | 5 | `passcodePreviousPasscodeBlockCount: 5` | The last 5 passcodes can't be reused (supported on iOS 17.0 and later, so covered by the 18.0 minimum) |

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
> - **Email** actions reference a notification message template by ID. The JSON contains the placeholder `<notification-template-id>`. Replace it (the import script does this), or pick the template in the admin center. The template name wasn't visible in the screenshot.

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** per user. **Microsoft Entra ID P1** for Conditional Access. |
| Apple MDM | **Apple MDM push certificate** configured and valid (**Devices > Enrollment > Apple > MDM Push Certificate**) |
| Enrollment | Personal devices enrolled with **Company Portal** (device enrollment) or a supported BYOD enrollment method. Users need **Company Portal** for compliance status and push notifications. |
| Restricted apps | Correct bundle IDs. Intune evaluates unmanaged apps for this setting. Confirm your BYOD enrollment method supports it before relying on it. |
| Notification template | At least one template under **Devices > Manage devices > Compliance > Notifications** |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All` and `DeviceManagementServiceConfig.Read.All` (templates). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **iOS/iPadOS**, then select **Create**.
4. **Basics**: set **Name** to `iOS - Compliance Policy - Default - BYOD`, then select **Next**.
5. **Compliance settings**:
   1. **Device Health**: Jailbroken devices = **Block**.
   2. **Device Properties**: Minimum OS version = `18.0`.
   3. **System Security > Password**:
      - Require a password to unlock mobile devices = **Require**
      - Simple passwords = **Block**
      - Minimum password length = **6**
      - Required password type = **At least numeric**
      - Maximum minutes after screen lock before password is required = **5 minutes**
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
$body = (Get-Content ".\Default-BYOD-Compliance-Policy.json" -Raw) -replace '<notification-template-id>', $templateId

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

# 6. Confirm settings, restricted apps, actions and assignment
Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=assignments,scheduledActionsForRule(`$expand=scheduledActionConfigurations)"
```

> [!NOTE]
> The `notificationMessageTemplates` lookup in step 2 wasn't re-verified on Microsoft Learn for this file. If it fails, remove the two `notification` (email) actions from the JSON, create the policy, then add the emails in the admin center.

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
4. Under **Conditions > Device platforms**, include **iOS**.
5. Under **Grant**, select **Require device to be marked as compliant**.
   - For users who don't enroll, use **Require app protection policy** as an alternative grant (with *Require one of the selected controls*).
6. Set **Enable policy** to **Report-only** first, then switch it **On** once devices show **Compliant**.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status counts: *Compliant*, *In grace period*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | Per-setting pass/fail, especially *Restricted apps*, *Minimum OS version* and the password settings |
| **Devices > iOS/iPadOS > (device) > Device compliance > (policy)** | Per-setting result for one device |
| On the device | **Company Portal > Devices > (this device) > Check Settings** lists each failing setting. **Settings > General > About** shows the iOS version. **Settings > Face ID & Passcode** shows the passcode and auto-lock. |
| Notifications | A push notification through Company Portal and the template email on day 0 and day 2 |

**Timing:** devices evaluate at check-in. To force an evaluation, use **Company Portal > Check Settings**, or select **Sync** for the device in the admin center.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or the user isn't in the assigned group | Open Company Portal > **Check Settings**. Check group membership. |
| **In grace period** | A setting failed less than 6 hours ago | Expected. Fix the setting before the 6 hours end. The user has already been notified. |
| *Restricted apps* noncompliant | TikTok or TikTok Lite installed | Uninstall the app, then **Check Settings** |
| *Restricted apps* never triggers | Wrong bundle ID, or app inventory not yet collected | Verify the bundle ID. Wait for inventory, or sync the device. |
| *Jailbroken devices* noncompliant | Jailbreak detected | Restore iOS through Finder/iTunes and re-enroll |
| *Minimum OS version* noncompliant | Device on iOS 17 or older (stale OS) | Update to iOS/iPadOS 18+. Older hardware that can't run iOS 18 can't comply. |
| *Password* noncompliant | Passcode shorter than 6, simple (1234), reused, or auto-lock longer than 5 minutes | Set a compliant passcode, and set **Auto-Lock** to 5 minutes or less |
| No push notification | Delivery isn't guaranteed, or notifications are off for Company Portal | Rely on the email action. Enable notifications for Company Portal. |
| Device Health attestation "needs restart" | Not applicable. That's a Windows behaviour. | – |
| Noncompliant and user can't fix it | User not licensed for Intune | Assign an Intune license |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Relax specific settings:** remove a restricted app, or lengthen the grace period from 0.25 days, without removing the policy.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: BYOD iOS devices are then governed only by other iOS policies that target them. If none remain, *Mark devices with no compliance policy assigned as* decides, and if that is **Not compliant**, CA-protected access is blocked. Nothing changes on the device itself.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for iOS/iPadOS in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-ios-ipados-settings)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [Intune discovered apps (app inventory on personal devices)](https://learn.microsoft.com/intune/app-management/discovered-apps)
- [iosCompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-ioscompliancepolicy?view=graph-rest-beta)
- [Bundle IDs for built-in iOS/iPadOS apps](https://learn.microsoft.com/intune/device-configuration/templates/ref-bundle-ids-ios)
