# Firewall Rules – FedEx

Two Windows Defender Firewall rules for the FedEx shipping software, **FedEx Shipping Manager** and **FedEx GSMW**, on Windows 10 and 11. They're delivered together in one Intune **Endpoint security > Firewall > Windows Firewall Rules** policy.

## Purpose

FedEx Ship Manager software talks to local services and other workstations (shared shipping database, label printers, and the FedEx servers). Windows Firewall blocks unsolicited inbound connections by default, and a non-admin user answering the firewall prompt creates **block** rules. Deploying the rules from Intune:

- lets the FedEx application accept the connections it needs, without user prompts;
- keeps the exceptions centrally managed and auditable;
- keeps working when local rule merging is turned off by a firewall hardening policy.

> [!WARNING]
> **File path `C:\` is not an application path, in either rule.** The Firewall CSP `App/FilePath` must be the **full path of an executable**, such as `C:\Windows\System\Notepad.exe`. Wildcards aren't supported.
> - A drive root won't match the FedEx processes.
> - It may make the rule fail. **If one rule fails, every rule in the profile fails**, so both FedEx rules would fail together.
> - Replace `C:\` with the real executables. On a device running FedEx Ship Manager, find them with `Get-Process | Where-Object Path -like "*FedEx*" | Select-Object Name, Path`. If a FedEx component runs as a Windows service, use **Service name** instead.

> [!IMPORTANT]
> **Rule 2 (FedEx GSMW) has no Direction or Action set.** When they're not configured, the CSP defaults apply: **Direction = OUT** (outbound) and **Action = Allow**.
> - Windows allows outbound traffic by default, so as configured this rule has **no effect** unless outbound traffic is blocked by default (*Block outbound connections = Yes*).
> - If GSMW needs to **receive** connections like rule 1, set **Direction** to *The rule applies to inbound traffic* and **Action** to *Allow*.

> [!CAUTION]
> With no protocol, port or remote address set, rule 1 allows **all inbound traffic** to the FedEx program from **any address** on **all network profiles, including Public**. Once the paths are right, consider restricting:
> - **Network types** to Domain/Private;
> - **Remote address ranges** to the shipping workstation or server subnet;
> - **Protocol/ports** to the ones FedEx documents for your installation.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `WIN-CFG-Firewall Rules - FedEx` |
| Rules | `FedEx Shipping Manager`, `FedEx GSMW` |
| Platform | Windows (Windows 10, Windows 11 and Windows Server) |
| Profile type | Endpoint security > Firewall > **Windows Firewall Rules** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `Firewall-Rules-FedEx.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin |
| Recommended assignment | A **device** group containing only the shipping workstations that run FedEx Ship Manager. Firewall rules are device-scoped. |
| Supported OS | Windows 10 1709 or later / Windows 11 (Pro, Enterprise, Education, IoT Enterprise) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the Firewall CSP nodes and values in the tables below. It doesn't publish:
> - the Windows Firewall Rules **template ID**;
> - the settings catalog **definition IDs** for each rule setting.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the rules in the admin center (steps below), then export the policy with Graph and **replace this JSON with the export**. The other firewall rule policies in this folder use the same approach.

## Configuration settings

CSP paths are relative to `./Vendor/MSFT/Firewall/MdmStore/FirewallRules/{FirewallRuleName}/`.

### Rule 1 – FedEx Shipping Manager

| Setting (admin center name) | Value | Firewall CSP node | What it does / why |
|---|---|---|---|
| Name | `FedEx Shipping Manager` | `Name` | Friendly name in *Windows Defender Firewall with Advanced Security*. |
| Enabled | Enabled | `Enabled` = `1` | Turns the rule on. |
| Direction | The rule applies to inbound traffic | `Direction` = `IN` | Applies to inbound connections. |
| Action | Allow | `Action/Type` = `1` | Allows matching traffic. |
| Interface Types | All | `InterfaceTypes` = `All` | Every interface type. Select **only** All. |
| File Path | `C:\` (as requested; see the warning above) | `App/FilePath` | Must be the full path of the FedEx executable. |
| Network Types | *Not configured* (left blank) | `Profiles` | Blank means the CSP default: **All** profiles (Domain, Private, Public). |

### Rule 2 – FedEx GSMW

| Setting (admin center name) | Value | Firewall CSP node | What it does / why |
|---|---|---|---|
| Name | `FedEx GSMW` | `Name` | Friendly name. |
| Enabled | Enabled | `Enabled` = `1` | Turns the rule on. |
| Direction | *Not configured* (left blank) | `Direction` | Default **OUT**: the rule applies to outbound traffic. See the important note above. |
| Action | *Not specified* | `Action/Type` | Default **Allow** (`1`). |
| Interface Types | All | `InterfaceTypes` = `All` | Every interface type. |
| File Path | `C:\` (as requested; see the warning above) | `App/FilePath` | Must be the full path of the GSMW executable. |
| Network Types | *Not configured* (left blank) | `Profiles` | Default **All** profiles. |

**Not configured in either rule** (they match any value): Description, Protocol, Local/Remote port ranges, Local/Remote address ranges, Package family name, Service name, Authorized users, Edge traversal, Policy App ID.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Windows edition | Pro, Enterprise, Education or IoT Enterprise, Windows 10 1709 or later / Windows 11 |
| Enrollment | Intune-enrolled devices (Entra joined, or hybrid joined), or co-managed with the **Endpoint Protection** workload set to Intune |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag |
| Firewall | Windows Defender Firewall must be on |
| Application | FedEx Ship Manager installed at the **exact paths** used in the rules |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Firewall > Create Policy**.
3. Set **Platform** to **Windows** and **Profile** to **Windows Firewall Rules**, then select **Create**.
4. **Basics**:
   - **Name**: `WIN-CFG-Firewall Rules - FedEx`
   - **Description**: Firewall rules for FedEx Ship Manager (Shipping Manager and GSMW).
   - Select **Next**.
5. **Configuration settings**: select **+ Add**, then **Edit rule**, and set **rule 1**:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Enabled | **Enabled** |
   | 2 | Name | `FedEx Shipping Manager` |
   | 3 | Direction | **The rule applies to inbound traffic.** |
   | 4 | Action | **Allow** |
   | 5 | Interface Types | **All** |
   | 6 | File Path | `C:\`. **Recommended:** the full path to the FedEx Ship Manager `.exe`. |
   | 7 | Network Types | Leave unselected (all profiles) |

   Select **Save**. Then select **+ Add** again, then **Edit rule**, and set **rule 2**:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Enabled | **Enabled** |
   | 2 | Name | `FedEx GSMW` |
   | 3 | Direction | Leave **Not configured** (outbound). **Recommended:** inbound, if GSMW receives connections. |
   | 4 | Action | Leave **Not configured** (Allow), or set **Allow** explicitly |
   | 5 | Interface Types | **All** |
   | 6 | File Path | `C:\`. **Recommended:** the full path to the GSMW `.exe`. |
   | 7 | Network Types | Leave unselected (all profiles) |

   Select **Save**, then **Next**.
6. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
7. **Assignments**: under **Included groups**, add the shipping workstations device group. Select **Next**.
8. **Review + create**: check both rules, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates").value |
    Where-Object displayName -like "*Firewall Rules*" | Select-Object id, displayName, templateFamily, platforms, technologies

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'WIN-CFG-Firewall Rules - FedEx'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Firewall-Rules-FedEx.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Firewall-Rules-FedEx.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -Body $body -ContentType "application/json"

# 4. Assign to a device group
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = "<fedex-workstations-group-id>" } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assign" -Body $assign -ContentType "application/json"
```

## Assignment & conflict guidance

- **Assign to device groups**, and only to the shipping workstations. Firewall rules are device-scoped, and keeping them narrow limits the inbound exception.
- **The two rules succeed or fail together.** They're in the same profile, and if one rule is invalid (for example, the `C:\` path), **both** fail. Intune can't tell you which one caused it.
- **Rules merge across profiles.** These rules add to the [Echo PAC Loader](../Firewall%20Rule%20Echo%20PAC%20Loader) and [Microsoft Teams](../Firewall%20Rule%20Microsoft%20Teams) rules on the device. An explicit **block** rule for the same program from any source (Intune, GPO, or a user prompt) beats these allow rules.
- **Shielded mode** (in a Windows Firewall profile policy or the security baseline) blocks all inbound traffic and overrides rule 1.
- **Block outbound connections.** Rule 2 only has an effect if a Windows Firewall profile policy sets *Block outbound connections = Yes*.
- **GPO.** Firewall rules from GPO and from MDM are both enforced, so *MDMWinsOverGP* doesn't apply. Check that no GPO blocks FedEx.

## Validation

**In the admin center**
- Open **Endpoint security > Firewall >** the policy **> Device status / Per-setting status**. It should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Confirm the rules arrived:
   ```powershell
   Get-NetFirewallRule -PolicyStore ActiveStore -DisplayName "FedEx*" |
       Select-Object DisplayName, Enabled, Direction, Action, Profile, PolicyStoreSourceType
   Get-NetFirewallRule -PolicyStore ActiveStore -DisplayName "FedEx*" | Get-NetFirewallApplicationFilter
   ```
   Expect:
   - **FedEx Shipping Manager**: Inbound / Allow
   - **FedEx GSMW**: Outbound / Allow, unless you changed it

   Both should show `Profile Any` and `PolicyStoreSourceType MDM`.
3. Open FedEx Ship Manager and run a test shipment or label print. Check that no firewall prompt appears.
4. For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also use `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Home edition, or Windows older than 1709 | Upgrade the edition or version. |
| **Error** (both rules fail) | A file path isn't an executable, or another value is invalid | Set the full `.exe` paths. Re-sync. |
| **Error**: InterfaceTypes "The parameter is incorrect" | **All** selected together with other interface types | Select only **All**. |
| FedEx still blocked inbound | The path doesn't match the running process, the traffic goes to a different FedEx executable or service, or a local block rule exists from an earlier prompt | Check process paths. Add a rule per executable or service. Remove block rules: `Get-NetFirewallRule -PolicyStore PersistentStore -Action Block | Where-Object DisplayName -like "*FedEx*"`. |
| GSMW still can't receive connections | Rule 2 is outbound by default | Set **Direction** to inbound. |
| Rules aren't present | Assigned to a user group | Assign to a **device** group. |

No restart is needed; Windows Firewall applies the rules as soon as they arrive.

## Rollback

- **Unassign or delete** the policy. Intune removes both rules from the device's MDM store and the exceptions **revert** (they're removed). They aren't tattooed.
- To turn off one rule only, edit it and set **Enabled** to **Disabled**.
- After rollback, FedEx may prompt users again. Non-admin users will get block rules.

## References

- [Firewall policy for endpoint security in Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/firewall)
- [Firewall policy settings for endpoint security](https://learn.microsoft.com/intune/device-configuration/endpoint-security/ref-firewall-settings)
- [Firewall CSP](https://learn.microsoft.com/windows/client-management/mdm/firewall-csp)
- [Windows Firewall rules (application rules, precedence, user prompt)](https://learn.microsoft.com/windows/security/operating-system-security/network-security/windows-firewall/rules)
