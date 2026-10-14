# Windows Security – Block Internet Sharing

Stops Windows 10 and 11 devices from sharing their network connection through **Internet Connection Sharing (ICS)** or **Mobile Hotspot**. Delivered as an Intune **settings catalog** policy.

## Purpose

A corporate device that shares its connection becomes an **unmanaged gateway**. Personal or unknown devices can reach the corporate network or VPN through it, bypassing network access control. It also adds an attack surface (DHCP, NAT services).

This policy turns off ICS and the ICS service, which the **Mobile Hotspot** feature relies on. CIS and Azure Windows baselines recommend this (*Prohibit use of Internet Connection Sharing on your DNS domain network* = Enabled).

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows Security - Block Internet Sharing` (as shown in the screenshot) |
| Description | Block Internet Connection Sharing and Mobile Hotspot (Wifi/AllowInternetSharing = Not allowed). |
| Platform | Windows 10 and later |
| Profile type | Settings catalog |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `Block-Internet-Sharing.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: corporate Windows devices. Exclude devices that legitimately share connections (for example labs), if any. |
| Supported OS | Windows 10 1507 or later / Windows 11 (Pro, Enterprise, Education) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Wifi

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Allow Internet Sharing | **Block** (Not allowed) | `./Device/Vendor/MSFT/Policy/Config/Wifi/AllowInternetSharing` = `0` | ICS can't be enabled or configured and the ICS service can't run. Mobile Hotspot is blocked. Maps to the GPO *Prohibit use of Internet Connection Sharing on your DNS domain network* (`NC_ShowSharedAccessUI`). |

Don't also configure *Administrative Templates > Network > Network Connections > Prohibit use of Internet Connection Sharing on your DNS domain network*. It writes the same registry value; one source is enough.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Windows | Pro, Enterprise or Education |
| Role | Policy and Profile Manager or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Settings catalog**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows Security - Block Internet Sharing`
   - **Description**: Block Internet Connection Sharing and Mobile Hotspot (Wifi/AllowInternetSharing = Not allowed).
   - Select **Next**.
4. **Configuration settings**: select **Add settings**, search **Allow Internet Sharing**, add it from the **Wifi** category, then set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Allow Internet Sharing | Block |

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
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows Security - Block Internet Sharing'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Block-Internet-Sharing.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Block-Internet-Sharing.json" -Raw
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
- **Security baselines / other profiles.** A device restrictions template (*Network > Internet sharing*) or a baseline that sets ICS creates a duplicate. Keep it in one place.
- **GPO.** On hybrid devices, the equivalent GPO `NC_ShowSharedAccessUI` writes the same value. Remove it, or make sure it matches.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Go to **Settings > Network & internet > Mobile hotspot**. The toggle should be unavailable or blocked. In `ncpa.cpl` > adapter **Properties**, the **Sharing** tab should be gone.
3. Check `HKLM\SOFTWARE\Policies\Microsoft\Windows\Network Connections\NC_ShowSharedAccessUI = 0`.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | Another policy sets the same setting to a different value | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid value | Fix the value and re-sync. |
| Hotspot still available | Policy not applied yet, or a newer Windows UI path | Sync and restart. Check the registry value and that the *Internet Connection Sharing* service doesn't start. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

No restart is usually needed. Already-running hotspot sessions stop after the policy applies (sign out or restart if not).

## Rollback

- **Unassign or delete** the policy. The policy value is removed and ICS / Mobile Hotspot become **available again** (reverts).

## References

- [Policy CSP – Wifi/AllowInternetSharing](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-wifi#allowinternetsharing)
- [Policy CSP – ADMX_NetworkConnections (NC_ShowSharedAccessUI)](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-networkconnections#nc_showsharedaccessui)
- [Use the settings catalog](https://learn.microsoft.com/intune/device-configuration/settings-catalog/)
