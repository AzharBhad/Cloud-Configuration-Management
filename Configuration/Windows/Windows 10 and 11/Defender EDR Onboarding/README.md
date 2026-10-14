# Defender EDR Onboarding

Onboards Windows 10 and 11 devices to **Microsoft Defender for Endpoint** (EDR) using the package Intune gets automatically from the Defender connector, with **sample sharing** turned on. Delivered as an Intune **Endpoint security > Endpoint detection and response** policy.

## Purpose

Onboarding connects each device's built-in Defender for Endpoint sensor to your tenant. This gives you:
- **EDR** alerts and incidents, and the device timeline;
- automated investigation and response;
- vulnerability management;
- **device risk score**, which your compliance policies use. The *Security Baseline* and *Windows 365 Cloud PC* compliance policies require risk **Low**.

It also enables ASR reporting and advanced hunting for the ASR policies in this folder.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - Defender EDR Onboarding` (as shown in the screenshot) |
| Description | Onboard to Defender for Endpoint (Auto from connector) with sample sharing All. |
| Platform | Windows 10 and later |
| Profile type | Endpoint security > Endpoint detection and response > **Endpoint detection and response** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. Tenants that manage devices through Defender for Endpoint security settings management show `mdm,microsoftSense`. |
| File | `Defender-EDR-Onboarding.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: all corporate Windows devices (or use the preconfigured *all devices* deployment on the **EDR Onboarding Status** tab). |
| Supported OS | Windows 10 1709 or later / Windows 11 (Pro, Enterprise, Education) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the **Endpoint detection and response template ID** or the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Endpoint detection and response

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Microsoft Defender for Endpoint client configuration package type | **Auto from connector** | `./Device/Vendor/MSFT/WindowsAdvancedThreatProtection/Onboarding` (blob supplied by the connector) | Uses the latest onboarding package from your Defender tenant automatically, so no blob is stored in policy or in this repo. |
| Sample Sharing | **All** | `./Device/Vendor/MSFT/WindowsAdvancedThreatProtection/Configuration/SampleSharing` = 1 | Lets Defender send suspicious file samples for deep analysis. Set to **None** only for devices that are too sensitive. |
| [Deprecated] Telemetry Reporting Frequency | *Not configured* | — | Deprecated; doesn't affect new devices. |

If you can't use the connector (for example air-gapped or multi-tenant), select **Onboard** and paste the `WindowsDefenderATP.onboarding` content from **Defender portal > Settings > Endpoints > Onboarding > Mobile Device Management / Microsoft Intune**. **Don't commit that blob to this repo.**

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | **Microsoft Defender for Endpoint P1/P2**, or Microsoft 365 E5 / E5 Security, plus Intune Plan 1 |
| Connector | **Tenant administration > Connectors and tokens > Microsoft Defender for Endpoint** = **Connected** (allow up to 15 minutes) |
| Network | Devices reach the Defender for Endpoint service URLs (for example `*.securitycenter.windows.com`) |
| Antivirus | Defender Antivirus active ([Defender Antivirus Configuration](../Defender%20Antivirus%20Configuration)), or passive with EDR in block mode |
| Role | **Endpoint Security Manager** / Intune Administrator. Security Administrator for the connector. |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Endpoint detection and response > Summary > Create Policy**. Set **Platform** to **Windows** and **Profile** to **Endpoint detection and response**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - Defender EDR Onboarding`
   - **Description**: Onboard to Defender for Endpoint (Auto from connector) with sample sharing All.
   - Select **Next**.
4. **Configuration settings**:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Microsoft Defender for Endpoint client configuration package type | Auto from connector |
   | 2 | Sample Sharing | All |

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
    Where-Object displayName -like "*Endpoint detection and response*" | Select-Object id, displayName, templateFamily, platforms, technologies

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - Defender EDR Onboarding'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Defender-EDR-Onboarding.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Defender-EDR-Onboarding.json" -Raw
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

- **One onboarding source per device.** Don't also onboard with a **device configuration** *Microsoft Defender for Endpoint* template, a GPO or script, or Configuration Manager. Two Intune sources for the same setting cause **conflicts**.
- The **Defender for Endpoint security baseline** doesn't onboard devices, but it overlaps with the Defender Antivirus settings (see that policy).

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Check **Endpoint security > Endpoint detection and response > EDR Onboarding Status** for onboarded and sensor-health counts. In the **Defender portal > Assets > Devices**, the device should appear with a recent *Last seen*.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Check `HKLM\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status` has `OnboardingState = 1`. `Get-Service Sense` should show **Running**.
3. Run Microsoft's detection test from an elevated prompt on a test device, then check the alert in the Defender portal.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | Another onboarding policy (device configuration template or a second EDR policy) | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Onboarding blob invalid or expired, or the connector isn't connected | Fix the value and re-sync. |
| *Auto from connector* option missing | Defender connector not connected or not yet synced | Connect it, wait 15 minutes, check permissions. |
| Device not in the Defender portal | Blocked URLs, Sense service not running, or onboarding pending | Check the network endpoints and the Sense service, then re-sync. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

No restart is needed. Onboarding starts the Sense service.

## Rollback

- **Unassign or delete** the policy. This does **not** offboard devices; they stay onboarded (effectively tattooed).
- To offboard, deploy an EDR policy with **Offboard** and the offboarding package from the Defender portal. Offboarding packages expire.

## References

- [Deploy endpoint detection and response policy with Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/deploy-edr)
- [Configure Defender for Endpoint with Intune and onboard devices](https://learn.microsoft.com/intune/device-security/microsoft-defender/configure-integration)
- [EDR policy settings](https://learn.microsoft.com/intune/device-configuration/endpoint-security/ref-edr-settings)
- [WindowsAdvancedThreatProtection CSP](https://learn.microsoft.com/windows/client-management/mdm/windowsadvancedthreatprotection-csp)
