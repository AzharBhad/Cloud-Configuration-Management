# AND-CORP-COMP-Security Patch Level

Intune compliance policy for **corporate-owned Android devices (COD)**: fully managed, dedicated, and corporate-owned work profile. It requires:

- Android **security patch level 2025-01-05** or later
- A device password of type **Numeric** or stronger (shown as "At least numeric" in the BYOD profile)

Devices are marked noncompliant after **0.25 days (6 hours)**. Users are emailed **immediately** and again after **2 days**.

## Purpose

- **Risk addressed:**
  - Corporate Android devices that don't install monthly security updates stay exposed to publicly disclosed vulnerabilities.
  - A device without a screen lock exposes everything on it if lost.
- **Why a separate policy:** keeping the patch level in its own policy lets you raise the date regularly without editing the [COD default policy](../Default%20Compliance%20Policy/README.md). A device is compliant only if **every** assigned policy passes.
- **Corporate advantage:** on fully managed devices you can push OS and security updates with a **system update** policy. Unlike BYOD, IT can drive devices to the required patch level instead of relying on users.
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a corporate device below the patch level, or without a numeric password, loses access to Microsoft 365 and other Entra-protected apps once the 6-hour grace period ends.

## Policy summary

| Item | Value |
|---|---|
| Display name | `AND-CORP-COMP-Security Patch Level` (naming standard, as no name was given) |
| Platform | Android Enterprise |
| Profile type | Fully managed, dedicated, and corporate-owned work profile |
| Graph `@odata.type` | `#microsoft.graph.androidDeviceOwnerCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Security-Patch-Level.json` |
| Assignment target | **Device groups** of corporate Android devices (same scope as the COD default policy) |
| Noncompliance actions | **Mark device noncompliant** after **0.25 days** (6 h). **Send email to end user** **immediately**. **Send email to end user** after **2 days**. |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint, where `androidDeviceOwnerCompliancePolicy` is documented.

## Configuration description

Every setting not listed is **Not configured**.

### Device Properties

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum security patch level | `2025-01-05` | `minAndroidSecurityPatchLevel` | The oldest Android security patch level a device can have. Older devices are noncompliant. The date must be in **YYYY-MM-DD** format. |

> [!NOTE]
> You listed this under *Device Security*. For the **corporate** profile type, the admin center places *Minimum security patch level* under **Device Properties** (next to Minimum/Maximum OS version). For the personally owned profile it's under *Device Security*.

> [!WARNING]
> **The date is old.** `2025-01-05` is roughly 21 months behind today (October 2026), so it only blocks severely outdated devices. For corporate devices, which IT can update, a rolling target of **no older than 3 months** is realistic. Raise the date once your **system update** policy has rolled the patch out.

### System Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require a password to unlock mobile devices | Require | `passwordRequired: true` | A device screen lock is set. Needed so the password type below is evaluated. |
| Required password type | **Numeric** (BYOD label: *At least numeric*) | `passwordRequiredType: "numeric"` | The password must be at least a numeric PIN (e.g. `123456`). Stronger types such as alphanumeric also pass. |

> [!TIP]
> - **Numeric** allows simple PINs like `1111` or `1234`. If this policy is assigned together with the COD default policy (*Numeric complex*, minimum 6), the stricter default policy still applies, because a device must pass both.
> - On its own, consider adding **Minimum password length** (e.g. 6) or using **Numeric complex**.

### Actions for noncompliance

| Action | Schedule | Message template | Additional recipients | Graph |
|---|---|---|---|---|
| Mark device noncompliant | **0.25 days** (6 hours) | – | None selected | `actionType: "block"`, `gracePeriodHours: 6` |
| Send email to end user | **Immediately** | Your template | None selected | `actionType: "notification"`, `gracePeriodHours: 0` |
| Send email to end user | **2 days** | Your template | None selected | `actionType: "notification"`, `gracePeriodHours: 48` |

> [!NOTE]
> - **Email template:** the email actions reference a **notification message template** by ID. The JSON contains the placeholder `<notification-template-id>`. Replace it (the import script does this), or pick the template in the admin center. Templates are under **Devices > Manage devices > Compliance > Notifications**.
> - **Dedicated (userless) devices** have no user to email, so the email actions have no effect on them.

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** (per user, or Intune Device license for userless dedicated devices). **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | **Android Enterprise** fully managed, dedicated or corporate-owned work profile enrollment. Intune must be connected to **Managed Google Play**. |
| System updates | A **system update** policy (**Devices > Android > Configuration > Device restrictions > General > System update**: *Automatic* or a maintenance window) so devices reach the required patch level. The OEM or carrier must have released that patch for each model. |
| Device password | Optionally enforce the password with a **device restrictions** policy, so users are prompted to set a PIN |
| Device administrator | **Not used.** Android device administrator is deprecated and unavailable on GMS devices. |
| Notification template | At least one template under **Devices > Manage devices > Compliance > Notifications** |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All` and `DeviceManagementServiceConfig.Read.All` (templates). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Android Enterprise**. **Profile type**: select **Fully managed, dedicated, and corporate-owned work profile**. Select **Create**.
4. **Basics**: set **Name** to `AND-CORP-COMP-Security Patch Level`, and paste the description from the JSON. Select **Next**.
5. **Compliance settings**:
   1. **Device Properties**: Minimum security patch level = `2025-01-05`.
   2. **System Security**: Require a password to unlock mobile devices = **Require**, Required password type = **Numeric**.
   3. Leave everything else **Not configured**, then select **Next**.
6. **Actions for noncompliance**:
   1. On **Mark device noncompliant**, set **Schedule** = **0.25**.
   2. **Add** > **Send email to end user**. Set Schedule **0**, **Message template** = your template, no additional recipients.
   3. **Add** > **Send email to end user**. Set Schedule **2**, **Message template** = your template, no additional recipients.
   4. Select **Next**.
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
$body = (Get-Content ".\Security-Patch-Level.json" -Raw) -replace '<notification-template-id>', $templateId

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

# 6. Later: raise the patch level without recreating the policy
Invoke-MgGraphRequest -Method PATCH `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)" `
  -Body (@{ "@odata.type" = "#microsoft.graph.androidDeviceOwnerCompliancePolicy"; minAndroidSecurityPatchLevel = "2026-07-01" } | ConvertTo-Json) `
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
2. Set **Users** to all users (or corporate Android users), and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
4. Under **Conditions > Device platforms**, include **Android**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first. Check how many devices fail the patch level before switching it **On**.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status counts: *Compliant*, *In grace period*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | *Minimum security patch level* and *Required password type* pass/fail |
| **Devices > Android > (device) > Hardware** | The device's reported **security patch level** |
| On the device | **Settings > About phone > Android version > Android security update** shows the patch date. **Microsoft Intune app > Check compliance** shows the failing setting. |
| Mail | The user receives the template email on day 0 and day 2 |

**Timing:** devices evaluate at check-in. After updating, open the **Intune app > Check compliance**, or select **Sync** in the admin center.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or isn't in the assigned device group | Sync the device. Check group membership. |
| **In grace period** | A setting failed less than 6 hours ago | Expected. Update or set a PIN before the 6 hours end. |
| Patch level noncompliant, no update offered | OEM/carrier hasn't released the patch for that model, or the model is out of support | Confirm with the OEM. Replace end-of-support devices. |
| Updated but still noncompliant | Device hasn't checked in since updating (stale OS / patch level reported) | Restart, then Intune app > **Check compliance** |
| Many devices fail at once | Patch date newer than your system update policy has delivered | Move the date back, let the update policy catch up, then raise it |
| *Required password type* noncompliant | No screen lock set (or a pattern / swipe) | Set a numeric PIN or stronger |
| Device Health attestation "needs restart" | Not applicable. That's a Windows behaviour. | – |
| No emails | Dedicated (userless) device, template missing, or no mailbox | Expected for userless devices. Otherwise check the template and mailbox. |
| Noncompliant and user can't fix it | User or device not licensed for Intune | Assign an Intune user or device license |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Relax the date:** move `minAndroidSecurityPatchLevel` to an older date (PATCH call above or admin center).
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: corporate devices are then governed only by the other assigned Android Enterprise corporate policies (e.g. the COD default policy). Nothing changes on the device itself.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Android Enterprise in Intune (fully managed, dedicated, corporate-owned work profile)](https://learn.microsoft.com/intune/device-security/compliance/ref-android-enterprise-settings#fully-managed,-dedicated,-and-corporate-owned-work-profile)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [androidDeviceOwnerCompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-androiddeviceownercompliancepolicy?view=graph-rest-beta)
