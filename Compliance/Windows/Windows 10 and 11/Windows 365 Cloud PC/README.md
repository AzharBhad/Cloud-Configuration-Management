# WIN-COMP-Windows 365 Cloud PC

Intune compliance policy for **Windows 365 Cloud PCs**. It requires:

- Encryption of data storage, firewall and TPM
- Antivirus and antispyware
- Microsoft Defender Antimalware with up-to-date security intelligence
- A password
- A Microsoft Defender for Endpoint machine risk score of **Low** or better

Cloud PCs that fail are marked noncompliant **immediately**.

## Purpose

- **Risk addressed:** a Cloud PC holds corporate data and sessions just like a physical PC. Malware (antivirus or Defender off, outdated security intelligence), a disabled firewall, no password, or a Defender for Endpoint risk above Low put that data at risk.
- **Why a separate Cloud PC policy:** Microsoft documents that some Windows compliance settings don't evaluate correctly on Cloud PCs:
  - **Require BitLocker** and **Require Secure Boot** *might report Not compliant*. BitLocker isn't supported on Cloud PCs, whose disks are encrypted with Azure server-side and host-based encryption.
  - **TPM** and **Require encryption of data storage on device** report **Not applicable**.

  Microsoft's guidance is to exclude Cloud PCs from physical-device policies that contain the *Not compliant* settings, and to give them their own policy without those settings. This is that policy. It has no Device Health (BitLocker / Secure Boot) settings.
- **Zero Trust role:** with the Conditional Access grant **Require device to be marked as compliant**, a Cloud PC that fails any check loses access to Microsoft 365 and other Entra-protected apps at once.

## Policy summary

| Item | Value |
|---|---|
| Display name | `WIN-COMP-Windows 365 Cloud PC` (the name wasn't visible in the screenshot, so this follows the naming standard) |
| Platform | Windows 10 and later |
| Profile type | Windows 10/11 compliance policy |
| Graph `@odata.type` | `#microsoft.graph.windows10CompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Windows-365-Cloud-PC.json` |
| Scope tags | **Windows Admin** |
| Assignment target | Included group **MEM-Windows-Devices-W365 PCs** (Status: Active, Filter: None, Filter mode: None) |
| Noncompliance actions | **Mark device noncompliant** **immediately**. No message template, additional recipients *None selected*. |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint. Firewall, TPM, antivirus, antispyware, Defender and Defender for Endpoint risk properties (`activeFirewallRequired`, `tpmRequired`, `antivirusRequired`, `antiSpywareRequired`, `defenderEnabled`, `signatureOutOfDate`, `deviceThreatProtectionEnabled`, `deviceThreatProtectionRequiredSecurityLevel`) exist only in the beta schema of `windows10CompliancePolicy`.

## Configuration description

Every setting not listed is **Not configured**. That includes all **Device Health** settings (Require BitLocker, Secure Boot, code integrity), which are deliberately left out for Cloud PCs.

### System Security – Encryption

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require encryption of data storage on device | Require | `storageRequireEncryption` | OS-drive encryption check. **On Cloud PCs this reports *Not applicable***, so it doesn't count against compliance. Cloud PC disks are already encrypted at rest (Azure SSE + host-based encryption, AES-256). |

### System Security – Device Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Firewall | Require | `activeFirewallRequired` | Windows Firewall is on |
| Trusted Platform Module (TPM) | Require | `tpmRequired` | TPM present. **On Cloud PCs this reports *Not applicable***. |
| Antivirus | Require | `antivirusRequired` | An antivirus registered with Windows Security Center is on and up to date |
| Antispyware | Require | `antiSpywareRequired` | An antispyware registered with Windows Security Center is on and up to date |

### System Security – Defender

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Microsoft Defender Antimalware | Require | `defenderEnabled` | The Defender antimalware service is running |
| Microsoft Defender Antimalware security intelligence up-to-date | Require | `signatureOutOfDate` | Security intelligence (signatures) is current |

### System Security – Password

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require a password to unlock mobile devices | Require | `passwordRequired` | A password or PIN is needed to unlock the session |

### Microsoft Defender for Endpoint

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require the device to be at or under the machine risk score | **Low** | `deviceThreatProtectionEnabled: true`, `deviceThreatProtectionRequiredSecurityLevel: "low"` | Compliant only with no threats or low-level threats. Medium or high makes the Cloud PC noncompliant. |

### Actions for noncompliance, scope tags and assignments

| Item | Value | Graph |
|---|---|---|
| Mark device noncompliant | **Immediately** | `actionType: "block"`, `gracePeriodHours: 0` |
| Scope tags | Windows Admin | `roleScopeTagIds` (tag **ID**, resolved by the import script) |
| Included groups | MEM-Windows-Devices-W365 PCs | `/assign` with `groupAssignmentTarget` |

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Windows 365** (Enterprise / Business / Flex) per user. **Microsoft Intune Plan 1**. **Microsoft Entra ID P1** for Conditional Access. **Microsoft Defender for Endpoint P2** (or Microsoft 365 E5) for the machine risk score. |
| Cloud PCs | Provisioned and **enrolled in Intune** (Windows 365 enrolls them automatically) |
| Group | Entra **device** group `MEM-Windows-Devices-W365 PCs` containing the Cloud PCs. A dynamic rule on the device model is typical, e.g. `(device.deviceModel -startsWith "Cloud PC")`. Validate it against your Cloud PCs. |
| Defender for Endpoint | **Endpoint security > Microsoft Defender for Endpoint**: connector **Enabled**, *Connect Windows devices* = **On**, and Cloud PCs onboarded (EDR policy). Without this, the risk-score setting can't be evaluated. |
| Scope tag | **Windows Admin** exists under **Tenant administration > Roles > Scope (tags)** |
| Roles | **Intune Administrator** or **Policy and Profile Manager** with the *Windows Admin* scope tag. **Conditional Access Administrator** for CA. |
| Graph import | `Microsoft.Graph.Authentication` module. Scopes `DeviceManagementConfiguration.ReadWrite.All`, `DeviceManagementRBAC.Read.All` and `Group.Read.All`. |

> [!WARNING]
> **Exclude Cloud PCs from physical-device policies.** Your [Require BitLocker](../Require%20BitLocker/README.md) policy is assigned to **All Devices**, and the [Security Baseline](../Security%20Baseline/README.md) policy requires **Secure Boot**. Both settings *might report Not compliant* on Cloud PCs, and a device is compliant only if **every** assigned policy passes. Create the **All Cloud PCs** filter (below) and set it to **Exclude** on those policies' assignments.

### Filter: All Cloud PCs (Microsoft-documented rule)

1. Go to **Intune admin center > Tenant administration > Filters > Managed devices > Create**.
2. Set **Name** = `All Cloud PCs` and **Platform** = *Windows 10 and later*.
3. Rules:
   - **model (Model)** *Contains* `Cloud PC`
   - **Or** **model (Model)** *Contains* `Windows 365`
4. Rule syntax: `(device.model -contains "Cloud PC") or (device.model -contains "Windows 365")`.
5. **Preview** to check the matches, then **Create**.
6. On the physical-device policies, edit **Assignments > All Devices > Filter** to `All Cloud PCs`, with Filter mode **Exclude**.

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Windows 10 and later**, then select **Create**.
4. **Basics**: set **Name** to `WIN-COMP-Windows 365 Cloud PC` (or your tenant's naming convention), and paste the description from the JSON. Select **Next**.
5. **Compliance settings**:
   1. **System Security > Encryption**: Require encryption of data storage on device = **Require**.
   2. **System Security > Device Security**:
      - Firewall = **Require**
      - Trusted Platform Module (TPM) = **Require**
      - Antivirus = **Require**
      - Antispyware = **Require**
   3. **System Security > Defender**:
      - Microsoft Defender Antimalware = **Require**
      - Microsoft Defender Antimalware security intelligence up-to-date = **Require**
   4. **System Security > Password**: Require a password to unlock mobile devices = **Require**.
   5. **Microsoft Defender for Endpoint**: Require the device to be at or under the machine risk score = **Low**.
   6. Leave **Device Health** and everything else **Not configured**, then select **Next**.
6. **Actions for noncompliance**: keep **Mark device noncompliant** with **Schedule** = **0** (Immediately). No message template, no additional recipients. Select **Next**.
7. **Scope tags**: **Select scope tags**, tick **Windows Admin**, then **Select**. Select **Next**.
8. **Assignments**: under **Included groups**, select **Add groups** and choose **MEM-Windows-Devices-W365 PCs**, with no filter. Select **Next**.
9. **Review + create**: confirm the summary matches the tables above, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
# 1. Connect with rights to create compliance policies, read scope tags and groups
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All","Group.Read.All"

# 2. Resolve the scope tag and the assignment group
$tags  = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags"
$tagId = ($tags.value | Where-Object displayName -eq "Windows Admin").id
$grp   = Invoke-MgGraphRequest -Method GET `
         -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq 'MEM-Windows-Devices-W365 PCs'&`$select=id"
$groupId = $grp.value[0].id
if (-not $tagId -or -not $groupId) { throw "Scope tag or group not found" }

# 3. Load the policy JSON and add the scope tag ID (PowerShell 7)
$policyBody = Get-Content ".\Windows-365-Cloud-PC.json" -Raw | ConvertFrom-Json -AsHashtable
$policyBody.roleScopeTagIds = @($tagId)

# 4. Create the policy (beta endpoint)
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body ($policyBody | ConvertTo-Json -Depth 10) -ContentType "application/json"

# 5. Assign to MEM-Windows-Devices-W365 PCs
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $groupId } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"

# 6. Confirm settings, scope tag and assignment
Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=assignments"
```

> [!NOTE]
> The scope-tag lookup (`/beta/deviceManagement/roleScopeTags`) wasn't re-verified on Microsoft Learn for this file. If step 2 fails, set the scope tag in the admin center (step 7 above).

## Tenant-wide compliance settings to review

Go to **Devices > Manage devices > Compliance > Compliance settings**:

| Setting | Recommended | Why |
|---|---|---|
| Mark devices with no compliance policy assigned as | **Not compliant** | Stops unassessed devices, including Cloud PCs missing from the group, from passing Conditional Access |
| Compliance status validity period (days) | **30** (default) | A device that hasn't reported within this period becomes noncompliant |

## Conditional Access integration

1. Go to **Microsoft Entra admin center > Entra ID > Conditional Access > Policies > New policy**.
2. Set **Users** to Cloud PC users, and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
   - Don't block the **Windows 365** / **Azure Virtual Desktop** connection apps on compliance, or users can't reach the Cloud PC to fix it.
4. Under **Conditions > Device platforms**, include **Windows**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first, then switch it **On** once Cloud PCs show **Compliant**.

## Validation

| Where | What to check |
|---|---|
| **Devices > Manage devices > Compliance > Policies > (policy) > Monitor** | Device status for Cloud PCs: *Compliant*, *Not compliant*, *Not evaluated* |
| **Devices > Monitor > Setting compliance** | Per-setting results. **TPM** and **encryption** should show *Not applicable* for Cloud PCs. |
| **Devices > Windows 365 > All Cloud PCs > (Cloud PC) > Device compliance** | Every assigned policy and its per-setting result. Confirm the BitLocker / Secure Boot policies are **excluded** by the filter. |
| **Microsoft Defender portal > Assets > Devices** | The Cloud PC's **Risk level** (*No known risks* / *Low*) and onboarding status |
| Inside the Cloud PC | **Company Portal > Devices > (this PC) > Check status**. `Get-MpComputerStatus \| Select AMServiceEnabled, AntivirusSignatureAge`. `dsregcmd /status`. |
| Logs | `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` inside the Cloud PC |

**Timing:** Cloud PCs evaluate at check-in. To force an evaluation, select **Sync** on the Cloud PC or in the admin center.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Cloud PC not in **MEM-Windows-Devices-W365 PCs**, or hasn't checked in | Check group membership (dynamic rule). Sync the Cloud PC. |
| **In grace period** | Not expected. This policy is *Immediate*. | If shown, another assigned policy has a grace period. Check that policy. |
| Cloud PC **Not compliant** on *Require BitLocker* or *Secure Boot* | A physical-device policy (e.g. *Require BitLocker* → All Devices, or *Security Baseline*) also applies to the Cloud PC | Exclude Cloud PCs from those policies with the **All Cloud PCs** filter. For Secure Boot, Microsoft recommends **reprovisioning** the Cloud PC. |
| Device Health attestation "needs restart" | Not applicable here. This policy has no Device Health settings. | – |
| *Machine risk score* noncompliant | Defender for Endpoint reports Medium/High risk | Investigate and resolve the alerts in the Defender portal |
| *Machine risk score* Not applicable / Error | Defender for Endpoint connector off, or Cloud PC not onboarded | Enable the connector and onboard the Cloud PC (EDR policy) |
| *Security intelligence up-to-date* noncompliant | Updates blocked or the Cloud PC was powered off (Flex / shared) | Run `Update-MpSignature`. Check the Defender update policy. |
| Stale OS version / old image | Cloud PC provisioned from an outdated custom image | Update the image and reprovision, or apply Windows Update rings |
| Noncompliant and user can't fix it | User not licensed for Intune / Windows 365 | Assign licenses. Check the Cloud PC's primary user. |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**. This matters especially because the action is *Immediate*.
2. **Add a grace period:** change **Mark device noncompliant** from 0 to 1 day without removing the policy.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove **MEM-Windows-Devices-W365 PCs**.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: Cloud PCs are then governed only by the other policies that still target them. If none remain, *Mark devices with no compliance policy assigned as* decides, and if that is **Not compliant**, CA-protected access is blocked. **Don't remove the All Cloud PCs exclusion** from the physical-device policies as part of the rollback.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Windows in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-windows-settings)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [windows10CompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windows10compliancepolicy?view=graph-rest-beta)
- [Windows 365 known issues: Cloud PC reports as not compliant](https://learn.microsoft.com/troubleshoot/windows-365/known-issues-enterprise#cloud-pc-reports-as-not-compliant-with-the-compliance-policy)
- [Create a filter for Cloud PCs](https://learn.microsoft.com/windows-365/enterprise/create-filter)
- [Data encryption in Windows 365](https://learn.microsoft.com/windows-365/enterprise/encryption)
