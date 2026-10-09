# Windows-Compliance-AllDevices-Baseline-Immediate

Baseline Intune compliance policy for **all Windows 10 and Windows 11 devices**. It requires:

- Secure Boot and code integrity
- Firewall and TPM
- Antivirus and antispyware
- Microsoft Defender Antimalware with up-to-date security intelligence
- A non-simple password, required again when the device returns from idle
- A Microsoft Defender for Endpoint machine risk score of **Low** or better

Devices that fail any setting are marked noncompliant **immediately**.

## Purpose

- **Risk addressed:**
  - Boot-level tampering (no Secure Boot or code integrity)
  - Malware on unprotected endpoints (antivirus or Defender off, outdated security intelligence)
  - Devices without a TPM or firewall
  - Unlocked devices
  - Devices that Defender for Endpoint rates above Low risk
- **Zero Trust role:** compliance is the "device is healthy" signal. Paired with the Conditional Access grant **Require device to be marked as compliant**, only devices that pass this policy can reach Microsoft 365 and other Entra-protected apps.
- **"Immediate":** there is no grace period. Any failed setting blocks CA-protected access at the next evaluation.

## Policy summary

| Item | Value |
|---|---|
| Display name | `Windows-Compliance-AllDevices-Baseline-Immediate` |
| Platform | Windows 10 and later |
| Profile type | Windows 10/11 compliance policy |
| Graph `@odata.type` | `#microsoft.graph.windows10CompliancePolicy` |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies` |
| File | `Security-Baseline.json` |
| Assignment target | All corporate Windows devices: a device group (or **All devices**), or user groups of licensed Windows users. Don't mix both for the same device. |
| Noncompliance actions | **Mark device noncompliant** **immediately** (schedule 0 days) |

> [!NOTE]
> The JSON uses the Graph **beta** endpoint. In Graph v1.0, `windows10CompliancePolicy` doesn't expose the firewall, TPM, antivirus, antispyware, Defender or Defender for Endpoint risk properties (`activeFirewallRequired`, `tpmRequired`, `antivirusRequired`, `antiSpywareRequired`, `defenderEnabled`, `signatureOutOfDate`, `deviceThreatProtectionEnabled`, `deviceThreatProtectionRequiredSecurityLevel`). They exist only in beta. Microsoft supports Intune beta APIs, but they can change.

## Configuration description

Settings not listed below are **Not configured**. That includes Require BitLocker, minimum/maximum OS version, encryption of data storage, real-time protection, Defender minimum version and Configuration Manager compliance.

### Device Health – Windows Health Attestation Service evaluation rules

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require Secure Boot to be enabled on the device | Require | `secureBootEnabled` | The device boots only with trusted, signed boot components. Blocks bootkits. Measured at boot by Device Health Attestation. |
| Require code integrity | Require | `codeIntegrityEnabled` | Detects unsigned drivers or system files being loaded into the kernel |

### System Security – Password

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require a password to unlock mobile devices | Require | `passwordRequired` | A password or PIN is needed to unlock the device |
| Simple passwords | Block | `passwordBlockSimple` | Blocks simple passwords and PINs such as `1234` or `1111` |
| Require password when device returns from idle state (Mobile and Holographic) | Require | `passwordRequiredToUnlockFromIdle` | The user must enter the password every time the device comes back from idle |

> [!WARNING]
> When the password requirement is applied to Windows desktops, users are affected at their **next sign-in** and may be prompted to change their password even when it already meets the requirement. Communicate this before assignment.

### System Security – Device Security

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Firewall | Require | `activeFirewallRequired` | Windows Firewall is on. A GPO that disables the firewall makes this noncompliant. |
| Trusted Platform Module (TPM) | Require | `tpmRequired` | The device reports a TPM (spec version > 0) |
| Antivirus | Require | `antivirusRequired` | An antivirus registered with Windows Security Center is on and up to date |
| Antispyware | Require | `antiSpywareRequired` | An antispyware registered with Windows Security Center is on and up to date |

### System Security – Defender

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Microsoft Defender Antimalware | Require | `defenderEnabled` | The Defender antimalware service is running |
| Microsoft Defender Antimalware security intelligence up-to-date | Require | `signatureOutOfDate` | Security intelligence (signatures) is current |

> [!WARNING]
> If a third-party antivirus is the primary AV, Defender runs in passive mode and fails **Microsoft Defender Antimalware**. With *Immediate* actions those devices are blocked at once. Exclude them, or use a separate policy that keeps only *Antivirus* and *Antispyware*.

### Microsoft Defender for Endpoint

| Setting (admin center name) | Value | Graph property | What it checks / why |
|---|---|---|---|
| Require the device to be at or under the machine risk score | **Low** | `deviceThreatProtectionEnabled: true`, `deviceThreatProtectionRequiredSecurityLevel: "low"` | The device is compliant only if Defender for Endpoint reports no threats or low-level threats. Medium or high makes it noncompliant. |

### Actions for noncompliance

| Action | Schedule | Graph |
|---|---|---|
| Mark device noncompliant | **Immediately** (0 days) | `actionType: "block"`, `gracePeriodHours: 0` |

## Prerequisites

| Area | Requirement |
|---|---|
| Licensing | **Microsoft Intune Plan 1** per user (included in Microsoft 365 E3/E5, EMS). **Microsoft Entra ID P1** for Conditional Access. **Microsoft Defender for Endpoint P2** (or Microsoft 365 E5) for the machine risk score. |
| Enrollment | Windows 10 / Windows 11 devices **enrolled in Intune** (Entra joined, hybrid joined via auto-enrollment, or co-managed) |
| Defender for Endpoint | **Intune admin center > Endpoint security > Microsoft Defender for Endpoint**: the connection is **Enabled**, *Connect Windows devices … to Microsoft Defender for Endpoint* = **On**, and devices are **onboarded** (EDR onboarding policy). Without this, the risk score setting can't be evaluated. |
| Hardware | TPM 2.0 and UEFI Secure Boot (Windows 11 hardware requirement) |
| Roles | **Intune Administrator** or **Policy and Profile Manager**. **Conditional Access Administrator** for the CA policy. |
| Defender | Defender Antivirus policy (Endpoint security > Antivirus) for updates |
| Graph import | `Microsoft.Graph.Authentication` PowerShell module, delegated scope `DeviceManagementConfiguration.ReadWrite.All` |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the **Microsoft Intune admin center** (<https://intune.microsoft.com>).
2. Go to **Devices > Manage devices > Compliance**, open the **Policies** tab and select **Create policy**.
3. **Platform**: select **Windows 10 and later**, then select **Create**.
4. **Basics**: set **Name** to `Windows-Compliance-AllDevices-Baseline-Immediate`. Optionally paste the description from the JSON. Select **Next**.
5. **Compliance settings**: expand each category and set:
   1. **Device Health > Windows Health Attestation Service evaluation rules**:
      - Require Secure Boot to be enabled on the device = **Require**
      - Require code integrity = **Require**
   2. **System Security > Password**:
      - Require a password to unlock mobile devices = **Require**
      - Simple passwords = **Block**
      - Require password when device returns from idle state (Mobile and Holographic) = **Require**
   3. **System Security > Device Security**:
      - Firewall = **Require**
      - Trusted Platform Module (TPM) = **Require**
      - Antivirus = **Require**
      - Antispyware = **Require**
   4. **System Security > Defender**:
      - Microsoft Defender Antimalware = **Require**
      - Microsoft Defender Antimalware security intelligence up-to-date = **Require**
   5. **Microsoft Defender for Endpoint**: Require the device to be at or under the machine risk score = **Low**.
   6. Leave every other setting **Not configured**. Select **Next**.
6. **Actions for noncompliance**: keep **Mark device noncompliant** with **Schedule (days after noncompliance)** = **0** (Immediately).
   - *Optional:* **Add** > **Send email to end user**, schedule **0**, with a template from **Devices > Manage devices > Compliance > Notifications**.
   - Select **Next**.
7. **Scope tags**: add your RBAC tags or keep **Default**, then select **Next**.
8. **Assignments**: **Add groups** and select a pilot device group first, then all Windows devices. Select **Next**.
9. **Review + create**: compare the summary with the tables above, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
# 1. Connect with rights to create compliance policies
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All"

# 2. Create the policy from the JSON (beta endpoint - see the NOTE in "Policy summary")
$body   = Get-Content ".\Security-Baseline.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST `
          -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies" `
          -Body $body -ContentType "application/json"
$policy.id                                            # keep the new policy ID

# 3. Assign it to a group (replace with your group's object ID)
$groupId = "<entra-group-object-id>"
$assign  = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = $groupId } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)/assign" `
  -Body $assign -ContentType "application/json"

# 4. Confirm
Invoke-MgGraphRequest -Method GET `
  -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies/$($policy.id)?`$expand=assignments"
```

> [!TIP]
> To target **All devices** instead of a group, use the target `@{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" }`.

## Tenant-wide compliance settings to review

Go to **Devices > Manage devices > Compliance > Compliance settings**:

| Setting | Recommended | Why |
|---|---|---|
| Mark devices with no compliance policy assigned as | **Not compliant** | Stops unassessed devices from passing Conditional Access |
| Compliance status validity period (days) | **30** (default) | A device that hasn't reported within this period becomes noncompliant |

## Conditional Access integration

1. Go to **Microsoft Entra admin center > Entra ID > Conditional Access > Policies > New policy**.
2. Set **Users** to all users (or the pilot group), and **exclude the break-glass accounts**.
3. Set **Target resources** to **Office 365** (then expand to all resources).
4. Under **Conditions > Device platforms**, include **Windows**.
5. Under **Grant**, select **Require device to be marked as compliant**.
6. Set **Enable policy** to **Report-only** first, then switch it **On** once pilot devices show **Compliant**.

> [!WARNING]
> Because this policy is **Immediate**, any device that fails a setting, or reaches **Medium** risk in Defender for Endpoint, is blocked at once once CA is **On**. Check the per-setting report on pilot devices before enforcing.

## Validation

| Where | What to check |
|---|---|
| **Devices > Monitor > Device compliance** / **Setting compliance** | Overall status and the per-setting pass/fail counts for this policy |
| **Devices > Manage devices > Compliance > Policies > (policy) > Device status** | Each assigned device: *Compliant*, *Not compliant*, *Not evaluated* |
| **Devices > Windows > (device) > Device compliance** | Per-setting result for one device |
| **Microsoft Defender portal > Assets > Devices** | The device's **Risk level** (must be *No known risks* or *Low*) and onboarding status |
| On the device | **Company Portal > Devices > (this PC) > Check status**, or **Settings > Accounts > Access work or school > (account) > Info > Sync** |
| On the device (logs) | `%ProgramData%\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log`. Run `dsregcmd /status` to confirm the device is joined and has a PRT. |
| Entra sign-in logs | **Device info** tab shows *Compliant: Yes* and the CA policy result |

**Timing:**
- Devices evaluate at check-in, and sooner when a monitored setting changes (firewall, antivirus, Defender, Secure Boot).
- To force an evaluation, select **Sync** on the device or in the admin center.
- Device Health settings (Secure Boot, code integrity) are measured **at boot**, so restart after firmware changes.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Not evaluated** | Device hasn't checked in since assignment, or isn't in the assigned group | Sync the device. Check group membership and assignment type. |
| *Machine risk score* noncompliant | Defender for Endpoint reports a Medium/High risk alert | Investigate and resolve the alerts in the Defender portal. The risk level drops after remediation. |
| *Machine risk score* shows **Not applicable / Error** | Defender for Endpoint connector off, or device not onboarded | Enable the connector and onboard the device (EDR policy) |
| *Require Secure Boot* noncompliant | Secure Boot off in UEFI, legacy BIOS mode, or TPM 2.0 missing | Enable Secure Boot in firmware, or convert MBR to GPT (`mbr2gpt`), then restart |
| *Password* settings noncompliant | No password/PIN, or a simple PIN (e.g. `1234`) | Set a compliant password/PIN, then sync |
| *Firewall* noncompliant despite Intune firewall policy | A GPO turns the firewall off or allows all inbound | Remove the conflicting GPO setting |
| *Firewall* shows **Error** after reboot / sleep | Device synced before the firewall reported status | Sync again |
| *Microsoft Defender Antimalware* noncompliant | Third-party AV made Defender passive, or the Defender service is disabled | See the WARNING under Defender. Re-enable Defender. |
| *Security intelligence up-to-date* noncompliant | Device offline or blocked from update sources | Run `Update-MpSignature`, then check WSUS / Defender update policy |
| Device noncompliant and user can't fix it | User not licensed for Intune, or device enrolled under another user | Assign an Intune license. Check the device's primary user. |

## Rollback

1. **Pause enforcement:** set the CA policy that requires compliance to **Report-only**.
2. **Relax the timing if needed:** change the **Mark device noncompliant** schedule from 0 to 1 day to give users a grace period, without removing the policy.
3. **Unassign:** **Compliance > Policies > (policy) > Properties > Assignments > Edit**, then remove the groups.
4. **Or delete:** **Compliance > Policies > (policy) > Delete**, or `Invoke-MgGraphRequest -Method DELETE -Uri ".../beta/deviceManagement/deviceCompliancePolicies/<id>"`.

Effect: if no other policy targets the device, its state is governed by *Mark devices with no compliance policy assigned as*. If that is **Not compliant**, CA-protected access is still blocked, so keep CA in report-only until a replacement policy is assigned.

## References

- [Create a compliance policy in Microsoft Intune](https://learn.microsoft.com/intune/device-security/compliance/create-policy)
- [Device compliance settings for Windows in Intune](https://learn.microsoft.com/intune/device-security/compliance/ref-windows-settings)
- [Configure actions for noncompliant devices](https://learn.microsoft.com/intune/device-security/compliance/configure-noncompliance-actions)
- [windows10CompliancePolicy resource type (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfig-windows10compliancepolicy?view=graph-rest-beta)
- [Monitor results of your compliance policies](https://learn.microsoft.com/intune/device-security/compliance/monitor-policy)
- [Enforce compliance for Microsoft Defender for Endpoint with Conditional Access](https://learn.microsoft.com/intune/protect/advanced-threat-protection)
- [Require device compliance with Conditional Access](https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-device-compliance)
