# App Control for Business – Base Policy (Audit, ISG + Windows/Store)

An **App Control for Business** (formerly WDAC) **base** policy in **Audit mode** on Windows 10 and 11. It trusts Windows components and Store apps (MSFT) and apps with good **Intelligent Security Graph** reputation (ISG), and logs everything else without blocking. Delivered as an Intune **Endpoint security > App Control for Business** policy using **built-in controls**.

## Purpose

Application control is one of the most effective defences against executable-based malware: apps must **earn trust** to run.

Deploying in **Audit** mode first shows which apps would be blocked, without affecting users. Use the results to build **supplemental policies** for line-of-business apps, then switch the base policy to **Enforce**.

Reading the policy name:

| Part | Meaning in this policy |
|---|---|
| **MP Base** | A *multiple-policy-format* **base** policy (supplemental policies can extend it) |
| **Audit** | *Enable trust of Windows components and store apps* = **Audit only** |
| **MSFT** | Trust **Windows components and Store apps** |
| **ISG** | **Trust apps with a good reputation** (Intelligent Security Graph) |
| **GE** | **Not clear from the screenshot.** Built-in controls only offer ISG and **managed installer**. If *GE* means something else (for example a custom rule set), the policy must use **Enter XML data** with your own XML instead. |

> [!NOTE]
> Consider also enabling **Trust apps from managed installers**, with the Intune Management Extension set as managed installer, so apps you deploy through Intune are trusted automatically. Microsoft recommends setting up the managed installer at the next available opportunity.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - WDAC - MP Base - Audit ISG+GE+MSFT` (as shown in the screenshot) |
| Description | App Control base policy, audit only: trust Windows components and Store apps + apps with good reputation (ISG). |
| Platform | Windows 10 and later |
| Profile type | Endpoint security > **App Control for Business** (built-in controls) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. Tenants that manage devices through Defender for Endpoint security settings management show `mdm,microsoftSense`. |
| File | `App-Control-Base-Audit.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups. Audit mode is safe to deploy broadly; enforcement should be staged by group. |
| Supported OS | Windows 10 1903 or later / Windows 11 (multiple-policy format) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the **App Control for Business template ID** or the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### App Control for Business

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Configuration settings format | **Use built-in controls** | ApplicationControl CSP | No custom XML; Intune generates the policy. |
| Enable trust of Windows components and store apps | **Audit only** | ApplicationControl CSP | Logs what **would** be blocked; nothing is blocked. |
| Select additional rules for trusting apps | **Trust apps with good reputation** | ApplicationControl CSP | Reputable apps (ISG) are trusted. Base PolicyID `{D6D6C2D6-E8B6-4D8F-8223-14BE1DE562FF}` (built-in controls: Windows + ISG). |

**Supplemental policies** must reference the base **PolicyID**. For built-in controls it's fixed by the options chosen:

| Options | PolicyID |
|---|---|
| Windows components and Store apps | `{A8012CFC-D8AE-493C-B2EA-510F035F1250}` |
| … + good reputation (**this policy**) | `{D6D6C2D6-E8B6-4D8F-8223-14BE1DE562FF}` |
| … + managed installers | `{63D1178A-816A-4AB6-8ECD-127F2DF0CE47}` |
| … + good reputation + managed installers | `{2DA0F72D-1688-4097-847D-C42C39E631BC}` |

If you add *managed installers* later, the PolicyID changes, and supplemental policies must reference the new ID.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1. Defender for Endpoint P2 or E5 for central analysis of audit events in advanced hunting. |
| Windows | Windows 10 1903 or later / Windows 11 |
| Cloud | The ISG option needs cloud connectivity (same intelligence as Defender and SmartScreen) |
| Managed installer (optional) | **Endpoint security > App Control for Business > Managed installer** tab: add the Intune Management Extension |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > App Control for Business** > the **App Control for Business** tab > **Create Policy** (platform is assigned automatically).
3. **Basics**:
   - **Name**: `Windows - WDAC - MP Base - Audit ISG+GE+MSFT`
   - **Description**: App Control base policy, audit only: trust Windows components and Store apps + apps with good reputation (ISG).
   - Select **Next**.
4. **Configuration settings**:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Configuration settings format | Use built-in controls |
   | 2 | Enable trust of Windows components and store apps | Audit only |
   | 3 | Select additional rules for trusting apps | Trust apps with good reputation |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add Windows **device** groups (App Control applies to devices only). Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag and template)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates").value |
    Where-Object displayName -like "*App Control for Business*" | Select-Object id, displayName, templateFamily, platforms, technologies

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - WDAC - MP Base - Audit ISG+GE+MSFT'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\App-Control-Base-Audit.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\App-Control-Base-Audit.json" -Raw
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

- **Base and supplemental policies.** Multiple base policies can coexist (Windows 10 1903+). A file must be allowed by **every** base policy to run once enforced, so plan bases carefully. Supplementals only extend the base whose PolicyID they reference.
- **Old App Control profiles.** Remove legacy *Application Control* settings under ASR policies or Endpoint protection templates; Microsoft is deprecating them.
- **ASR rules** (for example *Untrusted executables*) and **Smart App Control** complement App Control, but can block the same files. Review their events together.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Check advanced hunting (Defender for Endpoint) for `DeviceEvents | where ActionType startswith "AppControl"`, which shows the audit events across devices.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Run `CiTool.exe -lp` (Windows 11) to list active policies. The base policy shows as audit.
3. Check events in Event Viewer under *Applications and Services Logs > Microsoft > Windows > CodeIntegrity > Operational*. **3076** means audit (it would have been blocked). There are also script events under *AppLocker > MSI and Script* (8028). Collect 2–4 weeks of audit data before enforcing.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | Legacy Application Control settings from another profile | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Unsupported Windows build | Fix the value and re-sync. |
| Lots of 3076 events for in-house apps | Unsigned or unknown LOB apps | Deploy them through Intune with managed installer, sign them, or add a supplemental policy. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

Policies apply without a restart on supported builds (ApplicationControl CSP).

## Rollback

- **Unassign or delete** the policy. The App Control policy is **removed** from devices; in Audit mode nothing was blocked.
- Before switching to **Enforce**, make sure you can roll back quickly (unassign) and test on a pilot group.

## References

- [Manage approved apps with App Control for Business and managed installers](https://learn.microsoft.com/intune/device-configuration/endpoint-security/manage-app-control)
- [Authorize reputable apps with the Intelligent Security Graph](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/design/use-appcontrol-with-intelligent-security-graph)
- [Allow apps deployed by a managed installer](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/design/configure-authorized-apps-deployed-with-a-managed-installer)
- [App Control policy design decisions](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/design/understand-appcontrol-policy-design-decisions)
