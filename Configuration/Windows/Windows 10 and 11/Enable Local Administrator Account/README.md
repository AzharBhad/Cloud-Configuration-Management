# Enable Local Administrator Account

Enables the built-in local **Administrator** account on Windows 10 and 11, so Windows LAPS can manage it for break-glass and device recovery. Delivered as an Intune **settings catalog** policy.

## Purpose

The built-in Administrator account (well-known SID ending **-500**) is disabled by default. Enterprises often need a local admin account for **troubleshooting, help-desk support and device recovery** when a device can't reach Microsoft Entra ID.

Microsoft's guidance: if you enable the built-in administrator account, **secure its password with Windows LAPS**. Windows LAPS doesn't enable or create accounts itself (unless you use automatic account management on Windows 11 24H2), so this policy enables the account and a separate **LAPS policy** randomizes, rotates and backs up its password to Microsoft Entra ID.

> [!WARNING]
> **Never enable this account without Windows LAPS.** An enabled built-in admin with a shared or static password is a classic pass-the-hash and lateral-movement target. Deploy the LAPS policy **at the same time**, to the same devices.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - Enable Local Administrator Account` (as shown in the screenshot) |
| Description | Enable the built-in local Administrator account (managed by Windows LAPS). |
| Platform | Windows 10 and later |
| Profile type | Settings catalog |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `Enable-Local-Administrator-Account.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: the same devices that get your **Windows LAPS** policy (Endpoint security > Account protection). |
| Supported OS | Windows 10 1709 or later / Windows 11 (Pro, Enterprise, Education) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Local Policies Security Options

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Accounts Enable Administrator Account Status | **Enable** | `./Device/Vendor/MSFT/Policy/Config/LocalPoliciesSecurityOptions/Accounts_EnableAdministratorAccountStatus` = `1` | Enables the built-in local Administrator account (default `0` = disabled). LAPS manages the account through its well-known RID, so it keeps working even if the account is renamed. |

**Companion policy (required, not part of this file): Endpoint security > Account protection > Local admin password solution (Windows LAPS).** Recommended values:

| LAPS setting | Value | CSP |
|---|---|---|
| Backup Directory | Backup the password to Azure AD only | `LAPS/Policies/BackupDirectory` = `1` |
| Password Age Days | 30 | `PasswordAgeDays` |
| Password Complexity | Large + small letters + numbers + special characters | `PasswordComplexity` |
| Password Length | 14 or more | `PasswordLength` |
| Administrator Account Name | *Not configured* (manages the built-in account by RID) | `AdministratorAccountName` |
| Post-authentication actions | Reset password and log off the managed account | `PostAuthenticationActions` |
| Post-authentication reset delay | 8 hours (or less) | `PostAuthenticationResetDelay` |

Also turn on **Enable Microsoft Entra Local Administrator Password Solution (LAPS)** under **Microsoft Entra admin center > Devices > Device settings**.

**Optional hardening:** *Accounts Rename Administrator Account* (`Accounts_RenameAdministratorAccount`) makes the account name harder to guess. LAPS still finds the account by RID.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1. Windows LAPS is built into Windows; Microsoft Entra ID P1 isn't required for LAPS backup. |
| Windows | For LAPS: Windows 11 22H2/21H2 or Windows 10 22H2 with the **April 2023** security update or later |
| Microsoft Entra | **Enable Microsoft Entra LAPS** turned on in device settings |
| Companion policy | A **Windows LAPS** policy assigned to the same devices (see above) |
| Role | Policy and Profile Manager or Intune Administrator. Viewing LAPS passwords needs the *Read local admin password* permission (Cloud Device Administrator / custom role). |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Settings catalog**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - Enable Local Administrator Account`
   - **Description**: Enable the built-in local Administrator account (managed by Windows LAPS).
   - Select **Next**.
4. **Configuration settings**: select **Add settings**, search for **Administrator account status**, and under **Local Policies Security Options** select **Accounts Enable Administrator Account Status**. Then set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Accounts Enable Administrator Account Status | **Enable** |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add the Windows **device** group that also gets the Windows LAPS policy. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - Enable Local Administrator Account'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Enable-Local-Administrator-Account.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Enable-Local-Administrator-Account.json" -Raw
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
- **Security baselines.** The **Windows security baseline** and many CIS-style policies set *Accounts: Administrator account status* to **Disabled**. Assigning both causes a **conflict**. Exclude these devices from that baseline setting, or set it to *Not configured* there.
- **LAPS.** Assign exactly **one** LAPS policy per device. Multiple LAPS policies with different values conflict.
- **GPO.** On hybrid-joined devices, a GPO that disables the account wins unless **MDMWinsOverGP** is enabled. Use **Group Policy analytics** to find it.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Open **Devices >** a device **> Local admin password** to see the LAPS-managed account, password and last rotation time.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Check the account is enabled:
   ```powershell
   Get-LocalUser | Where-Object SID -like "S-1-5-*-500" | Select-Object Name, Enabled, PasswordLastSet
   ```
   Expect `Enabled = True` and, once LAPS applies, a recent `PasswordLastSet`.
3. Check LAPS in Event Viewer under *Applications and Services Logs > Microsoft > Windows > LAPS > Operational*. Event **10020** means the password was updated and backed up to Entra ID. You can also run `Get-LapsDiagnostics`.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | The Windows security baseline or another policy disables the Administrator account | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | The current Administrator password doesn't meet the password policy, so the account can't be re-enabled | Fix the value and re-sync. |
| Error re-enabling the account | The existing password doesn't meet complexity requirements | Have another admin reset the password, or let LAPS set it, then re-sync. |
| No password in Intune or Entra | No LAPS policy, Entra LAPS not enabled, or an unsupported Windows build | Deploy the LAPS policy. Enable LAPS in Entra. Update Windows. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

No restart is needed.

## Rollback

- **Unassign or delete** the policy. Policy CSP security options **remain as last set** (they're effectively tattooed), so the account stays **enabled**.
- To disable it again, deploy the same setting with **Disable** (`0`), or set it in the security baseline, and keep LAPS until the account is disabled.

## References

- [Policy CSP – LocalPoliciesSecurityOptions (Accounts_EnableAdministratorAccountStatus)](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-localpoliciessecurityoptions#accounts_enableadministratoraccountstatus)
- [Microsoft Intune support for Windows LAPS](https://learn.microsoft.com/intune/device-security/laps/overview)
- [Deploy Windows LAPS policy with Intune](https://learn.microsoft.com/intune/device-security/laps/deploy-policy)
- [Windows LAPS with Microsoft Entra ID](https://learn.microsoft.com/windows-server/identity/laps/laps-scenarios-azure-active-directory)
- [Use the settings catalog](https://learn.microsoft.com/intune/device-configuration/settings-catalog/)
