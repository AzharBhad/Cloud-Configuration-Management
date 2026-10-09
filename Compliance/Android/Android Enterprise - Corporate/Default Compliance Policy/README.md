# Android - Compliance Policy - Default - COD

Default Intune compliance policy for **corporate-owned Android devices (COD)**: fully managed, dedicated, and corporate-owned with a work profile. It covers:

- **Device integrity:** blocks rooted devices, and requires Play Integrity basic + device integrity plus **strong (hardware-backed) integrity**
- **OS and storage:** Android **14.0** or later, with encryption
- **Intune app:** requires Intune app runtime integrity
- **Password:** numeric complex, minimum 6, the last 5 passwords can't be reused, lock after 5 minutes

Devices are marked noncompliant after **0.25 days (6 hours)**. Users get push notifications and emails **immediately** and again after **2 days**.

## Purpose

- **Risk addressed:** corporate phones and tablets carry full corporate access, often for frontline or field staff. This policy blocks access from devices that:
  - are rooted, or fail Play Integrity / strong integrity
  - run an outdated Android release
  - are unencrypted
  - have a tampered Intune app
  - have a weak or reused PIN
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a corporate device that fails any check loses access to Microsoft 365 and other Entra-protected apps once the 6-hour grace period ends.
- **User experience:** two channels (a push notification through the Intune app, and email) tell the user straight away what to fix. A reminder follows on day 2 if the device is still noncompliant.
- **Difference from BYOD:** corporate devices are fully managed, so this policy checks the **whole device password** (with reuse history) and the **Intune app**. The [BYOD policy](../../Android%20Enterprise%20-%20Personally%20Owned/Default%20Compliance%20Policy/README.md) checks Company Portal, Play Services, unknown sources and USB debugging instead.

## Policy summary

| Item | Value |
|---|---|
| Display name | `Android - Compliance Policy - Default - COD` |
| Description | *(not shown in the source screenshot; left empty)* |
| Platform | Android Enterprise |
| Profile type | Fully managed, dedicated, and corporate-owned work profile |
| Graph `@odata.type` | `#microsoft.graph.androidDeviceOwnerCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Default-Compliance-Policy.json` |
| Scope tags | Not visible in the source screenshot. Use your Android RBAC tag, or **Default**. |
| Assignment target | Not visible in the source screenshot. Recommended: **device groups** of corporate Android devices (e.g. a dynamic group on enrollment profile). Use **device** groups for dedicated (userless) devices. |
| Noncompliance actions | **Mark device noncompliant** after 0.25 days. **Send push notification** immediately and after 2 days. **Send email** immediately and after 2 days. |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint, because `androidDeviceOwnerCompliancePolicy` is documented in the beta schema. Graph still names the Play Integrity checks `SafetyNet` (`securityRequireSafetyNetAttestation*`, `securityRequiredAndroidSafetyNetEvaluationType`) for backward compatibility.

## Configuration description

Every setting not listed is **Not configured**. That includes *Minimum security patch level*, maximum OS version, *Require no pending system updates*, password expiration, and *Microsoft Defender for Endpoint* / device threat level.

### Device Health

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Rooted devices | Block | `securityBlockJailbrokenDevices: true` | Rooted devices are noncompliant. Root access bypasses Android Enterprise management controls. |
| Play Integrity Verdict | Check basic integrity and device integrity | `securityRequireSafetyNetAttestationBasicIntegrity: true`, `securityRequireSafetyNetAttestationCertifiedDevice: true` | The device passes Google Play Integrity basic integrity and device integrity (a genuine, Google-certified device) |
| Check strong integrity using hardware-backed security features | Check strong integrity | `securityRequiredAndroidSafetyNetEvaluationType: "hardwareBacked"` | Integrity is attested with hardware-backed keys (a locked bootloader on certified hardware), which is the strongest anti-tamper signal |

> [!WARNING]
> **Strong integrity** fails on devices without hardware-backed key attestation, including some rugged or older models used by frontline staff, even when they aren't tampered with. Test every corporate model before broad assignment.

### Device Properties

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum OS version | `14.0` | `osMinimumVersion` | Devices below **Android 14** are noncompliant |

### System Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require encryption of data storage on device | Require | `storageRequireEncryption: true` | Device storage is encrypted |
| Intune app runtime integrity | Require | `securityRequireIntuneAppIntegrity: true` | The **Intune app** on the device is the genuine Microsoft app from Managed Google Play. Corporate Android Enterprise devices use the Intune app, not Company Portal, for user-facing compliance. |

### Device Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require a password to unlock mobile devices | Require | `passwordRequired: true` | A device screen lock is set |
| Required password type | Numeric complex | `passwordRequiredType: "numericComplex"` | Numeric PIN without repeating (1111) or consecutive (1234) digits |
| Number of passwords required before user can reuse a password | 5 | `passwordPreviousPasswordCountToBlock: 5` | The last 5 passwords can't be reused |
| Minimum password length | 6 | `passwordMinimumLength: 6` | At least 6 digits |
| Maximum minutes of inactivity before password is required | 5 minutes | `passwordMinutesOfInactivityBeforeLock: 5` | The screen locks after 5 minutes idle |

> [!TIP]
> On **corporate** Android Enterprise devices, *Required password type* and *Minimum password length* still apply on Android 12+. The Android 12 deprecation of these settings affects only **personally owned work profile** devices.

### Actions for noncompliance

| # | Action | Schedule | Message template | Additional recipients | Graph |
|---|---|---|---|---|---|
| 1 | Mark device noncompliant | **0.25 days** (6 hours) | – | None selected | `actionType: "block"`, `gracePeriodHours: 6` |
| 2 | Send push notification to end user | **Immediately** | – (Intune-generated) | None selected | `actionType: "pushNotification"`, `gracePeriodHours: 0` |
| 3 | Send push notification to end user | **2 days** | – (Intune-generated) | None selected | `actionType: "pushNotification"`, `gracePeriodHours: 48` |
| 4 | Send email to end user | **Immediately** | Selected (your template) | None selected | `actionType: "notification"`, `gracePeriodHours: 0` |
| 5 | Send email to end user | **2 days** | Selected (your template) | None selected | `actionType: "notification"`, `gracePeriodHours: 48` |

> [!NOTE]
> - **Push notifications** are generated by Intune, can't be customized, and are delivered through the Intune app. Microsoft **doesn't guarantee delivery**, so don't rely on them alone. That's why email is also configured.
> - **Email** actions reference a notification message template by ID. The JSON contains the placeholder `<notification-template-id>`. Replace it (the import script does this), or pick the template in the admin center. The template name wasn't visible in the screenshot.
> - **Dedicated (userless) devices** have no user to email or notify, so these actions have no effect on them.

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** (per user, or Intune Device license for userless dedicated devices). **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | **Android Enterprise** fully managed, dedicated or corporate-owned work profile enrollment (QR code, NFC, zero-touch or token). Intune must be connected to **Managed Google Play**. |
| Intune app | The **Microsoft Intune** app from Managed Google Play. It's installed automatically during corporate enrollment and is required for the runtime integrity check and push notifications. |
| Google services | GMS devices. Devices without GMS can't pass Play Integrity (use Android AOSP management for those). |
| Device administrator | **Not used.** Android device administrator is deprecated and unavailable on GMS devices. |
| Device password | Enforce the same password rules with a **device restrictions** policy for corporate devices, so users are prompted to set a compliant PIN |
| Notification template | At least one template under **Devices > Manage devices > Compliance > Notifications** |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All` and `DeviceManagementServiceConfig.Read.All` (templates). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Android Enterprise**. **Profile type**: select **Fully managed, dedicated, and corporate-owned work profile**. Select **Create**.
4. **Basics**: set **Name** to `Android - Compliance Policy - Default - COD`, then select **Next**.
5. **Compliance settings**:
   1. **Device Health**:
      - Rooted devices = **Block**
      - Play Integrity Verdict = **Check basic integrity & device integrity**
      - Check strong integrity using hardware-backed security features = **Check strong integrity**
   2. **Device Properties**: Minimum OS version = `14.0`.
   3. **System Security**:
      - Require encryption of data storage on device = **Require**
      - Intune app runtime integrity = **Require**
   4. **Device Security**:
      - Require a password to unlock mobile devices = **Require**
      - Required password type = **Numeric complex**
      - Number of passwords required before user can reuse a password = **5**
      - Minimum password length = **6**
      - Maximum minutes of inactivity before password is required = **5 minutes**
   5. Leave everything else **Not configured**, then select **Next**.
6. **Actions for noncompliance**:
   1. On **Mark device noncompliant**, set **Schedule** = **0.25**.
   2. **Add** > **Send push notification to end user**, with Schedule **0**.
   3. **Add** > **Send push notification to end user**, with Schedule **2**.
   4. **Add** > **Send email to end user**. Set Schedule **0**, **Message template** = your template, no additional recipients.
   5. **Add** > **Send email to end user**. Set Schedule **2**, **Message template** = your template, no additional recipients.
   6. Select **Next**.
7. **Scope tags**: select your Android RBAC tag (or keep **Default**), then select **Next**.
8. **Assignments**: **Add groups** and select the corporate Android device group (pilot first). Select **Next**.
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
$body = (Get-Content ".\Default-Compliance-Policy.json" -Raw) -replace '<notification-template-id>', $templateId

# 4. Create the policy (beta endpoint)
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body $body -ContentType "application/json"

# 5. Assign it to the corporate Android device group (replace with your group's object ID)
$groupId = "<corporate-android-device-group-id>"
$assign  = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $groupId } }
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
> The `notificationMessageTemplates` lookup in step 2 wasn't re-verified on Microsoft Learn for this file. If it fails, remove the two `notification` (email) actions from the JSON, create the policy, then add the emails in the admin center.

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
6. Set **Enable policy** to **Report-only** first, then switch it **On** once devices show **Compliant**.

> [!TIP]
> Dedicated (kiosk / shared) devices that sign in with shared-device mode or no user still need a compliance state for CA. Assign this policy to the **device** group so they're evaluated.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status counts: *Compliant*, *In grace period*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | Per-setting pass/fail, especially *Play Integrity*, *strong integrity* and *password* settings |
| **Devices > Android > (device) > Device compliance > (policy)** | Per-setting result for one device |
| On the device | **Microsoft Intune app > Devices > (this device) > Check compliance** lists each failing setting. **Settings > About phone** must show Android 14+. **Settings > Security** shows screen lock and encryption. |
| Notifications | A push notification arrives in the Intune app and the template email is sent on day 0 and day 2 |

**Timing:** devices evaluate at check-in. To force an evaluation, use **Intune app > Check compliance**, or select **Sync** for the device in the admin center.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or isn't in the assigned group | Use **Intune app > Check compliance**. Check group membership (device vs. user group). |
| **In grace period** | A setting failed less than 6 hours ago | Expected. Fix the setting before the 6 hours end. The user has already been notified. |
| *Strong integrity* noncompliant on a genuine device | No hardware-backed key attestation on that model, or an unlocked bootloader | Confirm with the vendor. Replace the model, or relax to basic + device integrity for a model-specific group. |
| *Play Integrity* noncompliant | Rooted device, custom ROM, unlocked bootloader, or outdated Play Services | Factory-reset to stock firmware and re-enroll |
| *Intune app runtime integrity* noncompliant | Intune app not from Managed Google Play, or modified | Reinstall the Intune app from Managed Google Play (or re-enroll) |
| *Minimum OS version* noncompliant | Device on Android 13 or older (stale OS) | Update Android with a **system update** policy. Replace devices the vendor no longer updates. |
| *Password* noncompliant | PIN too short, simple (1234), or reused | Set a 6+ digit PIN without sequences that differs from the last 5 |
| No push notification | Delivery isn't guaranteed, or notifications are off for the Intune app | Rely on the email action. Check notification settings for the Intune app. |
| Device Health attestation "needs restart" | Not applicable. That's a Windows behaviour. | – |
| Noncompliant and user can't fix it | User not licensed for Intune, or a userless dedicated device without an Intune Device license | Assign a user or device license |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Relax the riskiest setting first:** if many genuine devices fail, set *Check strong integrity* back to **Not configured**, or lengthen the grace period from 0.25 days.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: corporate Android devices are then governed only by other Android Enterprise corporate policies. If none remain, *Mark devices with no compliance policy assigned as* decides, and if that is **Not compliant**, CA-protected access is blocked. Nothing changes on the device itself.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Android Enterprise in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-android-enterprise-settings)
- [Configure actions for noncompliant devices (push notification, email)](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [androidDeviceOwnerCompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-androiddeviceownercompliancepolicy?view=graph-rest-beta)
- [deviceComplianceActionItem resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-devicecomplianceactionitem?view=graph-rest-beta)
- [Monitor results of your compliance policies](https://learn.microsoft.com/intune/device-security/compliance/monitor-policy)
