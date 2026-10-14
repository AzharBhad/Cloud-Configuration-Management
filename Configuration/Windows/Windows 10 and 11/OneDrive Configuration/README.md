# OneDrive Configuration

Microsoft-recommended **OneDrive sync app** configuration for Windows 10 and 11: silent sign-in, Known Folder Move (Desktop, Documents and Pictures), Files On-Demand, tenant-only sync and disk-space protection. Delivered as an Intune **settings catalog** policy.

## Purpose

OneDrive is where user data lives on cloud-managed Windows devices. This policy:
- **signs users in silently**;
- **moves Desktop, Documents and Pictures** into OneDrive without prompts, and stops users moving them back;
- keeps disk usage low with **Files On-Demand** and online-only team sites;
- allows sync only with **your tenant** and blocks personal OneDrive;
- warns users, then blocks downloads, when the disk is nearly full.

As a result, user data is backed up and protected by OneDrive version history (ransomware recovery), and it roams to replacement devices.

> [!IMPORTANT]
> **The screenshot shows `Windows - OneDrive Configuration` twice.** Two OneDrive policies on the same devices **conflict** on every setting they share. Keep **one** (this configuration), and delete or unassign the duplicate in Intune.
>
> These OneDrive settings were previously in [User Profile Settings](../User%20Profile%20Settings). They've been **moved here** so each setting is configured only once.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - OneDrive Configuration` (as shown in the screenshot) |
| Description | OneDrive: silent sign-in, silent Known Folder Move, block opt-out, Files On-Demand, tenant allow list, block personal sync, team sites online-only, low-disk-space protection. |
| Platform | Windows 10 and later |
| Profile type | Settings catalog |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `OneDrive-Configuration.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: corporate Windows devices (the *(User)* setting still applies to every user on the device). |
| Supported OS | Windows 10 1709 or later / Windows 11, current OneDrive sync app |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### OneDrive

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Silently sign in users to the OneDrive sync app with their Windows credentials | **Enabled** | `SilentAccountConfig` = 1 | Users on Entra-joined devices get OneDrive without entering credentials. |
| Silently move Windows known folders to OneDrive | **Enabled**: Tenant ID `<your-tenant-id>`; Desktop **True**, Documents **True**, Pictures **True**; Show notification **No** | `KFMSilentOptIn` (+ `KFMSilentOptInDesktop/Documents/Pictures`, `KFMSilentOptInWithNotification`) | Redirects the known folders silently. |
| Prevent users from redirecting their Windows known folders to their PC | **Enabled** | `KFMBlockOptOut` = 1 | Users can't stop protecting the folders. |
| Use OneDrive Files On-Demand | **Enabled** | `FilesOnDemandEnabled` = 1 | Files are online-only until opened. |
| Convert synced team site files to online-only files | **Enabled** | `DehydrateSyncedTeamSites` | Synced SharePoint libraries don't fill the disk. |
| Allow syncing OneDrive accounts for only specific organizations | **Enabled**: Tenant ID `<your-tenant-id>` | `AllowTenantList` | Only your tenant can sync (data-exfiltration control). |
| Prevent users from syncing personal OneDrive accounts (User) | **Enabled** | `DisablePersonalSync` = 1 | Blocks personal OneDrive on corporate devices. |
| Warn users who are low on disk space | **Enabled**: **2048** MB | `WarningMinDiskSpaceLimitInMB` | Warns users when a download would leave less than 2 GB free. |
| Block file downloads when users are low on disk space | **Enabled**: **1024** MB | `MinDiskSpaceLimitInMB` | Stops automatic downloads when less than 1 GB would remain. |

> [!IMPORTANT]
> Replace both `<your-tenant-id>` values with your Microsoft Entra **tenant ID** (GUID, from Microsoft Entra admin center > Overview). If the GPO *Prohibit User from manually redirecting Profile Folders* is enabled, known folders **won't** move. Folder Redirection GPOs must not target the same folders.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1, plus OneDrive for Business (Microsoft 365 / OneDrive Plan 1 or higher) |
| Join type | Microsoft Entra joined or hybrid joined, for silent sign-in |
| OneDrive app | Current OneDrive sync app, installed per machine |
| Tenant ID | Your Microsoft Entra tenant ID |
| Role | Policy and Profile Manager or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Settings catalog**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - OneDrive Configuration`
   - **Description**: OneDrive: silent sign-in, silent Known Folder Move, block opt-out, Files On-Demand, tenant allow list, block personal sync, team sites online-only, low-disk-space protection.
   - Select **Next**.
4. **Configuration settings**: select **Add settings**, open the **OneDrive** category, add the settings below (for Known Folder Move, pick the setting with **5 sub-settings**), then set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Silently sign in users to the OneDrive sync app with their Windows credentials | Enabled |
   | 2 | Silently move Windows known folders to OneDrive | Enabled; Tenant ID; Desktop/Documents/Pictures True; Show notification No |
   | 3 | Prevent users from redirecting their Windows known folders to their PC | Enabled |
   | 4 | Use OneDrive Files On-Demand | Enabled |
   | 5 | Convert synced team site files to online-only files | Enabled |
   | 6 | Allow syncing OneDrive accounts for only specific organizations | Enabled; Tenant ID |
   | 7 | Prevent users from syncing personal OneDrive accounts (User) | Enabled |
   | 8 | Warn users who are low on disk space | Enabled; 2048 |
   | 9 | Block file downloads when users are low on disk space | Enabled; 1024 |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add corporate Windows **device** groups. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - OneDrive Configuration'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\OneDrive-Configuration.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\OneDrive-Configuration.json" -Raw
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

- **Only one OneDrive policy.** Delete or unassign the **duplicate** `Windows - OneDrive Configuration` in your tenant.
- [User Profile Settings](../User%20Profile%20Settings) no longer contains OneDrive settings, so there's no overlap.
- **GPO.** On hybrid devices, remove OneDrive and Folder Redirection GPOs for the same folders. Use **Group Policy analytics** to migrate.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Check the **Microsoft 365 apps admin center > Health > OneDrive sync** for Known Folder Move and sync health.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Check `HKLM\SOFTWARE\Policies\Microsoft\OneDrive`: `SilentAccountConfig=1`, `KFMSilentOptIn=<tenant-id>`, `KFMBlockOptOut=1`, `FilesOnDemandEnabled=1`, `AllowTenantList` contains your tenant ID.
3. Desktop, Documents and Pictures should point to `C:\Users\<user>\OneDrive - <Org>\…`. **OneDrive > Settings > Sync and backup > Manage back up** shows all three as backed up.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | The duplicate OneDrive policy, or another policy with OneDrive settings | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid tenant ID | Fix the value and re-sync. |
| Known folders don't move | Folder Redirection GPO, *Prohibit User from manually redirecting Profile Folders*, or OneDrive not signed in | Remove the GPO. Check silent sign-in. |
| Users can't sync a partner's shared library | `AllowTenantList` limits sync to your tenant (by design) | Add the partner tenant ID if business-approved. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

Settings apply the next time the OneDrive sync app starts (sign out and in, or restart OneDrive).

## Rollback

- **Unassign or delete** the policy. OneDrive policy values are removed and the restrictions **revert**. **Folders already moved stay in OneDrive** (not reverted automatically).
- To move folders back to the PC centrally, deploy *Prevent users from moving their Windows known folders to OneDrive* with the redirect-back option (`KFMBlockOptIn = 2`).

## References

- [Use OneDrive policies to control sync settings](https://learn.microsoft.com/sharepoint/use-group-policy)
- [Redirect and move Windows known folders to OneDrive](https://learn.microsoft.com/sharepoint/redirect-known-folders)
- [Silently configure user accounts](https://learn.microsoft.com/sharepoint/use-silent-account-configuration)
- [Recommended OneDrive sync app configuration](https://learn.microsoft.com/sharepoint/ideal-state-configuration)
- [Use the settings catalog](https://learn.microsoft.com/intune/device-configuration/settings-catalog/)
