# macOS - Compliance Policy - Default

Default Intune compliance policy for **macOS** devices. It requires:

- System Integrity Protection
- macOS **15.0 (Sequoia)** or later
- Encryption of data storage (FileVault)
- The firewall with **stealth mode** on
- Gatekeeper set to **Mac App Store and identified developers**

Devices are marked noncompliant after **0.25 days (6 hours)**. Users get an email **immediately** and again after **2 days**.

## Purpose

- **Risk addressed:**
  - Data on a lost or stolen Mac (no FileVault)
  - System files and kernel extensions tampered with (SIP off)
  - Network exposure (firewall off, Mac answering probes without stealth mode)
  - Unsigned or unknown apps running (Gatekeeper weakened)
  - Unpatched, older macOS releases
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a Mac that fails any check loses access to Microsoft 365 and other Entra-protected apps after the 6-hour grace period.
- **User experience:** the immediate email tells users what to fix while they're still in the grace period. The 2-day email reminds anyone still noncompliant, by which time access is already blocked.

## Policy summary

| Item | Value |
|---|---|
| Display name | `macOS - Compliance Policy - Default` |
| Description | *(empty, as in the source policy)* |
| Platform | macOS |
| Profile type | Mac compliance policy |
| Graph `@odata.type` | `#microsoft.graph.macOSCompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Default-Compliance-Policy.json` |
| Scope tags | **Mac Admin** |
| Assignment target | Not visible in the source screenshot. Recommended: **all corporate Macs** (a device group, or *All devices* with a macOS-only filter, or user groups of Mac users). |
| Noncompliance actions | **Mark device noncompliant** after **0.25 days** (6 h). **Send email to end user** **immediately**. **Send email to end user** after **2 days**. |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint. `gatekeeperAllowedAppSource` (*Allow apps downloaded from these locations*) and `roleScopeTagIds` exist only in the beta schema of `macOSCompliancePolicy`. The other settings are also in v1.0.

## Configuration description

Every setting not listed is **Not configured**. That includes all *Password* settings, maximum OS version, OS build versions and *Microsoft Defender for Endpoint* / device threat level.

### Device Health

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require system integrity protection | Require | `systemIntegrityProtectionEnabled` | System Integrity Protection (SIP) is on. SIP stops even root from modifying protected system files, folders and processes. |

### Device Properties

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Minimum OS version | `15.0` | `osMinimumVersion` | Blocks Macs older than **macOS 15 Sequoia**. Older releases miss current security fixes. |

### System Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require encryption of data storage on device | Require | `storageRequireEncryption` | The startup disk is encrypted with **FileVault** |
| Firewall | Enable | `firewallEnabled` | The macOS application firewall is on |
| Stealth Mode | Enable | `firewallEnableStealthMode` | The Mac doesn't respond to probing requests (e.g. ICMP ping). Requires the firewall to be on. |
| Allow apps downloaded from these locations (Gatekeeper) | Mac App Store and identified developers | `gatekeeperAllowedAppSource: "macAppStoreAndIdentifiedDevelopers"` | Only App Store apps and apps signed by identified (notarized) developers can run |

### Actions for noncompliance

| Action | Schedule | Message template | Additional recipients | Graph |
|---|---|---|---|---|
| Mark device noncompliant | **0.25 days** (6 hours) | – | None selected | `actionType: "block"`, `gracePeriodHours: 6` |
| Send email to end user | **Immediately** | Selected (your template) | None selected | `actionType: "notification"`, `gracePeriodHours: 0` |
| Send email to end user | **2 days** | Selected (your template) | None selected | `actionType: "notification"`, `gracePeriodHours: 48` |

> [!NOTE]
> The email actions reference a **notification message template** by ID. The JSON contains the placeholder `<notification-template-id>`. Replace it with your template's ID (the import script below does this), or pick the template in the admin center. The template name wasn't visible in the screenshot. Templates are under **Devices > Manage devices > Compliance > Notifications**.

### Scope tags

| Item | Value | Graph |
|---|---|---|
| Scope tags | Mac Admin | `roleScopeTagIds` (tag **ID**, resolved by the import script) |

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** (included in Microsoft 365 E3/E5, EMS). **Microsoft Entra ID P1** for Conditional Access. |
| Enrollment | Macs **enrolled in Intune**: Automated Device Enrollment (Apple Business Manager) for corporate Macs, or Company Portal enrollment. Users need the **Company Portal** app to see compliance status and register for CA. |
| FileVault | A FileVault policy that **turns encryption on** and escrows the recovery key: **Endpoint security > Disk encryption > Create policy > macOS > FileVault**. Compliance only **checks** encryption. |
| Firewall | Optionally enforce with **Endpoint security > Firewall > macOS firewall** so users can't turn it off |
| Gatekeeper | Optionally enforce with a **Settings catalog** policy (System Policy Control) so the compliance check matches the configured state |
| Notification template | At least one template under **Devices > Manage devices > Compliance > Notifications** |
| Scope tag | **Mac Admin** exists under **Tenant administration > Roles > Scope (tags)** |
| Roles | **Intune Administrator** or **Policy and Profile Manager** with the *Mac Admin* scope tag. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All`, `DeviceManagementServiceConfig.Read.All` (templates) and `DeviceManagementRBAC.Read.All` (scope tags). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **macOS**, then select **Create**.
4. **Basics**: set **Name** to `macOS - Compliance Policy - Default`. Leave **Description** empty or add one. Select **Next**.
5. **Compliance settings**:
   1. **Device Health**: Require system integrity protection = **Require**.
   2. **Device Properties**: Minimum OS version = `15.0`.
   3. **System Security**:
      - Require encryption of data storage on device = **Require**
      - Firewall = **Enable**
      - Stealth Mode = **Enable**
      - Allow apps downloaded from these locations = **Mac App Store and identified developers**
   4. Leave everything else **Not configured**, then select **Next**.
6. **Actions for noncompliance**:
   1. On **Mark device noncompliant**, set **Schedule (days after noncompliance)** = **0.25**.
   2. **Add** > **Send email to end user**. Set Schedule = **0** (Immediately), **Message template** = your template, **Additional recipients** = none.
   3. **Add** > **Send email to end user**. Set Schedule = **2**, **Message template** = your template, **Additional recipients** = none.
   4. Select **Next**.
7. **Scope tags**: **Select scope tags**, tick **Mac Admin**, then **Select**. Select **Next**.
8. **Assignments**: **Add groups** and select your corporate Mac group (pilot group first). Select **Next**.
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
$raw        = (Get-Content ".\Default-Compliance-Policy.json" -Raw) -replace '<notification-template-id>', $templateId
$policyBody = $raw | ConvertFrom-Json -AsHashtable
$policyBody.roleScopeTagIds = @($tagId)

# 4. Create the policy (beta endpoint - Gatekeeper and scope tags are beta-only)
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body ($policyBody | ConvertTo-Json -Depth 10) -ContentType "application/json"

# 5. Assign to your corporate Mac group (replace with the group's object ID)
$groupId = "<entra-group-object-id>"
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
> The `notificationMessageTemplates` and `roleScopeTags` list endpoints in step 2 weren't re-verified on Microsoft Learn for this file. If step 2 fails, create the policy without them (remove the email actions from the JSON), then add the emails and the scope tag in the admin center.

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
6. Set **Enable policy** to **Report-only** first, then switch it **On** once Macs show **Compliant**.

> [!TIP]
> Mac users need the **Company Portal** app and the **Microsoft Enterprise SSO plug-in** (or a supported browser) so Entra ID can identify the Mac at sign-in. Otherwise even compliant Macs are blocked.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status counts: *Compliant*, *In grace period*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | Per-setting pass/fail (SIP, OS version, encryption, firewall, stealth mode, Gatekeeper) |
| **Devices > macOS > (device) > Device compliance > (policy)** | Per-setting result for one Mac |
| **Devices > Monitor > Encryption report** | FileVault status per Mac |
| On the Mac | **Company Portal > (this Mac) > Check status**. Terminal checks:<br>• `csrutil status` (SIP enabled)<br>• `fdesetup status` (FileVault is On)<br>• `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate --getstealthmode`<br>• `spctl --status` (assessments enabled)<br>• `sw_vers` (≥ 15.0) |
| Mail | The user receives the template email immediately, and again after 2 days if still noncompliant |

**Timing:** Macs evaluate at MDM check-in. To force an evaluation, open **Company Portal > Check status**, or select **Sync** for the device in the admin center.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Mac hasn't checked in since assignment, or isn't in the assigned group | Sync from Company Portal or the admin center. Check group membership. |
| **In grace period** | A setting failed less than 6 hours ago | Expected. Fix the setting before the 6 hours end. The user has already been emailed. |
| *Require system integrity protection* noncompliant | SIP disabled from Recovery (`csrutil disable`) | Boot to Recovery, run `csrutil enable`, restart, then sync |
| *Minimum OS version* noncompliant | Mac on macOS 14 or older (stale OS) | Update to macOS 15+. Use a **Software update** policy (DDM) to enforce updates. Check hardware support for macOS 15. |
| *Encryption* noncompliant | FileVault off, or waiting for the user to sign out / restart to start encryption | Assign a FileVault policy. The user signs out or restarts to begin encryption. |
| *Firewall* / *Stealth Mode* noncompliant | User turned them off in System Settings | Enforce with an Endpoint security firewall policy |
| *Gatekeeper* noncompliant | Gatekeeper set to allow apps from anywhere (`spctl --master-disable`) | Re-enable with `spctl --master-enable`, and enforce with a Settings catalog policy |
| Device Health attestation needing a restart | Not applicable on macOS (that is a Windows DHA behaviour) | SIP changes do need a restart. Restart, then sync. |
| No emails received | Template missing, or the user has no mailbox | Check the template under **Compliance > Notifications** and the user's mailbox |
| Noncompliant and user can't fix it | User not licensed for Intune, or Mac enrolled under another user | Assign an Intune license. Check the primary user. |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Lengthen the grace period:** raise **Mark device noncompliant** from 0.25 to 1 day or more if many Macs fail at once (e.g. right after a macOS release).
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: Macs are then governed only by any other assigned macOS policies. If none remain, *Mark devices with no compliance policy assigned as* decides, and if that is **Not compliant**, CA-protected access is blocked. Settings on the Mac (FileVault, firewall, Gatekeeper) are **not** changed.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for macOS in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-macos-settings)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [macOSCompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-macoscompliancepolicy?view=graph-rest-beta)
- [deviceComplianceActionItem resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-devicecomplianceactionitem?view=graph-rest-beta)
- [Monitor results of your compliance policies](https://learn.microsoft.com/intune/device-security/compliance/monitor-policy)
