# Firewall Rule – Echo PAC Loader

A Windows Defender Firewall rule, **Echo-PAC**, that allows inbound traffic for the Echo PAC Loader application on Windows 10 and 11. It's delivered as an Intune **Endpoint security > Firewall > Windows Firewall Rules** policy.

## Purpose

The Windows Firewall blocks unsolicited inbound connections by default. The Echo PAC Loader needs to accept inbound connections, and on managed devices a user without admin rights can't add the exception: the prompt creates a **block** rule instead. Deploying the rule from Intune:

- lets the Echo PAC Loader receive inbound traffic on every network profile (Domain, Private, Public) and every interface type;
- keeps the exception centrally managed and auditable, rather than created by hand on each device;
- keeps working when local rule merging is turned off (*AllowLocalPolicyMerge = false*, a common hardening setting). Rules from Intune still apply then.

> [!WARNING]
> **File path `C:\` is not an application path.** The Firewall CSP `App/FilePath` must be the **full path of an executable**, such as `C:\Windows\System\Notepad.exe`. Wildcards aren't supported.
> - A folder or drive root won't match the Echo PAC Loader process.
> - It may make the rule fail to apply. **If one rule fails, every rule in the same profile fails.**
> - Replace `C:\` with the loader's real executable path, for example `C:\Program Files\<Vendor>\Echo PAC Loader\<EchoPACLoader>.exe`. Confirm the path on a device with `Get-Process <name> | Select-Object Path`.

> [!CAUTION]
> This rule allows **all inbound protocols and ports, from any remote address, on all network profiles including Public**. Once the file path is correct, narrow it if you can:
> - Set **Protocol** (TCP 6 / UDP 17) and **Local port ranges** to the ports the loader actually listens on.
> - Set **Remote address ranges** to the PAC/management server subnet.
> - Consider leaving out the **Public** profile.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `WIN-CFG-Firewall Rule - Echo PAC Loader` |
| Rule name | `Echo-PAC` |
| Platform | Windows (Windows 10, Windows 11 and Windows Server) |
| Profile type | Endpoint security > Firewall > **Windows Firewall Rules** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export; tenants that manage devices through Defender for Endpoint security settings management may show `mdm,microsoftSense`. |
| File | `Firewall-Rule-Echo-PAC-Loader.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin |
| Recommended assignment | A **device** group containing the devices that run the Echo PAC Loader. Firewall rules are device-scoped. |
| Supported OS | Windows 10 1709 or later / Windows 11 (Pro, Enterprise, Education, IoT Enterprise) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the Firewall CSP nodes and values in the tables below. It doesn't publish:
> - the Windows Firewall Rules **template ID**;
> - the settings catalog **definition IDs** for each rule setting.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the rule in the admin center (steps below), then export it with Graph and **replace this JSON with the export**. The export becomes the importable body for other tenants.

## Configuration settings

### Windows Firewall Rule – Echo-PAC

| Setting (admin center name) | Value | Firewall CSP node (`./Vendor/MSFT/Firewall/MdmStore/FirewallRules/{FirewallRuleName}/…`) | What it does / why |
|---|---|---|---|
| Name | `Echo-PAC` | `Name` | Friendly name shown in *Windows Defender Firewall with Advanced Security*. The rule's node name can't contain `/`. |
| Enabled | Enabled | `Enabled` = `1` | Turns the rule on. New rules are enabled by default. |
| Direction | The rule applies to inbound traffic | `Direction` = `IN` | Applies to inbound connections. If not configured, the default is **OUT**. |
| Action | Allow | `Action/Type` = `1` | Allows matching traffic. `0` = Block. |
| Interface Types | All | `InterfaceTypes` = `All` | Allowed values are `RemoteAccess`, `Wireless`, `Lan`, `MBB` and `All`. |
| File Path | `C:\` (as requested; see the warning above) | `App/FilePath` | Full file path of the app the rule applies to, for example `C:\Windows\System\Notepad.exe`. |
| Network Types | FW_PROFILE_TYPE_ALL: This value represents all these network sets and any future network sets | `Profiles` = `0x7FFFFFFF` (2147483647) | All profiles (Domain 0x1, Private 0x2, Public 0x4) and any future ones. If not specified, the default is also All. |

**Not configured** (the rule matches any value): Description, Protocol, Local/Remote port ranges, Local/Remote address ranges, Package family name, Service name, Authorized users (`LocalUserAuthorizedList`), Edge traversal, Policy App ID.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Windows edition | Pro, Enterprise, Education or IoT Enterprise, Windows 10 1709 or later / Windows 11 |
| Enrollment | Intune-enrolled devices (Entra joined, or hybrid joined), or co-managed with the **Endpoint Protection** workload set to Intune. Windows Server needs Defender for Endpoint security settings management. |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag |
| Firewall | Windows Defender Firewall must be on. If it's off, rules aren't enforced. |
| Application | The Echo PAC Loader must be installed at the **exact path** used in the rule |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Firewall > Create Policy**.
3. Set **Platform** to **Windows** and **Profile** to **Windows Firewall Rules**, then select **Create**.
4. **Basics**:
   - **Name**: `WIN-CFG-Firewall Rule - Echo PAC Loader`
   - **Description**: Allow inbound traffic for the Echo PAC Loader on all networks.
   - Select **Next**.
5. **Configuration settings**: select **+ Add** to add a rule, then **Edit rule** and set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Enabled | **Enabled** |
   | 2 | Name | `Echo-PAC` |
   | 3 | Direction | **The rule applies to inbound traffic.** |
   | 4 | Action | **Allow** |
   | 5 | Interface Types | **All** |
   | 6 | File Path | `C:\`. **Recommended:** use the full path to the loader's `.exe` instead. |
   | 7 | Network Types | **FW_PROFILE_TYPE_ALL** |

   Leave the other settings **Not configured**. Select **Save**, then **Next**.
6. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
7. **Assignments**: under **Included groups**, add the device group that has the Echo PAC Loader. Select **Next**.
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
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'WIN-CFG-Firewall Rule - Echo PAC Loader'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Firewall-Rule-Echo-PAC-Loader.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Firewall-Rule-Echo-PAC-Loader.json" -Raw
$policy = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" -Body $body -ContentType "application/json"

# 4. Assign to a device group
$assign = @{
  assignments = @(
    @{ target = @{ "@odata.type" = "#microsoft.graph.groupAssignmentTarget"; groupId = "<echo-pac-device-group-id>" } }
  )
} | ConvertTo-Json -Depth 5
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($policy.id)/assign" -Body $assign -ContentType "application/json"
```

## Assignment & conflict guidance

- **Assign to device groups.** Firewall rules are device-scoped. Target only devices that run the Echo PAC Loader rather than *All devices*, so the inbound exception stays as small as possible.
- **Rules from different policies add up; they don't conflict.** Windows Firewall merges every rule from every source. Precedence works like this:
  - Explicit **block** rules beat allow rules.
  - Allow rules beat the default inbound block.
  - More specific rules win.

  An explicit **block** rule matching the same traffic (from Intune, GPO or a baseline) will override Echo-PAC.
- **Firewall profile policies.** The **Windows Firewall** profile (Endpoint security > Firewall) or the **Windows security baseline** can set *Shielded mode*, which blocks all inbound traffic and overrides this rule. They can also turn off local rule merging; that doesn't affect Intune-delivered rules.
- **Limits.** Each Windows Firewall Rules profile holds up to **150 rules**. If one rule in the profile fails, **every rule in it fails**, and Intune can't tell you which one. Keep Echo-PAC in its own profile until the file path is confirmed.
- **GPO.** Firewall rules from GPO and from MDM are **both** enforced, so *MDMWinsOverGP* doesn't apply. Check that no GPO blocks the loader.
- **Other policies in this repo.** The [Windows security baseline compliance policy](../../../../Compliance/Windows/Windows%2010%20and%2011/Security%20Baseline) needs the firewall to be **on**, which this rule depends on. It doesn't conflict.

## Validation

**In the admin center**
- Open **Endpoint security > Firewall >** the policy **> Device status / Per-setting status**. It should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Optionally, check **Reports > Firewall > MDM Firewall status for Windows 10 and later**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Confirm the rule arrived:
   ```powershell
   Get-NetFirewallRule -PolicyStore ActiveStore -DisplayName "Echo-PAC" |
       Select-Object DisplayName, Enabled, Direction, Action, Profile, PolicyStoreSourceType
   Get-NetFirewallRule -PolicyStore ActiveStore -DisplayName "Echo-PAC" | Get-NetFirewallApplicationFilter
   Get-NetFirewallRule -PolicyStore ActiveStore -DisplayName "Echo-PAC" | Get-NetFirewallInterfaceTypeFilter
   ```
   Expect `Enabled True`, `Direction Inbound`, `Action Allow`, `Profile Any`, and `PolicyStoreSourceType MDM`. The application filter should show the configured program path.
3. In **wf.msc**, open **Inbound Rules**. MDM rules are listed there.
4. Test the connection from a remote host to the loader, for example with `Test-NetConnection <device> -Port <loader-port>`.
5. For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`, or use **Access work or school > Export management log files**.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Home edition, or Windows older than 1709 | Upgrade the edition or version. |
| **Error** (whole profile fails) | Invalid value in a rule, for example a file path that isn't an executable, or a setting the OS doesn't support | Fix the **File Path** (full `.exe` path). Remove unsupported settings. Re-sync. |
| Rule is present but traffic is still blocked | The file path doesn't match the process, an explicit block rule exists, shielded mode is on, or the app uses a different executable or service | Check the real process path. Check `Get-NetFirewallRule -Action Block`. Check the Firewall profile policy. Consider a **Service name** rule. |
| Rule isn't present | Assigned to a user group, or the device isn't in the group | Assign to a **device** group. |
| Works on the corporate network but not elsewhere | The traffic is blocked upstream (VPN or network firewall), not on the device | Check the network path. The rule already covers all profiles. |
| User sees a firewall prompt for the loader | The process path differs from the rule's file path | Fix the file path. Delete the block rules the prompt created. |

No restart is needed; Windows Firewall applies the rule as soon as it arrives.

## Rollback

- **Unassign or delete** the policy. Intune removes the rule from the device's MDM store and the inbound exception **reverts** (it's removed). It isn't tattooed.
- To disable the rule without deleting the policy, edit the rule and set **Enabled** to **Disabled**.
- If traffic still flows after removal, look for a **local** or **GPO** rule that also allows the loader: `Get-NetFirewallRule -DisplayName "*Echo*" -PolicyStore ActiveStore`.

## References

- [Firewall policy for endpoint security in Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/firewall)
- [Firewall policy settings for endpoint security](https://learn.microsoft.com/intune/device-configuration/endpoint-security/ref-firewall-settings)
- [Manage endpoint security policies in Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/manage-policies)
- [Firewall CSP](https://learn.microsoft.com/windows/client-management/mdm/firewall-csp)
- [Windows Firewall rules (rule precedence, application rules)](https://learn.microsoft.com/windows/security/operating-system-security/network-security/windows-firewall/rules)
- [configurationPolicies (beta)](https://learn.microsoft.com/graph/api/resources/intune-deviceconfigv2-devicemanagementconfigurationpolicy?view=graph-rest-beta)
