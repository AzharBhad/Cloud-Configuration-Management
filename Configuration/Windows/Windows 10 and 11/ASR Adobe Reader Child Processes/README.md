# ASR – Adobe Child Process

Sets the Microsoft Defender attack surface reduction (ASR) rule **Block Adobe Reader from creating child processes** to **Block** on Windows 10 and 11, through an Intune **Endpoint security > Attack surface reduction > Attack Surface Reduction Rules** policy.

## Purpose

Malware can download and launch payloads by breaking out of Adobe Reader. This rule stops Adobe Reader from creating child processes, so a malicious PDF can't use it to spread.

**Why Block:** Malicious PDFs use exploits and social engineering to break out of Adobe Reader. Adobe Reader seldom needs to start other programs.

Microsoft's recommended rollout for ASR rules is **Audit → (Warn) → Block**. Assign the policy to a pilot group first, review detections in **Reports > Endpoint security > Attack surface reduction**, then widen the assignment. If the pilot shows business impact, switch the rule to **Audit** while you add per-rule exclusions.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - ASR - Adobe_Child_Process` (as shown in the screenshot) |
| Description | Block Adobe Reader from creating child processes (Block). |
| Platform | Windows 10 and later |
| Profile type | Endpoint security > Attack surface reduction > **Attack Surface Reduction Rules** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. Tenants that manage devices through Defender for Endpoint security settings management show `mdm,microsoftSense`. |
| File | `ASR-Adobe-Reader-Child-Processes.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups. Start with a pilot group, then all corporate Windows devices. |
| Supported OS | Windows 10 1809 or later / Windows 11 (Pro, Enterprise, Education). Supports **Warn** mode. |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the **Attack Surface Reduction Rules template ID** or the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Attack Surface Reduction Rules

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Block Adobe Reader from creating child processes | **Block** | `./Device/Vendor/MSFT/Policy/Config/Defender/AttackSurfaceReductionRules` → `7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c=1` | Mode values: `0` Off, `1` Block, `2` Audit, `5` Not configured, `6` Warn. Supports **Warn** mode. |
| ASR Only Per Rule Exclusions (this rule) | *Not configured* | Per-rule exclusions | Add the full paths of approved apps only if the pilot shows false positives. |
| All other ASR rules | *Not configured* | — | Each rule is in its own policy (your naming standard), so this policy configures **only** this rule. |

**Dependencies:** Microsoft Defender Antivirus. Microsoft Defender Antivirus must be the active antivirus with real-time protection on (see [Defender Antivirus Configuration](../Defender%20Antivirus%20Configuration)).

> [!IMPORTANT]
> User notifications need the cloud protection level set to **High** or above; EDR alerts need **High plus** or above.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1, plus Windows E3 or Microsoft 365 E3 for ASR rules. Defender for Endpoint (Microsoft 365 E5 or MDE P2) adds ASR reports, alerts and advanced hunting. |
| Antivirus | **Microsoft Defender Antivirus** active (not passive) with real-time protection on |
| Windows | Windows 10 1809 or later / Windows 11 |
| Enrollment | Intune-enrolled devices, or co-managed with the **Endpoint Protection** workload set to Intune |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Attack surface reduction > Create Policy**. Set **Platform** to **Windows** and **Profile** to **Attack Surface Reduction Rules**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - ASR - Adobe_Child_Process`
   - **Description**: Block Adobe Reader from creating child processes (Block).
   - Select **Next**.
4. **Configuration settings**:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Block Adobe Reader from creating child processes | **Block** |
   | 2 | ASR Only Per Rule Exclusions (this rule) | Leave empty |
   | 3 | All other rules | **Not configured** |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add a **pilot device group** first, then all corporate Windows devices once validated. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag and template)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates").value |
    Where-Object displayName -like "*Attack Surface Reduction Rules*" | Select-Object id, displayName, templateFamily, platforms, technologies

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - ASR - Adobe_Child_Process'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\ASR-Adobe-Reader-Child-Processes.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\ASR-Adobe-Reader-Child-Processes.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -Body $body -ContentType "application/json"

# 4. Assign to a device group
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = "<windows-device-group-id>" } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assign" -Body $assign -ContentType "application/json"
```

## Assignment & conflict guidance

- **Assign to device groups.** ASR rules are device-scoped.
- **One source per rule.** ASR rules from different policies **merge**, but if two sources set **this same rule** to different modes it's a **conflict**, and the rule isn't applied. Possible other sources:
  - another ASR Rules policy;
  - the **Microsoft Defender for Endpoint security baseline** (which enables most ASR rules in **Block**);
  - an **Endpoint protection** template profile;
  - a settings catalog Defender policy.

  Set this rule to *Not configured* everywhere else.
- **Your other ASR policies** ([USB untrusted EXE](../Block%20Untrusted%20EXE%20from%20USB) and the ASR policies next to this one) each configure a **different** rule, so they merge without conflicting.
- **GPO and PowerShell.** On hybrid devices, a GPO that sets ASR rules can conflict. Intune overrides local `Set-MpPreference` values.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Check **Reports > Endpoint security > Attack surface reduction** (needs Defender for Endpoint) for detections and blocked files.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Confirm the rule mode. Expect `7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c` with Action **1**:
   ```powershell
   $p = Get-MpPreference
   0..($p.AttackSurfaceReductionRules_Ids.Count-1) | ForEach-Object {
     [pscustomobject]@{ Id = $p.AttackSurfaceReductionRules_Ids[$_]; Action = $p.AttackSurfaceReductionRules_Actions[$_] }
   } | Where-Object Id -eq "7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c"
   ```
3. Check events in Event Viewer under *Applications and Services Logs > Microsoft > Windows > Windows Defender > Operational*: **1121** blocked, **1122** audited, **1129** user bypassed a Warn block.
4. Optionally, test with Microsoft's [ASR rule demonstration samples](https://learn.microsoft.com/defender-endpoint/defender-endpoint-demonstration-attack-surface-reduction-rules) on a test device.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Windows edition or version that doesn't support the rule | Upgrade the OS or edition. |
| **Conflict** | The same rule is set by another ASR policy, the Defender for Endpoint baseline, or an Endpoint protection profile | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid exclusion path, or Defender Antivirus isn't the active antivirus | Fix the value and re-sync. |
| A legitimate app is blocked | False positive | Add a **per-rule exclusion** (full path) or switch to **Audit** temporarily. Don't use global ASR exclusions. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

No device restart is needed; Defender applies the rule when the policy arrives.

## Rollback

- **Unassign or delete** the policy. The rule **reverts** to its default (**not configured / off**). It isn't tattooed.
- To keep monitoring without blocking, set the rule to **Audit**.

## References

- [Attack surface reduction policy settings for endpoint security in Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/ref-attack-surface-reduction-settings)
- [ASR rules reference](https://learn.microsoft.com/defender-endpoint/attack-surface-reduction-rules-reference)
- [ASR rules overview (modes, exclusions)](https://learn.microsoft.com/defender-endpoint/attack-surface-reduction-rules-overview)
- [Configure ASR rules and exclusions](https://learn.microsoft.com/defender-endpoint/attack-surface-reduction-rules-configure)
- [Policy CSP – Defender/AttackSurfaceReductionRules](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-defender#attacksurfacereductionrules)
