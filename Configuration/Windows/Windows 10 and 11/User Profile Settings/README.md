# User Profile Settings

Manages local Windows **user profiles** on Windows 10 and 11 by deleting profiles that haven't been used for 90 days when the device restarts. Delivered as an Intune **settings catalog** policy.

## Purpose

Unused local profiles build up on shared, reassigned or long-lived devices. They waste disk space and leave behind data from former users. This policy has the User Profile Service delete profiles that haven't been used for **90 days**, at the next restart.

User data is protected in OneDrive (see [OneDrive Configuration](../OneDrive%20Configuration)), so removing stale local profiles doesn't lose work files.

> [!NOTE]
> This policy previously also held the OneDrive Known Folder Move settings. Those have **moved to [OneDrive Configuration](../OneDrive%20Configuration)** to avoid configuring the same OneDrive settings in two policies. If you created this policy in Intune with the OneDrive settings, remove them from it.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - User Profile Settings` (as shown in the screenshot) |
| Description | Delete user profiles not used for 90 days on system restart. |
| Platform | Windows 10 and later |
| Profile type | Settings catalog |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `User-Profile-Settings.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: corporate **physical** Windows devices. **Exclude VMs, Windows 365 Cloud PCs and AVD** (see the warning below). |
| Supported OS | Windows 10 2004 with KB5005101 or later / Windows 11 (Pro, Enterprise, Education) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Administrative Templates > System > User Profiles

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Delete user profiles older than a specified number of days on system restart | **Enabled**: **90** days | `./Device/Vendor/MSFT/Policy/Config/ADMX_UserProfiles/CleanupProfiles` | At restart, deletes local profiles not used within 90 days (one day = 24 hours after last access). |

> [!WARNING]
> Microsoft advises **not** using this setting on **Azure VMs**, because it can make them unresponsive. Exclude Cloud PCs and AVD with a filter, for example `(device.model -contains "Cloud PC") or (device.model -contains "Windows 365")`. If Configuration Manager *User Data and Profiles* compliance settings are active, they take precedence and this policy is ignored.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Windows | Windows 10 2004 with KB5005101 or later / Windows 11 |
| Data protection | OneDrive Known Folder Move deployed ([OneDrive Configuration](../OneDrive%20Configuration)) |
| Role | Policy and Profile Manager or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Settings catalog**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - User Profile Settings`
   - **Description**: Delete user profiles not used for 90 days on system restart.
   - Select **Next**.
4. **Configuration settings**: select **Add settings**, open **Administrative Templates > System > User Profiles**, then set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Delete user profiles older than a specified number of days on system restart | Enabled; 90 |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add corporate Windows **device** groups, with a **filter** that excludes Cloud PCs and VMs. Select **Next**.
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

- **Assign to device groups.**
- **GPO.** On hybrid devices, a GPO with a different value conflicts. Use **Group Policy analytics** to migrate.
- **Configuration Manager.** *User Data and Profiles* settings override this policy.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Check `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` has `CleanupProfiles = 90`.
3. After the next restart, profiles not used for 90 days are gone from `C:\Users` and from **Settings > Accounts > Other users**.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | Another policy sets the same setting to a different value | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid value | Fix the value and re-sync. |
| Old profiles not deleted | No restart yet, ConfigMgr *User Data and Profiles* active, or the profile was used recently | Restart. Disable the ConfigMgr setting. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

Cleanup runs at the **next restart**.

## Rollback

- **Unassign or delete** the policy. Cleanup stops (the policy value is removed). **Profiles already deleted can't be recovered** from the device; restore files from OneDrive.

## References

- [Policy CSP – ADMX_UserProfiles (CleanupProfiles)](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-userprofiles#cleanupprofiles)
- [User profiles older than a specified number of days aren't deleted](https://learn.microsoft.com/troubleshoot/windows-server/group-policy/old-user-profiles-not-deleted-system-restart)
- [Use the settings catalog](https://learn.microsoft.com/intune/device-configuration/settings-catalog/)
