# Android - Compliance Policy - Default - BYOD

Default Intune compliance policy for **personally owned Android devices with a work profile** (Android Enterprise BYOD). It covers:

- **Device integrity:**
  - Blocks rooted devices
  - Requires Google Play Services and an up-to-date security provider
  - Requires Play Integrity basic + device integrity, plus **strong (hardware-backed) integrity**
- **OS and storage:** Android **14.0** or later, with encryption.
- **Device security:**
  - Blocks apps from unknown sources and USB debugging
  - Requires Company Portal app runtime integrity
  - Requires a device password: complexity **Medium**, numeric complex, minimum 6, lock after 5 minutes

Devices are marked noncompliant after **0.25 days (6 hours)**.

## Purpose

- **Risk addressed:** personal phones hold corporate email, Teams and files in the work profile. This policy blocks access from devices that:
  - are rooted or tampered with (fail Play Integrity / strong integrity)
  - run an outdated Android release
  - are unencrypted, or have no or a weak screen lock
  - allow sideloaded apps or USB debugging
  - run a modified Company Portal app
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a BYOD device that fails any check loses access to Microsoft 365 and other Entra-protected apps once the 6-hour grace period ends.
- **Privacy:** compliance on a personally owned work profile device reads only security state (integrity, OS version, encryption, password presence). It doesn't read personal apps or data.

## Policy summary

| Item | Value |
|---|---|
| Display name | `Android - Compliance Policy - Default - BYOD` |
| Description | *(not shown in the source screenshot; left empty)* |
| Platform | Android Enterprise |
| Profile type | Personally-owned work profile |
| Graph `@odata.type` | `#microsoft.graph.androidWorkProfileCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Default-Compliance-Policy.json` |
| Scope tags | Not visible in the source screenshot. Use your Android RBAC tag, or **Default**. |
| Assignment target | Not visible in the source screenshot. Recommended: **user groups** of BYOD users. Personally owned work profile devices are best targeted by user. |
| Noncompliance actions | **Mark device noncompliant** after **0.25 days** (6 hours). Rows below it were cut off in the screenshot. Add them if your tenant has more (e.g. *Send email*, *Send push notification*). |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint. Several properties in this policy exist only in the beta schema of `androidWorkProfileCompliancePolicy`:
> - `requiredPasswordComplexity`
> - `securityRequiredAndroidSafetyNetEvaluationType`
> - `securityRequireGooglePlayServices`
> - `securityRequireUpToDateSecurityProviders`
> - `securityRequireCompanyPortalAppIntegrity`
>
> Graph still names the Play Integrity checks `SafetyNet` for backward compatibility.

## Configuration description

Every setting not listed is **Not configured**. That includes *Minimum security patch level*, maximum OS version, *Work profile security* passwords, and *Microsoft Defender for Endpoint* / device threat level.

### Device Health

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Rooted devices | Block | `securityBlockJailbrokenDevices: true` | Rooted devices are noncompliant. Root access bypasses the work profile's isolation. |
| Google Play Services is configured | Require | `securityRequireGooglePlayServices: true` | Google Play Services is installed and enabled. Integrity and security-provider checks depend on it. |
| Up-to-date security provider | Require | `securityRequireUpToDateSecurityProviders: true` | The device's security provider (TLS / crypto libraries) is current, protecting against known vulnerabilities |
| Play Integrity Verdict | Check basic integrity and device integrity | `securityRequireSafetyNetAttestationBasicIntegrity: true`, `securityRequireSafetyNetAttestationCertifiedDevice: true` | The device passes Google Play Integrity basic integrity and device integrity (a genuine, Google-certified Android device) |
| Check strong integrity using hardware-backed security features | Check strong integrity | `securityRequiredAndroidSafetyNetEvaluationType: "hardwareBacked"` | Integrity is attested with hardware-backed keys (a locked bootloader on certified hardware), which is the strongest anti-tamper signal |

> [!WARNING]
> **Strong integrity** fails on devices without hardware-backed key attestation, and on some older or uncommon models even when they aren't tampered with. Pilot with a representative device set before broad assignment. If too many genuine devices fail, drop to *basic and device integrity* only.

### Device Properties

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum OS version | `14.0` | `osMinimumVersion` | Devices below **Android 14** are noncompliant. They miss current platform security features and patches. |

### System Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require encryption of data storage on device | Require | `storageRequireEncryption: true` | Device storage is encrypted |

### Device Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Block apps from unknown sources | Block | `securityPreventInstallAppsFromUnknownSources: true` | Installing apps from outside Google Play (sideloading) must be off |
| Company Portal app runtime integrity | Require | `securityRequireCompanyPortalAppIntegrity: true` | The Company Portal app is the genuine, unmodified version from Google Play |
| Block USB debugging on device | Block | `securityDisableUsbDebugging: true` | USB debugging (developer option) must be off |
| Require a password to unlock mobile devices | Require | `passwordRequired: true` | A device screen lock is set |
| Password complexity | **Medium** | `requiredPasswordComplexity: "medium"` | **Android 12+**: PIN without repeating (4444) or ordered (1234) sequences, at least 4 characters |
| Required password type | Numeric complex | `passwordRequiredType: "numericComplex"` | **Android 11 and earlier only**: numeric PIN without repeating or consecutive digits |
| Minimum password length | 6 | `passwordMinimumLength: 6` | **Android 11 and earlier only**: at least 6 characters |
| Maximum minutes of inactivity before password is required | 5 minutes | `passwordMinutesOfInactivityBeforeLock: 5` | The screen locks after 5 minutes idle |

> [!NOTE]
> **Password settings and Android versions.** Google deprecated *Required password type* and *Minimum password length* for personally owned work profile devices on **Android 12 and later**, and replaced them with **Password complexity**.
> - This policy requires **Android 14.0**, so every compliant device is evaluated on **Password complexity = Medium**.
> - The numeric complex / length 6 values are kept to match the source policy, but have no effect on in-scope devices.
> - If you want a 6-character minimum on Android 12+, you need **High** complexity: at least 8 for a PIN, or at least 6 for alphabetic/alphanumeric.

### Actions for noncompliance

| Action | Schedule | Message template | Additional recipients | Graph |
|---|---|---|---|---|
| Mark device noncompliant | **0.25 days** (6 hours) | – | None selected | `actionType: "block"`, `gracePeriodHours: 6` |

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** per user. **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | **Android Enterprise personally-owned work profile** enrollment. Intune must be connected to **Managed Google Play** (**Devices > Enrollment > Android > Managed Google Play**), and users enroll through the **Company Portal** app. |
| Google services | Devices need Google Play Services (GMS). Devices without GMS can't pass Play Integrity or the Play Services checks. |
| Device administrator | **Not used.** Android device administrator is deprecated and unavailable on GMS devices. This policy targets Android Enterprise only. |
| Device password | Optionally enforce the same password rules with a **device restrictions / Settings catalog** policy, so users are prompted rather than only marked noncompliant |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module, scope `DeviceManagementConfiguration.ReadWrite.All` |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Android Enterprise**. **Profile type**: select **Personally-owned work profile**. Select **Create**.
4. **Basics**: set **Name** to `Android - Compliance Policy - Default - BYOD`, then select **Next**.
5. **Compliance settings**:
   1. **Device Health**:
      - Rooted devices = **Block**
      - Google Play Services is configured = **Require**
      - Up-to-date security provider = **Require**
      - Play Integrity Verdict = **Check basic integrity & device integrity**
      - Check strong integrity using hardware-backed security features = **Check strong integrity**
   2. **Device Properties**: Minimum OS version = `14.0`.
   3. **System Security**: Require encryption of data storage on device = **Require**.
   4. **Device Security**:
      - Block apps from unknown sources = **Block**
      - Company Portal app runtime integrity = **Require**
      - Block USB debugging on device = **Block**
      - Require a password to unlock mobile devices = **Require**
      - *Android 12+*: Password complexity = **Medium**
      - *Android 11 and earlier*: Required password type = **Numeric complex**, Minimum password length = **6**
      - Maximum minutes of inactivity before password is required = **5 minutes**
   5. Leave everything else **Not configured**, then select **Next**.
6. **Actions for noncompliance**: on **Mark device noncompliant**, set **Schedule** = **0.25**. Add any further actions your tenant uses. Select **Next**.
7. **Scope tags**: select your Android RBAC tag (or keep **Default**), then select **Next**.
8. **Assignments**: **Add groups** and select the BYOD user group (pilot first). Select **Next**.
9. **Review + create**: confirm the summary matches the tables above, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
# 1. Connect with rights to create compliance policies
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

# 2. Create the policy from the JSON (beta endpoint - see the NOTE in "Policy summary")
$body   = Get-Content ".\Default-Compliance-Policy.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body $body -ContentType "application/json"
$policy.id

# 3. Assign it to the BYOD user group (replace with your group's object ID)
$groupId = "<byod-user-group-object-id>"
$assign  = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $groupId } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"

# 4. Confirm settings and assignment
Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=assignments"
```

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
   - For users who don't enroll, use **Require app protection policy** as an alternative grant (with *Require one of the selected controls*).
6. Set **Enable policy** to **Report-only** first, then switch it **On** once devices show **Compliant**.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status counts: *Compliant*, *In grace period*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | Per-setting pass/fail, especially *Play Integrity*, *strong integrity* and *Minimum OS version* |
| **Devices > Android > (device) > Device compliance > (policy)** | Per-setting result for one device |
| On the device | **Company Portal > Devices > (this device) > Check device settings** lists each failing setting with fix instructions. **Settings > About phone > Android version** must be 14+. **Settings > Security** shows screen lock and encryption. |

**Timing:** devices evaluate at check-in. To force an evaluation, use **Company Portal > Check device settings**, or select **Sync** for the device in the admin center.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or the user isn't in the assigned group | Open Company Portal > **Check device settings**. Check group membership. |
| **In grace period** | A setting failed less than 6 hours ago | Expected. Fix the setting before the 6 hours end. |
| *Strong integrity* noncompliant on a genuine device | No hardware-backed key attestation on that model, or an unlocked bootloader | Confirm with the device vendor. Replace the device, or relax to basic + device integrity for a model-specific group. |
| *Play Integrity* noncompliant | Rooted device, custom ROM, unlocked bootloader, or outdated Play Services | Restore the stock firmware and relock the bootloader. Update Google Play Services. |
| *Minimum OS version* noncompliant | Device on Android 13 or older (stale OS) | Update Android. If the vendor offers no update, the device can't be used for work. |
| *Password* noncompliant on Android 12+ | Screen lock below **Medium** complexity (e.g. pattern or a simple PIN like 1234) | Set a PIN without repeating or ordered digits, or a password |
| *Unknown sources* / *USB debugging* noncompliant | User enabled sideloading or developer options | Turn off **Install unknown apps** for all apps and **USB debugging** (Developer options) |
| *Company Portal app runtime integrity* noncompliant | Company Portal installed from outside Google Play, or modified | Reinstall Company Portal from Google Play |
| Device Health attestation "needs restart" | Not applicable. That's a Windows behaviour. | – |
| Noncompliant and user can't fix it | User not licensed for Intune | Assign an Intune license |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Relax the riskiest setting first:** if many genuine devices fail, set *Check strong integrity* back to **Not configured**, or lengthen the grace period from 0.25 days.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: BYOD devices are then governed only by other Android policies that target them. If none remain, *Mark devices with no compliance policy assigned as* decides, and if that is **Not compliant**, CA-protected access is blocked. Nothing changes on the device itself.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Android Enterprise in Intune (personally owned work profile)](https://learn.microsoft.com/intune/device-security/compliance/ref-android-enterprise-settings#personally-owned-work-profile)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [androidWorkProfileCompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-androidworkprofilecompliancepolicy?view=graph-rest-beta)
- [Monitor results of your compliance policies](https://learn.microsoft.com/intune/device-security/compliance/monitor-policy)
