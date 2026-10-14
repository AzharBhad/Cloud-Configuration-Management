# Firewall Configuration – Global

Tenant-wide **Windows Defender Firewall** profile settings for Windows 10 and 11: firewall on for Domain, Private and Public, inbound blocked by default, no user prompts, logging of dropped packets, and local rules ignored on public networks. Delivered as an Intune **Endpoint security > Firewall > Windows Firewall** policy.

## Purpose

Host firewalls are a core Zero Trust control: every device protects itself, wherever it connects. This **global** policy sets the firewall **profiles**. The app-specific **rules** are in the separate rule policies: [Echo PAC Loader](../Firewall%20Rule%20Echo%20PAC%20Loader), [Microsoft Teams](../Firewall%20Rule%20Microsoft%20Teams), [FedEx](../Firewall%20Rules%20FedEx) and [PC Refresh Tool](../Firewall%20Rule%20PC%20Refresh%20Tool).

It also makes devices pass the **firewall** requirement in your Windows compliance policies.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Firewall Configuration - Global` (as shown in the screenshot) |
| Description | Windows Firewall on for all profiles; inbound block / outbound allow; no notifications; drop logging; local rule merge off on Public. |
| Platform | Windows 10 and later |
| Profile type | Endpoint security > Firewall > **Windows Firewall** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. Tenants that manage devices through Defender for Endpoint security settings management show `mdm,microsoftSense`. |
| File | `Firewall-Configuration-Global.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: all corporate Windows devices. |
| Supported OS | Windows 10 1709 or later / Windows 11 (Pro, Enterprise, Education) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the **Windows Firewall template ID** or the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Firewall (per profile)

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Enable Domain Network Firewall | **True** | `./Vendor/MSFT/Firewall/MdmStore/DomainProfile/EnableFirewall` | Firewall on. |
| Default Inbound Action for Domain Profile | **Block** | `./Vendor/MSFT/Firewall/MdmStore/DomainProfile/DefaultInboundAction` = 1 | Block unsolicited inbound traffic that doesn't match a rule. |
| Default Outbound Action for Domain Profile | **Allow** | `./Vendor/MSFT/Firewall/MdmStore/DomainProfile/DefaultOutboundAction` = 0 | Normal outbound connectivity. |
| Disable Inbound Notifications (Domain) | **True** | `./Vendor/MSFT/Firewall/MdmStore/DomainProfile/DisableInboundNotifications` | No prompts that lead users to create block or allow rules. |
| Allow Local Policy Merge (Domain) | **True** | `./Vendor/MSFT/Firewall/MdmStore/DomainProfile/AllowLocalPolicyMerge` | Allows local rules created by app installers on trusted networks. |
| Enable Log Dropped Packets (Domain) | **True** | `./Vendor/MSFT/Firewall/MdmStore/DomainProfile/EnableLogDroppedPackets` | Logs blocked traffic for troubleshooting. |
| Log Max File Size (Domain) | **16384** KB | `./Vendor/MSFT/Firewall/MdmStore/DomainProfile/LogMaxFileSize` | 16 MB log. |
| Enable Private Network Firewall | **True** | `./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/EnableFirewall` | Firewall on. |
| Default Inbound Action for Private Profile | **Block** | `./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/DefaultInboundAction` = 1 | Block unsolicited inbound traffic that doesn't match a rule. |
| Default Outbound Action for Private Profile | **Allow** | `./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/DefaultOutboundAction` = 0 | Normal outbound connectivity. |
| Disable Inbound Notifications (Private) | **True** | `./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/DisableInboundNotifications` | No prompts that lead users to create block or allow rules. |
| Allow Local Policy Merge (Private) | **True** | `./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/AllowLocalPolicyMerge` | Public: **ignore local rules** (only Intune and GPO rules apply). Domain/Private: allow installer-created rules. |
| Enable Log Dropped Packets (Private) | **True** | `./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/EnableLogDroppedPackets` | Logs blocked traffic for troubleshooting. |
| Log Max File Size (Private) | **16384** KB | `./Vendor/MSFT/Firewall/MdmStore/PrivateProfile/LogMaxFileSize` | 16 MB log. |
| Enable Public Network Firewall | **True** | `./Vendor/MSFT/Firewall/MdmStore/PublicProfile/EnableFirewall` | Firewall on. |
| Default Inbound Action for Public Profile | **Block** | `./Vendor/MSFT/Firewall/MdmStore/PublicProfile/DefaultInboundAction` = 1 | Block unsolicited inbound traffic that doesn't match a rule. |
| Default Outbound Action for Public Profile | **Allow** | `./Vendor/MSFT/Firewall/MdmStore/PublicProfile/DefaultOutboundAction` = 0 | Normal outbound connectivity. |
| Disable Inbound Notifications (Public) | **True** | `./Vendor/MSFT/Firewall/MdmStore/PublicProfile/DisableInboundNotifications` | No prompts that lead users to create block or allow rules. |
| Allow Local Policy Merge (Public) | **False** | `./Vendor/MSFT/Firewall/MdmStore/PublicProfile/AllowLocalPolicyMerge` | Public: **ignore local rules** (only Intune and GPO rules apply). Domain/Private: allow installer-created rules. |
| Enable Log Dropped Packets (Public) | **True** | `./Vendor/MSFT/Firewall/MdmStore/PublicProfile/EnableLogDroppedPackets` | Logs blocked traffic for troubleshooting. |
| Log Max File Size (Public) | **16384** KB | `./Vendor/MSFT/Firewall/MdmStore/PublicProfile/LogMaxFileSize` | 16 MB log. |

> [!IMPORTANT]
> **Local Policy Merge = False on Public** means rules created **locally** (by installers or users) are **ignored on public networks**. Only rules from Intune and GPO apply there. Any app that needs inbound traffic on public networks must get its rule from Intune, as your Teams and Echo-PAC rules do. Set it to *True* if that's too restrictive. *Shielded mode* is left **Not configured**; it would block all inbound traffic, including your Intune rules.

Log files go to the default path `%systemroot%\system32\LogFiles\Firewall\pfirewall.log`.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Windows | Pro, Enterprise or Education, Windows 10 1709 or later |
| Enrollment | Intune-enrolled, or co-managed with the **Endpoint Protection** workload set to Intune |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Firewall > Create Policy**. Set **Platform** to **Windows** and **Profile** to **Windows Firewall**, then select **Create**.
3. **Basics**:
   - **Name**: `Firewall Configuration - Global`
   - **Description**: Windows Firewall on for all profiles; inbound block / outbound allow; no notifications; drop logging; local rule merge off on Public.
   - Select **Next**.
4. **Configuration settings**: for **each** of Domain, Private and Public, set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Enable Network Firewall | True |
   | 2 | Default Inbound Action | Block |
   | 3 | Default Outbound Action | Allow |
   | 4 | Disable Inbound Notifications | True |
   | 5 | Allow Local Policy Merge | Domain True / Private True / **Public False** |
   | 6 | Enable Log Dropped Packets | True |
   | 7 | Log Max File Size | 16384 |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add all corporate Windows **device** groups. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag and template)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates").value |
    Where-Object displayName -like "*Windows Firewall*" | Select-Object id, displayName, templateFamily, platforms, technologies

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Firewall Configuration - Global'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Firewall-Configuration-Global.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Firewall-Configuration-Global.json" -Raw
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

- **One Windows Firewall *profile* policy per device.** Firewall profile settings from Endpoint protection templates, settings catalog, or the **Windows security baseline** conflict with this policy when values differ.
- **Firewall *rules* policies don't conflict** with this profile policy; they're merged. But **Shielded mode** or a *block all* setting from another source would override them.
- **GPO.** On hybrid devices, GPO firewall settings and rules also apply. Align them, and keep rules in Intune.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Check the profiles:
   ```powershell
   Get-NetFirewallProfile -PolicyStore ActiveStore | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, NotifyOnListen, AllowLocalFirewallRules, LogBlocked, LogMaxSizeKilobytes
   ```
   Expect all three profiles `Enabled = True`, inbound `Block`, outbound `Allow`, and Public `AllowLocalFirewallRules = False`.
3. Check **Windows Security > Firewall & network protection**: "Some settings are managed by your organization".
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | The Windows security baseline or another firewall profile policy | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid value | Fix the value and re-sync. |
| App works on office Wi-Fi but not at home or on public networks | Local rule ignored on Public (merge off) | Deploy an Intune firewall rule for the app, or set Public merge to True. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

No restart is needed.

## Rollback

- **Unassign or delete** the policy. Profile settings **revert** to Windows defaults (firewall on, inbound block, notifications on, local merge on). They aren't tattooed.

## References

- [Firewall policy for endpoint security in Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/firewall)
- [Firewall policy settings](https://learn.microsoft.com/intune/device-configuration/endpoint-security/ref-firewall-settings)
- [Firewall CSP](https://learn.microsoft.com/windows/client-management/mdm/firewall-csp)
- [Windows Firewall rules (local policy merge)](https://learn.microsoft.com/windows/security/operating-system-security/network-security/windows-firewall/rules)
