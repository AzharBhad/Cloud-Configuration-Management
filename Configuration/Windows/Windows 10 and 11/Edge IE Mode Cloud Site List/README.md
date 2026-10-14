# Edge IE Mode Sites – Cloud List

Turns on **Internet Explorer mode** in Microsoft Edge and points it at an **Enterprise Mode site list hosted in the Microsoft 365 admin center** (cloud site list), on Windows 10 and 11. Delivered as an Intune **settings catalog** policy.

## Purpose

Internet Explorer 11 is retired, but some legacy line-of-business sites (ActiveX, document modes, old intranet apps) still need the IE engine. **IE mode** runs those sites inside Edge, based on an **Enterprise Mode site list**.

With **Cloud Site List Management**:
- the site list is stored and edited in the **Microsoft 365 admin center** (**Settings > Org settings > Microsoft Edge site lists**);
- no on-premises web server or file share is needed;
- changes are versioned and audited.

Edge downloads the list when the user is signed in with their work account, and refreshes it every 120 minutes by default.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - Edge IE Mode Sites - Cloud List` (as shown in the screenshot) |
| Description | Enable Edge IE mode and use the Microsoft 365 admin center cloud site list; report user and neutral sites back to the admin center. |
| Platform | Windows 10 and later |
| Profile type | Settings catalog |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `Edge-IE-Mode-Cloud-Site-List.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: devices whose users need legacy sites. Different device groups can get different lists (one policy per list). |
| Supported OS | Windows 10 / 11 with Microsoft Edge **93** or later (cloud site list). User reporting needs Edge 99 or later. |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Microsoft Edge

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Configure Internet Explorer integration | **Enabled: Internet Explorer mode** | `InternetExplorerIntegrationLevel` = IEMode | Turns on IE mode. Required for any site list to apply. |
| Configure the Enterprise Mode Cloud Site List | **Enabled**: `<site-list-id>` | `InternetExplorerIntegrationCloudSiteList` | The **Site list ID** copied from Microsoft 365 admin center > Microsoft Edge site lists. Takes precedence over the on-premises `InternetExplorerIntegrationSiteList`. |
| Configure reporting of IE Mode user list entries to the M365 Admin Center Site Lists app | **Enabled** | `InternetExplorerIntegrationCloudUserSitesReporting` | Sends sites that users add to their local IE mode list to the admin center, so you can find gaps in the list. |
| Configure reporting of potentially misconfigured neutral site URLs to the M365 Admin Center Site Lists app | **Enabled** | `InternetExplorerIntegrationCloudNeutralSitesReporting` | Reports likely misconfigured neutral sites (for example authentication servers). |

**Create the list first:** Microsoft 365 admin center > **Settings > Org settings > Microsoft Edge site lists** > create or import the XML > **Publish** > copy the **Site list ID**. This needs the **Edge Administrator** (or Global Administrator) role.

> [!NOTE]
> Users must be **signed in to Edge with their work account** for the cloud list to download. The [Edge Configuration](../Edge%20Configuration) policy enables implicit sign-in for this.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1. Cloud site lists are available in worldwide and GCC clouds. |
| Edge | Version 93 or later (99 or later for reporting) |
| Site list | Published in the Microsoft 365 admin center; Site list ID available |
| Identity | Users signed in to Edge with a Microsoft Entra work account |
| Role | Intune: Policy and Profile Manager. Microsoft 365 admin center: **Edge Administrator**. |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Settings catalog**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - Edge IE Mode Sites - Cloud List`
   - **Description**: Enable Edge IE mode and use the Microsoft 365 admin center cloud site list; report user and neutral sites back to the admin center.
   - Select **Next**.
4. **Configuration settings**: select **Add settings**, search **Internet Explorer**, add the four **Microsoft Edge** device settings below, then set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Configure Internet Explorer integration | Enabled > Internet Explorer mode |
   | 2 | Configure the Enterprise Mode Cloud Site List | Enabled > paste the Site list ID |
   | 3 | Configure reporting of IE Mode user list entries to the M365 Admin Center Site Lists app | Enabled |
   | 4 | Configure reporting of potentially misconfigured neutral site URLs to the M365 Admin Center Site Lists app | Enabled |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add the **device** group(s) that need this site list. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - Edge IE Mode Sites - Cloud List'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Edge-IE-Mode-Cloud-Site-List.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Edge-IE-Mode-Cloud-Site-List.json" -Raw
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

- **One site list per device.** Don't also set `InternetExplorerIntegrationSiteList` (on-premises XML), or two cloud lists, on the same devices. The cloud list takes precedence, and two cloud-list policies conflict.
- **Edge security baseline / other Edge policies.** Keep IE integration settings only in this policy.
- **GPO.** On hybrid devices, remove the IE mode GPO settings (*Configure Internet Explorer integration* / *Configure the Enterprise Mode Site List*).
- The Windows **Use the Enterprise mode IE website list** setting is also overridden by the cloud list.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Open `edge://compat/enterprise`. It should show the **cloud site list** with its version, and you can select **Force update**. `edge://policy` should show the four policies with **Status OK**.
3. Browse to a listed site. It should open with the **IE mode** icon in the address bar.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | Another policy sets IE integration or a different site list | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid value | Fix the value and re-sync. |
| Site list not downloaded | User not signed in to Edge, or the list isn't published | Sign in with the work account. Publish the list. Use **Force update** on `edge://compat/enterprise`. |
| Sites don't open in IE mode right after deployment | Edge needs a restart and the list caches for about 60 seconds | Restart Edge and wait, or force update. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

The cloud site list policy **needs an Edge restart** (no dynamic refresh).

## Rollback

- **Unassign or delete** the policy. IE mode and the cloud list are removed and sites open in normal Edge mode. It isn't tattooed.
- Keep the site list in the admin center so you can re-assign it later. You can restore any of the last three published versions.

## References

- [Cloud Site List Management for IE mode](https://learn.microsoft.com/deployedge/edge-ie-mode-cloud-site-list-mgmt)
- [InternetExplorerIntegrationCloudSiteList](https://learn.microsoft.com/deployedge/microsoft-edge-policies/internetexplorerintegrationcloudsitelist)
- [InternetExplorerIntegrationLevel](https://learn.microsoft.com/deployedge/microsoft-edge-policies/internetexplorerintegrationlevel)
- [Microsoft Edge – Policies](https://learn.microsoft.com/deployedge/microsoft-edge-policies)
