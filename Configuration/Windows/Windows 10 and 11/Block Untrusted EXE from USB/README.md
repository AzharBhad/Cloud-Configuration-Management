# Block Untrusted EXE from USB

Turns on the Microsoft Defender attack surface reduction (ASR) rule **Block untrusted and unsigned processes that run from USB** in **Warn** mode on Windows 10 and 11. It's delivered as an Intune **Endpoint security > Attack surface reduction > Attack Surface Reduction Rules** policy.

## Purpose

USB drives and SD cards are a common way for malware and unapproved tools to get onto a device. This rule stops **unsigned or untrusted executables** (`.exe`, `.dll`, `.scr` and similar) from running directly from removable drives.

With **Warn** mode:
- the user sees a Windows Security notification that the file was blocked;
- the user can **bypass** the block for 24 hours, if they decide the file is legitimate;
- every block and bypass is recorded, so you can review the impact before moving to **Block**.

This follows Microsoft's recommended staged rollout for ASR rules: **Audit → Warn → Block**. It also supports Zero Trust by limiting what can run on a device, and it complements USB storage controls (device control) if you add them later.

> [!NOTE]
> The rule doesn't stop files being **copied** from the USB drive to disk. Untrusted files copied to disk are still evaluated by Defender Antivirus and the other ASR rules.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - ASR - USB_untrusted_EXE` (as shown in the policies-list screenshot; previously `WIN-CFG-Block Untrusted EXE from USB`) |
| Description | Block Untrusted EXEs that run from USB |
| Platform | Windows (Windows 10, Windows 11 and Windows Server) |
| Profile type | Endpoint security > Attack surface reduction > **Attack Surface Reduction Rules** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export; tenants that manage devices through Defender for Endpoint security settings management show `mdm,microsoftSense`. |
| File | `Block-Untrusted-EXE-from-USB.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin |
| Recommended assignment | **Device** groups. Start with a pilot group, then all Windows devices. |
| Supported OS | Windows 10 1709 or later; **Warn mode needs Windows 10 1809 or later**, or Windows 11. Pro, Enterprise and Education. |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the rule's GUID, the CSP and the mode values in the table below. It doesn't publish:
> - the Attack Surface Reduction Rules **template ID**;
> - the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Attack Surface Reduction Rules

| Setting (admin center name) | Value | CSP / rule ID | What it does / why |
|---|---|---|---|
| Block untrusted and unsigned processes that run from USB | **Warn** | `./Device/Vendor/MSFT/Policy/Config/Defender/AttackSurfaceReductionRules` → `b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4=6` | Blocks unsigned or untrusted executables on USB removable drives, including SD cards, and lets the user bypass the block. Mode values: `0` Off, `1` Block, `2` Audit, `5` Not configured, `6` Warn. On Windows 10 earlier than 1809, Warn behaves like **Block**. |
| ASR Only Per Rule Exclusions | *Not configured* | Per-rule exclusions | Add the full paths of approved tools that must run from USB, if needed. |
| All other ASR rules | *Not configured* | — | Left unset so this policy has **one purpose** and doesn't conflict with other ASR policies or the security baseline. |
| Attack Surface Reduction Only Exclusions (global) | *Not configured* | `Policy/Config/Defender/AttackSurfaceReductionOnlyExclusions` | Global exclusions affect **every** ASR rule, so avoid them. Use per-rule exclusions instead. |

**Related Defender settings that must already be on** (normally set in your Antivirus policy, not here): Microsoft Defender Antivirus **real-time protection** and **cloud-delivered protection**. ASR rules depend on Defender Antivirus being the active antivirus.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1, plus Windows E3 or Microsoft 365 E3 for ASR rules. Defender for Endpoint (P1/P2 or Microsoft 365 E5) adds ASR reporting and advanced hunting. |
| Windows edition | Pro, Enterprise or Education. Warn mode needs Windows 10 1809 or later, or Windows 11. |
| Antivirus | **Microsoft Defender Antivirus** must be the active antivirus, with real-time protection on. ASR rules don't work when a non-Microsoft antivirus is active. |
| Enrollment | Intune-enrolled devices (Entra joined, or hybrid joined), or co-managed with the **Endpoint Protection** workload set to Intune |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag |
| Notifications | Windows Security notifications must not be suppressed, or users won't see the Warn prompt |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Attack surface reduction > Create Policy**.
3. Set **Platform** to **Windows** and **Profile** to **Attack Surface Reduction Rules**, then select **Create**.
4. **Basics**:
   - **Name**: `Windows - ASR - USB_untrusted_EXE`
   - **Description**: `Block Untrusted EXEs that run from USB`
   - Select **Next**.
5. **Configuration settings**:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Block untrusted and unsigned processes that run from USB | **Warn** |
   | 2 | ASR Only Per Rule Exclusions (for this rule) | Leave empty, or add approved tool paths |
   | 3 | All other rules | **Not configured** |

   Select **Next**.
6. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
7. **Assignments**: under **Included groups**, add a **pilot device group** first. Add all Windows devices after validation. Select **Next**.
8. **Review + create**: check that the rule shows **Warn**, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates").value |
    Where-Object displayName -like "*Attack Surface Reduction Rules*" | Select-Object id, displayName, templateFamily, platforms, technologies

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - ASR - USB_untrusted_EXE'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Block-Untrusted-EXE-from-USB.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Block-Untrusted-EXE-from-USB.json" -Raw
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
- **Only one source per rule.** ASR rules from **different policies merge** on the device, but if two policies set **this same rule** to different modes (for example Warn here and Block elsewhere), that's a **conflict** and neither value applies. Rules can be set by:
  - other **Attack Surface Reduction Rules** policies;
  - the **Microsoft Defender for Endpoint security baseline**, which sets this rule to **Block** by default;
  - an **Endpoint protection** template profile;
  - a **settings catalog** Defender policy.

  Set the rule to *Not configured* everywhere except this policy, or use baseline exclusions.
- **GPO or PowerShell.** Intune overrides conflicting local PowerShell (`Set-MpPreference`) settings. If a GPO also sets ASR rules on hybrid devices, check which one wins with *MDMWinsOverGP* or remove the GPO setting. Group Policy analytics can help with GPO migration.
- **Exclusions.** Per-rule exclusions for this rule only affect this rule. Global *ASR Only Exclusions* affect all ASR rules on the device.

## Validation

**In the admin center**
- Open **Endpoint security > Attack surface reduction >** the policy **> Device status / Per-setting status**. It should show **Succeeded**.
- Check **Reports > Endpoint security > Attack surface reduction** (needs Defender for Endpoint) for detections and Warn bypasses.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Confirm the rule mode. Expect `b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4` with Action **6**:
   ```powershell
   $p = Get-MpPreference
   0..($p.AttackSurfaceReductionRules_Ids.Count-1) | ForEach-Object {
     [pscustomobject]@{ Id = $p.AttackSurfaceReductionRules_Ids[$_]; Action = $p.AttackSurfaceReductionRules_Actions[$_] }
   } | Where-Object Id -eq "b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4"
   ```
3. Test it: copy an unsigned test `.exe` to a USB drive and run it. You should see a Windows Security **warning** with an option to unblock. Microsoft's ASR demonstration samples can be used for this.
4. Check events in Event Viewer under *Applications and Services Logs > Microsoft > Windows > Windows Defender > Operational*:
   - **1121**: blocked;
   - **1122**: audit;
   - **1129**: user bypassed a Warn block.
5. For policy delivery errors, check *DeviceManagement-Enterprise-Diagnostics-Provider > Admin* or run `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported edition, or Windows 10 earlier than 1709 | Upgrade the OS or edition. |
| **Conflict** | Another policy or the Defender baseline sets this rule to a different mode | Set the rule in only one policy. Use **Per-setting status** to find the other source. |
| **Error** | Invalid exclusion path, or Defender isn't the active antivirus | Fix the exclusions. Check `Get-MpComputerStatus` (AMRunningMode should be **Normal**). |
| Rule blocks with no option to bypass | Windows 10 earlier than 1809, where Warn becomes Block | Update Windows. |
| No prompt, file runs | The file is signed and trusted (allowed by design), the rule isn't applied, or there's an exclusion | Check the rule mode with `Get-MpPreference`. Check exclusions. |
| Legitimate USB tool blocked | Unsigned line-of-business tool | Users can bypass in Warn mode. For a permanent fix, add a per-rule exclusion or get the tool signed. |
| Assigned to a user group but not applied as expected | Device-scoped setting | Assign to device groups. |

No restart is needed. Defender applies the rule when the policy arrives.

## Rollback

- **Unassign or delete** the policy. The rule **reverts** to its default, which is **not configured (off)**. It isn't tattooed.
- To change behaviour without removing the policy, set the rule to **Audit mode** (log only) or **Disable**. Move to **Block** once the Warn period shows no business impact.

## References

- [Attack surface reduction policy settings for endpoint security in Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/ref-attack-surface-reduction-settings)
- [ASR rules reference – Block untrusted and unsigned processes that run from USB](https://learn.microsoft.com/defender-endpoint/attack-surface-reduction-rules-reference#block-untrusted-and-unsigned-processes-that-run-from-usb)
- [Configure ASR rules and exclusions](https://learn.microsoft.com/defender-endpoint/attack-surface-reduction-rules-configure)
- [ASR rules overview (modes, exclusions)](https://learn.microsoft.com/defender-endpoint/attack-surface-reduction-rules-overview)
- [Policy CSP – Defender/AttackSurfaceReductionRules](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-defender#attacksurfacereductionrules)
- [ASR rule demonstrations](https://learn.microsoft.com/defender-endpoint/defender-endpoint-demonstration-attack-surface-reduction-rules)
