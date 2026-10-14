# Edge Configuration

Enterprise security and experience configuration for **Microsoft Edge** on Windows 10 and 11: SmartScreen enforcement, HTTPS warning enforcement, tracking prevention, automatic work-account sign-in, a clean first run, and updates. Delivered as an Intune **settings catalog** policy.

## Purpose

Edge is the main way users reach the internet, and phishing and malicious downloads are the top initial-access threats. This policy:

- **Enforces Microsoft Defender SmartScreen.** It's on, users **can't bypass** warnings for sites or downloads, and potentially unwanted apps are blocked. It works alongside the network protection set in the [Defender Antivirus policy](../Defender%20Antivirus%20Configuration).
- **Blocks clicking through HTTPS certificate warnings**, which are often a sign of interception or phishing.
- Uses **Balanced tracking prevention**, signs users in to their work profile automatically, hides consumer features (Rewards, shopping, first-run), and keeps Edge **updating automatically**.

Most of these values match the **Microsoft Edge security baseline**.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - Edge Configuration` (as shown in the screenshot) |
| Description | Microsoft Edge enterprise configuration: SmartScreen (sites, downloads, PUA) enforced, no HTTPS warning bypass, balanced tracking prevention, implicit sign-in, no consumer features, updates allowed. |
| Platform | Windows 10 and later |
| Profile type | Settings catalog |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. |
| File | `Edge-Configuration.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: all corporate Windows devices. |
| Supported OS | Windows 10 / 11 with Microsoft Edge 77 or later (SmartScreen policies need Windows Pro, Enterprise or Education that's MDM-enrolled or domain-joined) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Microsoft Edge > SmartScreen settings

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Configure Microsoft Defender SmartScreen | **Enabled** | `SmartScreenEnabled` | SmartScreen is on and users can't turn it off. |
| Configure Microsoft Defender SmartScreen to block potentially unwanted apps | **Enabled** | `SmartScreenPuaEnabled` | Blocks adware, coin miners and bundleware downloads. |
| Prevent bypassing Microsoft Defender SmartScreen prompts for sites | **Enabled** | `PreventSmartScreenPromptOverride` | Users are blocked from continuing to flagged sites. |
| Prevent bypassing of Microsoft Defender SmartScreen warnings about downloads | **Enabled** | `PreventSmartScreenPromptOverrideForFiles` | Users can't download unverified files that SmartScreen flags. |

### Microsoft Edge

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Allow users to proceed from the HTTPS warning page | **Disabled** | `SSLErrorOverrideAllowed` | Users can't click through certificate-error pages. |
| Block tracking of users' web-browsing activity | **Enabled: Balanced** | `TrackingPrevention` | Blocks harmful trackers with minimal site breakage. |
| Hide the First-run experience and splash screen | **Enabled** | `HideFirstRunExperience` | No first-run prompts on new devices. |
| Show Microsoft Rewards experiences | **Disabled** | `ShowMicrosoftRewards` | Removes a consumer feature. |
| Shopping in Microsoft Edge Enabled | **Disabled** | `EdgeShoppingAssistantEnabled` | Removes coupon and price-comparison features. |

### Microsoft Edge > Identity and sign-in

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Enable implicit sign-in | **Enabled** | `ImplicitSignInEnabled` | Edge signs the user in with their Windows work account, which enables SSO and Conditional Access. |

### Microsoft Edge Update > Applications

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Update policy override default | **Enabled: Always allow updates (recommended)** | `UpdateDefault` | Edge keeps patching itself automatically. |

**Optional additions** for stricter environments, after testing: *Configure InPrivate mode availability = disabled*, *Control which extensions cannot be installed* = `*` with an allow-list, and *Browser sign-in settings = Force users to sign-in*.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1 |
| Edge | Microsoft Edge (Chromium) installed; built into Windows 10 20H2 and later and Windows 11 |
| Windows | Pro, Enterprise or Education, MDM-enrolled (needed for SmartScreen and other device policies) |
| Role | Policy and Profile Manager or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Devices > Manage devices > Configuration > Create > New policy**. Set **Platform** to **Windows 10 and later** and **Profile type** to **Settings catalog**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - Edge Configuration`
   - **Description**: Microsoft Edge enterprise configuration: SmartScreen (sites, downloads, PUA) enforced, no HTTPS warning bypass, balanced tracking prevention, implicit sign-in, no consumer features, updates allowed.
   - Select **Next**.
4. **Configuration settings**: select **Add settings** and search the **Microsoft Edge** and **Microsoft Edge Update** categories. Use the device (non-*User*) versions of the settings, then set:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Configure Microsoft Defender SmartScreen | Enabled |
   | 2 | Configure Microsoft Defender SmartScreen to block potentially unwanted apps | Enabled |
   | 3 | Prevent bypassing Microsoft Defender SmartScreen prompts for sites | Enabled |
   | 4 | Prevent bypassing of Microsoft Defender SmartScreen warnings about downloads | Enabled |
   | 5 | Allow users to proceed from the HTTPS warning page | Disabled |
   | 6 | Block tracking of users' web-browsing activity | Enabled > Balanced |
   | 7 | Hide the First-run experience and splash screen | Enabled |
   | 8 | Show Microsoft Rewards experiences | Disabled |
   | 9 | Shopping in Microsoft Edge Enabled | Disabled |
   | 10 | Enable implicit sign-in | Enabled |
   | 11 | Update policy override default | Enabled > Always allow updates (recommended) |

   Leave everything else **Not configured**. Select **Next**.
5. **Scope tags**: remove **Default**, add **Windows Admin**, then select **Next**.
6. **Assignments**: Add all corporate Windows **device** groups. Select **Next**.
7. **Review + create**: check the settings, then select **Create**.

## Step-by-step: import with Microsoft Graph PowerShell

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -Scopes "DeviceManagementConfiguration.ReadWrite.All","DeviceManagementRBAC.Read.All"

# 1. Find the IDs the JSON needs (scope tag)
(Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags").value |
    Select-Object id, displayName

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - Edge Configuration'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Edge-Configuration.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Edge-Configuration.json" -Raw
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

- **Assign to device groups**, and use the device versions of the settings. Don't configure the same Edge setting as both a device and a *(User)* setting.
- **Microsoft Edge security baseline.** It sets SmartScreen, SmartScreen bypass and SSL override among others. If assigned, align the values or remove the duplicates; different values cause **conflicts**.
- **Other Edge policies.** Keep each Edge setting in **one** policy. Use separate policies only for different purposes (for example *Edge extensions*).
- **GPO.** On hybrid devices, remove the Edge ADMX GPO settings, or use *MDMWinsOverGP*. Use **Group Policy analytics** to migrate.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. In Edge, open `edge://policy`. Every configured policy should show **Status OK** and **Source Platform** (MDM).
3. Check `HKLM\SOFTWARE\Policies\Microsoft\Edge` for the values (for example `SmartScreenEnabled=1`, `SSLErrorOverrideAllowed=0`).
4. Test SmartScreen with `https://demo.smartscreen.msft.net/`. The warning page should have **no** *continue* option.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | The Edge security baseline or another Edge policy sets the same policy differently | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid value | Fix the value and re-sync. |
| Policy shows an *Error* in edge://policy | Unknown or obsolete policy, or the wrong scope | Update Edge. Use the device setting. |
| SmartScreen policies ignored | Windows Home, or the device isn't MDM-enrolled or domain-joined | Use a supported edition and enrollment. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

Most Edge policies apply dynamically. Use **Reload policies** on `edge://policy`, or restart Edge.

## Rollback

- **Unassign or delete** the policy. Intune removes the Edge policy registry values and Edge **reverts** to its defaults, with users able to change settings. It isn't tattooed.
- Remove individual settings by editing the policy, rather than deleting the whole thing.

## References

- [Configure Microsoft Edge policy settings with Intune](https://learn.microsoft.com/deployedge/configure-edge-with-intune)
- [Microsoft Edge – Policies](https://learn.microsoft.com/deployedge/microsoft-edge-policies)
- [Microsoft Edge – Update policies](https://learn.microsoft.com/deployedge/microsoft-edge-update-policies)
- [Microsoft Edge security baseline settings for Intune](https://learn.microsoft.com/intune/device-security/security-baselines/ref-edge-settings)
- [Use the settings catalog](https://learn.microsoft.com/intune/device-configuration/settings-catalog/)
