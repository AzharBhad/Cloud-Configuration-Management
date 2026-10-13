# Firewall Rule – PC Refresh Tool

A Windows Defender Firewall rule, **PC Refresh Tool**, that allows inbound **TCP** traffic so a PC refresh / migration tool can reach devices during a hardware refresh. It's delivered as an Intune **Endpoint security > Firewall > Windows Firewall Rules** policy on Windows 10 and 11.

## Purpose

PC refresh and user-state migration tools copy data and settings from an old device to a new one, either device-to-device or through a migration server. They need to open inbound TCP connections to the device, which Windows Firewall blocks by default. Deploying the rule from Intune:

- lets the refresh tool reach the device without users answering firewall prompts or creating block rules;
- keeps the exception centrally managed, so it can be **removed when the refresh project ends**;
- keeps working when local rule merging is turned off by a firewall hardening policy.

> [!IMPORTANT]
> **Address ranges were given as "assume".** "assume" isn't a valid Firewall CSP value, so I chose these documented values:
>
> | Setting | Value used | Why |
> |---|---|---|
> | Local address ranges | `*` (any local address), the CSP default | The rule should apply to whatever address the device has. |
> | Remote address ranges | `LocalSubnet` | A CSP keyword. It only accepts connections from devices on the **same subnet**, which suits device-to-device migration and is much safer than *any*. |
>
> **If the refresh tool runs from a server or another subnet**, replace `LocalSubnet` with that server's IP or subnet, for example `10.20.30.40` or `10.20.30.0/24`. Remote address ranges also accept other tokens, such as `Intranet`, `DNS` or an IP range like `10.0.0.1-10.0.0.50`.

> [!WARNING]
> No **program** (file path) and no **local port** is set. The rule allows inbound TCP **to any port and any program**, from the remote address range above, on every network profile. Once you know the tool's details, narrow the rule:
> - **Local port ranges**: the TCP ports the tool listens on. Protocol 6 is already set, which local ports need.
> - **File path**: the full path of the tool's agent executable. Wildcards aren't supported.
> - **Network types**: Domain/Private only, if refreshes only happen on site.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `WIN-CFG-Firewall Rule - PC Refresh Tool` |
| Rule name | `PC Refresh Tool` |
| Platform | Windows (Windows 10, Windows 11 and Windows Server) |
| Profile type | Endpoint security > Firewall > **Windows Firewall Rules** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `Firewall-Rule-PC-Refresh-Tool.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin |
| Recommended assignment | A **device** group of devices in the current refresh wave (old and new devices). Remove the assignment when the wave is finished. |
| Supported OS | Windows 10 1709 or later / Windows 11 (Pro, Enterprise, Education, IoT Enterprise) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the Firewall CSP nodes and values in the table below. It doesn't publish:
> - the Windows Firewall Rules **template ID**;
> - the settings catalog **definition IDs** for each rule setting.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the rule in the admin center (steps below), then export it with Graph and **replace this JSON with the export**. The other firewall rule policies in this folder use the same approach.

## Configuration settings

### Windows Firewall Rule – PC Refresh Tool

CSP paths are relative to `./Vendor/MSFT/Firewall/MdmStore/FirewallRules/{FirewallRuleName}/`.

| Setting (admin center name) | Value | Firewall CSP node | What it does / why |
|---|---|---|---|
| Name | `PC Refresh Tool` | `Name` | Friendly name in *Windows Defender Firewall with Advanced Security*. |
| Enabled | Enabled | `Enabled` = `1` | Turns the rule on. |
| Direction | The rule applies to inbound traffic | `Direction` = `IN` | Applies to inbound connections. |
| Action | Allow | `Action/Type` = `1` | Allows matching traffic. |
| Protocol | `6` (TCP) | `Protocol` = `6` | IP protocol number: 6 = TCP, 17 = UDP. |
| Local Address Ranges | `*` (assumed; requested "assume") | `LocalAddressRanges` = `*` | Any local address. `*` must be the only token if used. |
| Remote Address Ranges | `LocalSubnet` (assumed; requested "assume") | `RemoteAddressRanges` = `LocalSubnet` | Only devices on the same subnet can connect. Tokens aren't case-sensitive. |
| Interface Types | All | `InterfaceTypes` = `All` | Every interface type. Select **only** All. |
| Network Types | FW_PROFILE_TYPE_ALL | `Profiles` = `0x7FFFFFFF` (2147483647) | Domain, Private, Public and any future profiles. |

**Not configured**: Description, Local/Remote port ranges, File path / Package family name / Service name, Authorized users, Edge traversal, Policy App ID.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Windows edition | Pro, Enterprise, Education or IoT Enterprise, Windows 10 1709 or later / Windows 11 |
| Enrollment | Intune-enrolled devices (Entra joined, or hybrid joined), or co-managed with the **Endpoint Protection** workload set to Intune |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag |
| Firewall | Windows Defender Firewall must be on |
| Network | Old and new devices on the same subnet (because of `LocalSubnet`), or change the remote address range to the refresh server/subnet |
| Application | The PC refresh tool installed on the devices, if you add a file path |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Firewall > Create Policy**.
3. Set **Platform** to **Windows** and **Profile** to **Windows Firewall Rules**, then select **Create**.
4. **Basics**:
   - **Name**: `WIN-CFG-Firewall Rule - PC Refresh Tool`
   - **Description**: Allow inbound TCP from the local subnet for the PC refresh / migration tool.
   - Select **Next**.
5. **Configuration settings**: select **+ Add** to add a rule, then **Edit rule** and set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Enabled | **Enabled** |
   | 2 | Name | `PC Refresh Tool` |
   | 3 | Direction | **The rule applies to inbound traffic.** |
   | 4 | Action | **Allow** |
   | 5 | Protocol | `6` |
   | 6 | Local Address Ranges | `*` |
   | 7 | Remote Address Ranges | `LocalSubnet`, or the refresh server's IP or subnet |
   | 8 | Interface Types | **All** (only All) |
   | 9 | Network Types | **FW_PROFILE_TYPE_ALL** |
   | 10 | *(Recommended)* Local Port Ranges / File Path | The tool's listening ports and agent `.exe` |

   Leave the other settings **Not configured**. Select **Save**, then **Next**.
6. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
7. **Assignments**: under **Included groups**, add the refresh-wave device group. Select **Next**.
8. **Review + create**: check the rule, then select **Create**.

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
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'WIN-CFG-Firewall Rule - PC Refresh Tool'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Firewall-Rule-PC-Refresh-Tool.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Firewall-Rule-PC-Refresh-Tool.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -Body $body -ContentType "application/json"

# 4. Assign to a device group
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = "<pc-refresh-wave-group-id>" } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assign" -Body $assign -ContentType "application/json"
```

## Assignment & conflict guidance

- **Assign to device groups**, ideally a **temporary** refresh-wave group. This is a project rule, so remove the assignment when the refresh is done.
- **Rules merge across profiles.** This rule adds to the [Echo PAC Loader](../Firewall%20Rule%20Echo%20PAC%20Loader), [Microsoft Teams](../Firewall%20Rule%20Microsoft%20Teams) and [FedEx](../Firewall%20Rules%20FedEx) rules on the device. An explicit **block** rule for the same traffic beats this allow rule.
- **Shielded mode** (in a Windows Firewall profile policy or the security baseline) blocks all inbound traffic and overrides this rule.
- **Keep it in its own profile.** If one rule in a profile fails, the whole profile fails. Keeping this rule separate means a problem elsewhere doesn't stop the refresh.
- **GPO.** Firewall rules from GPO and from MDM are both enforced, so *MDMWinsOverGP* doesn't apply.

## Validation

**In the admin center**
- Open **Endpoint security > Firewall >** the policy **> Device status / Per-setting status**. It should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Confirm the rule arrived:
   ```powershell
   $r = Get-NetFirewallRule -PolicyStore ActiveStore -DisplayName "PC Refresh Tool"
   $r | Select-Object DisplayName, Enabled, Direction, Action, Profile, PolicyStoreSourceType
   $r | Get-NetFirewallPortFilter     # Protocol TCP
   $r | Get-NetFirewallAddressFilter  # LocalAddress Any, RemoteAddress LocalSubnet
   ```
3. From another device on the same subnet, test the tool's port with `Test-NetConnection <device> -Port <tool-port>`. Then run a test migration.
4. For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also use `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Home edition, or Windows older than 1709 | Upgrade the edition or version. |
| **Error**: address ranges "The parameter is incorrect" | An invalid token such as `assume`, `*` combined with other tokens, or a bad range format | Use `*`, `LocalSubnet`, a subnet such as `10.0.0.0/24`, or a range such as `10.0.0.1-10.0.0.50` with no spaces. |
| **Error**: LocalPortRanges "The parameter is incorrect" | Ports set without protocol 6 or 17, or a descending or out-of-range value | Keep Protocol `6`. Use ascending ranges within 0–65535. |
| **Error**: InterfaceTypes | **All** selected together with other interface types | Select only **All**. |
| Tool can't connect | The source device is on a different subnet (`LocalSubnet`), there's an explicit block rule, or shielded mode is on | Set remote addresses to the tool's subnet or server. Check `Get-NetFirewallRule -Action Block`. Check firewall profile policies. |
| Rule isn't present | Assigned to a user group | Assign to a **device** group. |

No restart is needed; Windows Firewall applies the rule as soon as it arrives.

## Rollback

- **Unassign or delete** the policy when the refresh project ends. Intune removes the rule from the device's MDM store and inbound TCP **reverts** to the default block. It isn't tattooed.
- To pause the rule without deleting the policy, edit it and set **Enabled** to **Disabled**.

## References

- [Firewall policy for endpoint security in Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/firewall)
- [Firewall policy settings for endpoint security](https://learn.microsoft.com/intune/device-configuration/endpoint-security/ref-firewall-settings)
- [Firewall CSP (LocalAddressRanges / RemoteAddressRanges tokens)](https://learn.microsoft.com/windows/client-management/mdm/firewall-csp)
- [Windows Firewall rules (precedence, application rules)](https://learn.microsoft.com/windows/security/operating-system-security/network-security/windows-firewall/rules)
