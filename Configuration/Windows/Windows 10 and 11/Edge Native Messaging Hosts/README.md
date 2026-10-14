# Edge – Allowed Native Messaging Hosts

Restricts Microsoft Edge **native messaging hosts** on Windows 10 and 11 to an approved allow list. Native messaging hosts are local programs that browser extensions can talk to. Delivered as an Intune **settings catalog** policy.

## Purpose

Browser extensions can exchange messages with **native programs installed on the device** (native messaging hosts). This is a powerful bridge out of the browser sandbox: a malicious or compromised extension could use an unapproved host to run code or exfiltrate data.

This policy applies Microsoft's Edge for Business data-security pattern:
- **deny all** hosts (`*`);
- **allow only** approved hosts by name;
- block **user-level hosts**, which can be installed without admin rights.

> [!IMPORTANT]
> The screenshot only shows the policy name, so the **allow list must be filled in with your approved hosts**. The policy ships with one Microsoft host (the Outlook S/MIME control) and placeholders. Inventory existing hosts **before** deploying, or the extensions that use them (password managers, DLP, signing or e-ID tools, and so on) stop working.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - Edge - Allowed Native Messaging Hosts` (as shown in the screenshot) |
| Description | Block all Edge native messaging hosts except approved ones; disallow user-level (non-admin installed) hosts. |
| Platform | Windows 10 and later |
| Profile type | Settings catalog |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `Edge-Native-Messaging-Hosts.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: corporate Windows devices. Pilot first. |
| Supported OS | Windows 10 / 11 with Microsoft Edge 77 or later |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Microsoft Edge > Native Messaging

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Configure native messaging block list | **Enabled**: `*` | `NativeMessagingBlocklist` | `*` denies every native messaging host unless it's explicitly allowed. |
| Control which native messaging hosts users can use | **Enabled**: `com.microsoft.outlook.smime.chromenativeapp`, `<approved-host-1>`, `<approved-host-2>` | `NativeMessagingAllowlist` | Hosts exempt from the block list. The S/MIME host is Microsoft's documented value for Outlook on the web S/MIME. Replace the placeholders with your approved hosts. |
| Allow user-level native messaging hosts (installed without admin permissions) | **Disabled** | `NativeMessagingUserLevelHosts` | Only hosts installed at **system level** (by admins or Intune) can be used. |

**Find the hosts currently in use** on a sample of devices:
```powershell
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Edge\NativeMessagingHosts","HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge\NativeMessagingHosts","HKCU:\SOFTWARE\Microsoft\Edge\NativeMessagingHosts","HKLM:\SOFTWARE\Google\Chrome\NativeMessagingHosts" -ErrorAction SilentlyContinue | Select-Object PSChildName
```
Each key name (for example `com.vendor.product`) is a host name to approve or leave blocked. Edge also reads Chrome's registration keys.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Edge | Microsoft Edge 77 or later |
| Inventory | List of approved native messaging hosts (see above) |
| Role | Policy and Profile Manager or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Settings catalog**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - Edge - Allowed Native Messaging Hosts`
   - **Description**: Block all Edge native messaging hosts except approved ones; disallow user-level (non-admin installed) hosts.
   - Select **Next**.
4. **Configuration settings**: select **Add settings**, open **Microsoft Edge > Native Messaging**, select all three device settings, then set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Configure native messaging block list | Enabled; add `*` |
   | 2 | Control which native messaging hosts users can use | Enabled; add `com.microsoft.outlook.smime.chromenativeapp` and each approved host |
   | 3 | Allow user-level native messaging hosts (installed without admin permissions) | Disabled |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add a pilot **device** group, then corporate Windows devices. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - Edge - Allowed Native Messaging Hosts'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Edge-Native-Messaging-Hosts.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Edge-Native-Messaging-Hosts.json" -Raw
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

- **Assign to device groups**, and use the device (not *User*) settings.
- **Other Edge policies.** Keep native messaging settings only in this policy. The [Edge Configuration](../Edge%20Configuration) policy doesn't set them.
- **Extension management.** If you also restrict extensions (ExtensionSettings or allow lists), approve the host **and** its extension.
- **GPO.** On hybrid devices, remove the *Microsoft Edge > Native Messaging* GPO settings, or rely on *MDMWinsOverGP*.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Open `edge://policy`. **NativeMessagingBlocklist**, **NativeMessagingAllowlist** and **NativeMessagingUserLevelHosts** should show **Status OK**.
3. Test an approved extension that uses a native host (it should work) and an unapproved one (it should fail to connect to its host).
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | Another Edge policy or the Edge security baseline sets native messaging | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid value | Fix the value and re-sync. |
| An extension stops working ("native host has exited" / can't connect) | Its host isn't on the allow list, or it's installed per-user | Add the host name to the allow list. Install the host per-machine. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

Edge applies these policies dynamically; use **Reload policies** on `edge://policy` or restart Edge.

## Rollback

- **Unassign or delete** the policy. Edge **reverts** to loading all installed native messaging hosts. It isn't tattooed.

## References

- [NativeMessagingBlocklist](https://learn.microsoft.com/deployedge/microsoft-edge-policies/nativemessagingblocklist)
- [NativeMessagingAllowlist](https://learn.microsoft.com/deployedge/microsoft-edge-policies/nativemessagingallowlist)
- [NativeMessagingUserLevelHosts](https://learn.microsoft.com/deployedge/microsoft-edge-policies/nativemessaginguserlevelhosts)
- [Edge for Business – app configuration policies (Windows)](https://learn.microsoft.com/intune/solutions/edge-data-security/app-configuration-step-4)
- [S/MIME settings for Outlook on the web](https://learn.microsoft.com/exchange/policy-and-compliance/smime/smime-settings-for-owa)
