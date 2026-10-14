# User Profile Settings

Protects and manages Windows **user profiles** on Windows 10 and 11: OneDrive Known Folder Move (Desktop, Documents and Pictures backed up to OneDrive), silent OneDrive sign-in, Files On-Demand, and automatic cleanup of stale local profiles. Delivered as an Intune **settings catalog** policy.

## Purpose

The screenshot shows only the policy name, so this is an **enterprise interpretation** of *User Profile Settings*. It covers the two things that matter most for user profiles on cloud-managed Windows devices:

1. **Profile data protection.** OneDrive **Known Folder Move** silently redirects each user's Desktop, Documents and Pictures to their work OneDrive.
   - Profile data is backed up, roams to new devices (PC refresh, Autopilot reset) and is protected against ransomware through OneDrive version history.
   - Users can't move the folders back.
   - **Files On-Demand** keeps disk usage low, and only the **corporate tenant** can sync.
2. **Profile hygiene.** Local profiles not used for **90 days** are deleted at restart, which frees disk space and removes data left by former users on shared or reassigned devices.

These are the OneDrive settings Microsoft recommends for Intune-managed devices.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - User Profile Settings` (as shown in the screenshot) |
| Description | OneDrive Known Folder Move, silent sign-in, Files On-Demand, block personal OneDrive, and clean up user profiles unused for 90 days. |
| Platform | Windows 10 and later |
| Profile type | Settings catalog |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `User-Profile-Settings.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: corporate Windows devices. Exclude **VMs / Windows 365 / Azure Virtual Desktop** from the profile-cleanup setting (see the warning below). |
| Supported OS | Windows 10 1709 or later / Windows 11. Profile cleanup through MDM needs Windows 10 2004 with KB5005101 or later. |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### OneDrive

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Silently sign in users to the OneDrive sync app with their Windows credentials | **Enabled** | `SilentAccountConfig` = 1 | Entra-joined users get OneDrive without entering credentials. |
| Silently move Windows known folders to OneDrive | **Enabled** | `KFMSilentOptIn` | Redirects known folders without user interaction. |
|   > Tenant ID (Device) | `<your-tenant-id>` | `KFMSilentOptIn` | **Tenant-specific.** Find it in Microsoft Entra admin center > Overview. |
|   > Desktop / Documents / Pictures (Device) | **True** / **True** / **True** | `KFMSilentOptInDesktop` / `…Documents` / `…Pictures` | All three folders are moved. |
|   > Show notification to users after folders have been redirected (Device) | **No** | `KFMSilentOptInWithNotification` | Silent move. |
| Prevent users from redirecting their Windows known folders to their PC | **Enabled** | `KFMBlockOptOut` = 1 | Users can't stop protecting the folders. |
| Use OneDrive Files On-Demand | **Enabled** | `FilesOnDemandEnabled` = 1 | Files are online-only until opened; saves disk space. |
| Allow syncing OneDrive accounts for only specific organizations | **Enabled**, Tenant ID `<your-tenant-id>` | `AllowTenantList` | Only your tenant's OneDrive and SharePoint can sync (data-exfiltration control). |
| Prevent users from syncing personal OneDrive accounts (User) | **Enabled** | `DisablePersonalSync` = 1 | Blocks personal OneDrive sync on corporate devices. |

### Administrative Templates > System > User Profiles

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Delete user profiles older than a specified number of days on system restart | **Enabled**, **90** days | `./Device/Vendor/MSFT/Policy/Config/ADMX_UserProfiles/CleanupProfiles` | At restart, the User Profile Service deletes local profiles not used in 90 days. Data is safe in OneDrive through Known Folder Move. |

> [!WARNING]
> **Profile cleanup and VMs.** Microsoft advises **not** to use *Delete user profiles older than a specified number of days* on Azure **VMs**, because it can make them unresponsive. Exclude Windows 365 Cloud PCs and AVD session hosts with a filter, for example `(device.model -contains "Cloud PC") or (device.model -contains "Windows 365")`. If Configuration Manager *User Data and Profiles* compliance settings are active, they take precedence and the cleanup policy is ignored.

> [!IMPORTANT]
> Replace both `<your-tenant-id>` values with your Microsoft Entra **tenant ID** (GUID) before deploying. If the Group Policy *Prohibit User from manually redirecting Profile Folders* is enabled anywhere, known folders **won't** move.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1, plus OneDrive for Business (Microsoft 365 / OneDrive Plan 1 or higher) |
| Join type | **Microsoft Entra joined** or hybrid joined, for silent account configuration |
| OneDrive app | Current OneDrive sync app (installed per-machine with Microsoft 365 Apps or Windows) |
| Tenant ID | Your Microsoft Entra tenant ID |
| Role | Policy and Profile Manager or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Settings catalog**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - User Profile Settings`
   - **Description**: OneDrive Known Folder Move, silent sign-in, Files On-Demand, block personal OneDrive, and clean up user profiles unused for 90 days.
   - Select **Next**.
4. **Configuration settings**: select **Add settings**. Add the settings from the **OneDrive** category and from **Administrative Templates > System > User Profiles**, then set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Silently sign in users to the OneDrive sync app with their Windows credentials | Enabled |
   | 2 | Silently move Windows known folders to OneDrive (the setting with 5 sub-settings) | Enabled; Tenant ID; Desktop/Documents/Pictures True; Show notification No |
   | 3 | Prevent users from redirecting their Windows known folders to their PC | Enabled |
   | 4 | Use OneDrive Files On-Demand | Enabled |
   | 5 | Allow syncing OneDrive accounts for only specific organizations | Enabled; Tenant ID |
   | 6 | Prevent users from syncing personal OneDrive accounts (User) | Enabled |
   | 7 | Delete user profiles older than a specified number of days on system restart | Enabled; 90 |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add corporate Windows **device** groups. Add a **filter** to exclude Cloud PCs and VMs (see the warning above). Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - User Profile Settings'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\User-Profile-Settings.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\User-Profile-Settings.json" -Raw
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

- **Assign to device groups.** The *(User)* OneDrive setting still applies through device assignment, to every user who signs in.
- **Other OneDrive policies.** Configure each OneDrive setting in only **one** policy. If you add a separate OneDrive policy later, move these settings there.
- **GPO.** On hybrid devices, remove the equivalent OneDrive and Folder Redirection GPOs. **Folder Redirection GPOs and Known Folder Move must not target the same folders.** Use **Group Policy analytics** to migrate.
- **Configuration Manager** *User Data and Profiles* settings override the profile cleanup policy.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- In the **Microsoft 365 apps admin center > Health > OneDrive sync**, check Known Folder Move status by device.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Check the OneDrive policy values in `HKLM\SOFTWARE\Policies\Microsoft\OneDrive`: `SilentAccountConfig=1`, `KFMSilentOptIn=<tenant-id>`, `KFMBlockOptOut=1`, `FilesOnDemandEnabled=1`.
3. In File Explorer, check that Desktop, Documents and Pictures point to `C:\Users\<user>\OneDrive - <Org>\…`. In OneDrive **Settings > Sync and backup > Manage back up**, all three folders show as backed up.
4. For profile cleanup, check `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` has `CleanupProfiles = 90`. Stale profiles are removed at the **next restart**.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | Another OneDrive or ADMX policy sets the same value | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid tenant ID | Fix the value and re-sync. |
| Known folders don't move | Folder Redirection GPO, *Prohibit User from manually redirecting Profile Folders* enabled, or OneDrive not signed in yet | Remove the conflicting GPO. Confirm silent sign-in works. |
| Old profiles not deleted | No restart yet, ConfigMgr *User Data and Profiles* active, or the profile was used recently | Restart the device. Disable the ConfigMgr setting. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

OneDrive settings apply the next time OneDrive starts. Profile cleanup runs at the **next restart**.

## Rollback

- **Unassign or delete** the policy. OneDrive policy values are removed; **folders already moved stay in OneDrive**, and users can then move them back.
- To move folders back to the PC centrally, deploy *Prevent users from moving their Windows known folders to OneDrive* with the option to redirect them back (`KFMBlockOptIn = 2`).
- Profile cleanup stops when the policy is removed. **Deleted profiles can't be recovered** from the device; restore files from OneDrive.

## References

- [Use OneDrive policies to control sync settings](https://learn.microsoft.com/sharepoint/use-group-policy)
- [Redirect and move Windows known folders to OneDrive](https://learn.microsoft.com/sharepoint/redirect-known-folders)
- [Silently configure user accounts](https://learn.microsoft.com/sharepoint/use-silent-account-configuration)
- [Policy CSP – ADMX_UserProfiles (CleanupProfiles)](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-userprofiles#cleanupprofiles)
- [User profiles older than a specified number of days aren't deleted](https://learn.microsoft.com/troubleshoot/windows-server/group-policy/old-user-profiles-not-deleted-system-restart)
- [Use the settings catalog](https://learn.microsoft.com/intune/device-configuration/settings-catalog/)
