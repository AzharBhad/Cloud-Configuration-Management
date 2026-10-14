# LAPS Profile

Configures **Windows LAPS** on Windows 10 and 11 to randomize, rotate and back up the built-in local Administrator password to **Microsoft Entra ID**. Delivered as an Intune **settings catalog** policy (as in the screenshot).

## Purpose

Every Windows device has a built-in local Administrator account. With a shared or static password, compromising one device compromises them all (pass-the-hash, lateral movement).

Windows LAPS gives each device a **unique random password**. It's **backed up to Entra ID**, where you can read it with RBAC in Intune and Entra, **rotated every 30 days**, and **rotated again after use**.

This policy manages the account that [Enable Local Administrator Account](../Enable%20Local%20Administrator%20Account) turns on. Deploy both together.

> [!TIP]
> Microsoft's recommended path for LAPS is **Endpoint security > Account protection > Local admin password solution (Windows LAPS)**. It uses the same LAPS CSP settings. The screenshot shows this policy as **Settings catalog**, so it's documented that way. Either works, but use **only one** LAPS policy per device.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - LAPS Profile` (as shown in the screenshot) |
| Description | Windows LAPS: backup to Entra ID, 30-day rotation, 14-character complex password, reset and sign out 8 hours after use. |
| Platform | Windows 10 and later |
| Profile type | Settings catalog (category **LAPS**) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `LAPS-Profile.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: the same devices as *Enable Local Administrator Account*. Don't use user groups (LAPS settings would change with each sign-in). |
| Supported OS | Windows 11 22H2/21H2 or Windows 10 22H2/21H2/1809 with the **April 2023** security update or later |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### LAPS

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Backup Directory | **Backup the password to Azure AD only** | `./Device/Vendor/MSFT/LAPS/Policies/BackupDirectory` = 1 | Required minimum; stores the password in Microsoft Entra ID. |
| Password Age Days | **30** | `./Device/Vendor/MSFT/LAPS/Policies/PasswordAgeDays` = 30 | Rotation interval (minimum 7 for Entra ID, maximum 365). |
| Password Complexity | **Large letters + small letters + numbers + special characters** | `./Device/Vendor/MSFT/LAPS/Policies/PasswordComplexity` = 4 | Microsoft-recommended value. |
| Password Length | **14** | `./Device/Vendor/MSFT/LAPS/Policies/PasswordLength` = 14 | Range 8–64. 14 is the default. |
| Administrator Account Name | *Not configured* | `./Device/Vendor/MSFT/LAPS/Policies/AdministratorAccountName` | Manages the **built-in** Administrator, found by its well-known RID even if renamed. |
| Post Authentication Actions | **Reset password and logoff the managed account** | `./Device/Vendor/MSFT/LAPS/Policies/PostAuthenticationActions` = 3 | After the grace period, rotates the password and signs the account out. |
| Post Authentication Reset Delay | **8** hours | `./Device/Vendor/MSFT/LAPS/Policies/PostAuthenticationResetDelay` = 8 | Grace period after the password is used (default 24). |

Also turn on **Microsoft Entra admin center > Devices > Device settings > Enable Microsoft Entra Local Administrator Password Solution (LAPS) = Yes**. Without it, backup to Entra ID fails.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1. Windows LAPS is built into Windows. |
| Windows | Supported build with the April 2023 update or later (see Supported OS) |
| Entra | Microsoft Entra LAPS enabled in device settings |
| Account | Built-in Administrator enabled ([Enable Local Administrator Account](../Enable%20Local%20Administrator%20Account)); LAPS doesn't create or enable it |
| Role | Policy and Profile Manager or Endpoint Security Manager. Viewing passwords needs *Read local admin password* permission. |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Settings catalog**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - LAPS Profile`
   - **Description**: Windows LAPS: backup to Entra ID, 30-day rotation, 14-character complex password, reset and sign out 8 hours after use.
   - Select **Next**.
4. **Configuration settings**: select **Add settings**, open the **LAPS** category, add the settings below, then set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Backup Directory | Backup the password to Azure AD only |
   | 2 | Password Age Days | 30 |
   | 3 | Password Complexity | Large letters + small letters + numbers + special characters |
   | 4 | Password Length | 14 |
   | 5 | Post Authentication Actions | Reset password and logoff the managed account |
   | 6 | Post Authentication Reset Delay | 8 |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add the corporate Windows **device** groups that get *Enable Local Administrator Account*. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - LAPS Profile'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\LAPS-Profile.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\LAPS-Profile.json" -Raw
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

- **Exactly one LAPS policy per device.** The LAPS CSP allows a single configuration. A second policy (Endpoint security LAPS or settings catalog) causes processing failures and can stop the backup.
- LAPS CSP settings **override** LAPS GPOs and legacy Microsoft LAPS.
- The [Enable Local Administrator Account](../Enable%20Local%20Administrator%20Account) policy is complementary (it enables the account) and doesn't conflict.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Check **Devices >** a device **> Local admin password** for the account, password, last rotation and next rotation. Check **Reports > Account protection** (LAPS reports) too.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Run `Get-LapsDiagnostics`, or check Event Viewer under *Applications and Services Logs > Microsoft > Windows > LAPS > Operational*. Event **10020** means the password was updated and backed up to Entra ID.
3. To test rotation, use **Rotate local admin password** in Intune (device action), then check the new *last rotation* time.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | Two LAPS policies assigned to the device | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Entra LAPS not enabled, unsupported Windows build, or PasswordAgeDays below 7 with Entra backup | Fix the value and re-sync. |
| No password shown in Intune | Entra LAPS disabled, device not Entra/hybrid joined, or account disabled | Enable Entra LAPS. Enable the Administrator account. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

No restart is needed; LAPS processes policy on its next cycle (about every hour).

## Rollback

- **Unassign or delete** the policy. LAPS stops managing the password. The **last password stays set** on the device (it isn't reset to an old value) and remains in Entra ID until the device object is deleted.
- Before removing LAPS, disable the Administrator account, or plan another way to manage it.

## References

- [Microsoft Intune support for Windows LAPS](https://learn.microsoft.com/intune/device-security/laps/overview)
- [Deploy Windows LAPS policy with Intune](https://learn.microsoft.com/intune/device-security/laps/deploy-policy)
- [LAPS CSP](https://learn.microsoft.com/windows/client-management/mdm/laps-csp)
- [Windows LAPS with Microsoft Entra ID](https://learn.microsoft.com/windows-server/identity/laps/laps-scenarios-azure-active-directory)
- [Configure policy settings for Windows LAPS](https://learn.microsoft.com/windows-server/identity/laps/laps-management-policy-settings)
