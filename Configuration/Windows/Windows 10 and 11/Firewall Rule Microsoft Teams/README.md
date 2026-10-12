# Firewall Rule – Microsoft Teams

A Windows Defender Firewall rule, **Microsoft Teams**, that allows inbound **UDP** traffic so Teams calls and meetings can use direct media paths. It's delivered as an Intune **Endpoint security > Firewall > Windows Firewall Rules** policy on Windows 10 and 11.

## Purpose

Teams audio, video and screen sharing work best over UDP, including peer-to-peer media between clients. The first time Teams listens for inbound media, Windows Firewall prompts the user. A user who isn't a local admin, or who cancels the prompt, ends up with **block** rules. Media then falls back to relays or TCP, which hurts call quality.

Deploying the rule from Intune:

- avoids the firewall prompt and the block rules it can create;
- keeps Teams media on UDP for better call quality;
- keeps working when local rule merging is turned off by a firewall hardening policy.

> [!WARNING]
> **As configured, this rule is not specific to Teams.** No application (file path or package family name), no local port range and no remote address range is set. The rule therefore allows **all inbound UDP, to any port, for any program, from any address, on every network profile including Public**.
>
> Recommended hardening, in order:
> 1. Under **Package Family Name**, set `MSTeams_8wekyb3d8bbwe` so the rule only matches the new Teams client.
>    - A file path doesn't work well for the new Teams client. It installs under a folder whose name changes with every update (`C:\Program Files\WindowsApps\MSTeams_<version>_x64__8wekyb3d8bbwe\ms-teams.exe`), and Windows Firewall doesn't support wildcards in paths.
>    - Check the name on a device with `Get-AppxPackage -Name MSTeams | Select-Object PackageFamilyName`.
> 2. Fill in **Local port range** with the UDP ports your Teams media policy uses, if you've set specific client media ports.
> 3. Leave out the **Public** network type if peer-to-peer media on public networks isn't needed.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `WIN-CFG-Firewall Rule - Microsoft Teams` |
| Rule name | `Microsoft Teams` |
| Platform | Windows (Windows 10, Windows 11 and Windows Server) |
| Profile type | Endpoint security > Firewall > **Windows Firewall Rules** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `Firewall-Rule-Microsoft-Teams.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin |
| Recommended assignment | A **device** group of Windows devices that run Teams. Firewall rules are device-scoped. |
| Supported OS | Windows 10 1709 or later / Windows 11 (Pro, Enterprise, Education, IoT Enterprise) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the Firewall CSP nodes and values in the tables below. It doesn't publish:
> - the Windows Firewall Rules **template ID**;
> - the settings catalog **definition IDs** for each rule setting.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the rule in the admin center (steps below), then export it with Graph and **replace this JSON with the export**. The [Echo PAC Loader rule](../Firewall%20Rule%20Echo%20PAC%20Loader) uses the same approach.

## Configuration settings

### Windows Firewall Rule – Microsoft Teams

| Setting (admin center name) | Value | Firewall CSP node (`./Vendor/MSFT/Firewall/MdmStore/FirewallRules/{FirewallRuleName}/…`) | What it does / why |
|---|---|---|---|
| Name | `Microsoft Teams` | `Name` | Friendly name shown in *Windows Defender Firewall with Advanced Security*. |
| Enabled | Enabled | `Enabled` = `1` | Turns the rule on. |
| Direction | The rule applies to inbound traffic | `Direction` = `IN` | Applies to inbound connections. If not configured, the default is **OUT**. |
| Action | Allow | `Action/Type` = `1` | Allows matching traffic. |
| Protocol | `17` (UDP) | `Protocol` = `17` | IP protocol number: 6 = TCP, 17 = UDP. Teams media prefers UDP. |
| Local port range | *Not configured* (left blank) | `LocalPortRanges` | Blank means **all** local ports. If you set it later, Protocol must be 6 or 17, which it already is. Ranges must be ascending and within 0–65535. |
| Remote address range | *Not configured* (left blank) | `RemoteAddressRanges` | Blank means **any** remote address (`*`). |
| Interface Types | All | `InterfaceTypes` = `All` | If **All** is selected, don't select any other interface type, or the rule fails. |
| Network Types | FW_PROFILE_TYPE_ALL: This value represents all these network sets and any future network sets | `Profiles` = `0x7FFFFFFF` (2147483647) | Domain, Private, Public and any future profiles. |

**Not configured**: Description, Package family name / File path / Service name (see the hardening warning above), Remote port ranges, Local address ranges, Authorized users, Edge traversal, Policy App ID.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1. Teams itself needs a Microsoft 365 / Teams licence. |
| Windows edition | Pro, Enterprise, Education or IoT Enterprise, Windows 10 1709 or later / Windows 11 |
| Enrollment | Intune-enrolled devices (Entra joined, or hybrid joined), or co-managed with the **Endpoint Protection** workload set to Intune |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag |
| Firewall | Windows Defender Firewall must be on |
| Application | The new Teams client (`MSTeams` MSIX package), if you add the package family name |
| Network | Outbound access to the Microsoft 365 / Teams endpoints (UDP 3478–3481 and TCP 443) must also be allowed on your network firewalls and proxies. This rule only covers inbound traffic on the device. |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Firewall > Create Policy**.
3. Set **Platform** to **Windows** and **Profile** to **Windows Firewall Rules**, then select **Create**.
4. **Basics**:
   - **Name**: `WIN-CFG-Firewall Rule - Microsoft Teams`
   - **Description**: Allow inbound UDP for Microsoft Teams media on all networks.
   - Select **Next**.
5. **Configuration settings**: select **+ Add** to add a rule, then **Edit rule** and set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Enabled | **Enabled** |
   | 2 | Name | `Microsoft Teams` |
   | 3 | Direction | **The rule applies to inbound traffic.** |
   | 4 | Action | **Allow** |
   | 5 | Protocol | `17` |
   | 6 | Local Port Ranges | Leave blank. Optionally add your Teams media port range. |
   | 7 | Remote Address Ranges | Leave blank (any) |
   | 8 | Interface Types | **All** (only All) |
   | 9 | Network Types | **FW_PROFILE_TYPE_ALL** |
   | 10 | *(Recommended)* Package Family Name | `MSTeams_8wekyb3d8bbwe` |

   Leave the other settings **Not configured**. Select **Save**, then **Next**.
6. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
7. **Assignments**: under **Included groups**, add the Windows device group. Select **Next**.
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
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'WIN-CFG-Firewall Rule - Microsoft Teams'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Firewall-Rule-Microsoft-Teams.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Firewall-Rule-Microsoft-Teams.json" -Raw
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

- **Assign to device groups.** Firewall rules are device-scoped.
- **Conflicting rules are both delivered.** Windows Firewall Rules profiles merge on the device. If another profile **blocks** Teams and this one allows it, both reach the device, and the **block wins** (explicit block rules beat allow rules). Microsoft's own example of this conflict is *Teams.exe*.
- **Block rules left by the user prompt.** Devices where a user already answered the Teams firewall prompt may have local **block** rules for Teams. Those beat this allow rule. Remove them (see Troubleshooting).
- **Other firewall policies.**
  - **Shielded mode** (in a Windows Firewall profile policy or the security baseline) blocks all inbound traffic and overrides this rule.
  - Turning off **local rule merging** doesn't affect Intune-delivered rules, but it does stop local block rules from applying.
- **Limits.** Each Windows Firewall Rules profile holds up to 150 rules, and **if one rule fails, the whole profile fails**. Keeping Teams in its own profile, separate from [Echo-PAC](../Firewall%20Rule%20Echo%20PAC%20Loader) (whose file path still needs fixing), means a problem with one rule doesn't break the other.
- **GPO.** Firewall rules from GPO and from MDM are both enforced, so *MDMWinsOverGP* doesn't apply. Check that no GPO blocks Teams.

## Validation

**In the admin center**
- Open **Endpoint security > Firewall >** the policy **> Device status / Per-setting status**. It should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Confirm the rule arrived:
   ```powershell
   $r = Get-NetFirewallRule -PolicyStore ActiveStore -DisplayName "Microsoft Teams"
   $r | Select-Object DisplayName, Enabled, Direction, Action, Profile, PolicyStoreSourceType
   $r | Get-NetFirewallPortFilter          # Protocol UDP, LocalPort Any
   $r | Get-NetFirewallAddressFilter       # RemoteAddress Any
   $r | Get-NetFirewallInterfaceTypeFilter # InterfaceType Any
   ```
   Expect `Enabled True`, `Direction Inbound`, `Action Allow`, `Profile Any`, and `PolicyStoreSourceType MDM`.
3. Make a Teams call and check that no firewall prompt appears. Ask the user to check call quality (**More > Settings > Device settings > Make a test call**). Admins can also check the **Call Quality Dashboard** for UDP versus TCP media.
4. For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also use `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Home edition, or Windows older than 1709 | Upgrade the edition or version. |
| **Error**: LocalPortRanges "The parameter is incorrect" | A port range is descending, outside 0–65535, or set without protocol 6 or 17 | Use ascending ranges such as `50000-50059` and keep Protocol `17`. |
| **Error**: InterfaceTypes "The parameter is incorrect" | **All** was selected together with other interface types | Select only **All**. |
| **Error** (whole profile fails) | Any one rule in the profile is invalid | Fix the bad rule. Keep this rule in its own profile. |
| Teams still shows a firewall prompt, or media falls back to TCP | Local **block** rules from an earlier prompt, or an explicit block rule in another policy | Remove them: `Get-NetFirewallRule -PolicyStore PersistentStore -Action Block | Where-Object DisplayName -like "*Teams*" | Remove-NetFirewallRule` (run as admin). Check other firewall policies. |
| Rule isn't present | Assigned to a user group, or the device isn't in the group | Assign to a **device** group. |

No restart is needed; Windows Firewall applies the rule as soon as it arrives.

## Rollback

- **Unassign or delete** the policy. Intune removes the rule from the device's MDM store and inbound UDP **reverts** to the default block. It isn't tattooed.
- To disable the rule without deleting the policy, edit the rule and set **Enabled** to **Disabled**.
- After rollback, Teams may prompt users again. Non-admin users will get block rules.

## References

- [Firewall policy for endpoint security in Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/firewall)
- [Firewall policy settings for endpoint security](https://learn.microsoft.com/intune/device-configuration/endpoint-security/ref-firewall-settings)
- [Firewall CSP](https://learn.microsoft.com/windows/client-management/mdm/firewall-csp)
- [Windows Firewall rules (application rules, precedence, user prompt)](https://learn.microsoft.com/windows/security/operating-system-security/network-security/windows-firewall/rules)
- [Prevent antivirus and DLP tools from blocking Teams (new Teams install location)](https://learn.microsoft.com/troubleshoot/microsoftteams/teams-administration/include-exclude-teams-from-antivirus-dlp#new-teams)
- [Microsoft 365 URLs and IP address ranges – Teams](https://learn.microsoft.com/microsoft-365/enterprise/urls-and-ip-address-ranges#microsoft-teams)
