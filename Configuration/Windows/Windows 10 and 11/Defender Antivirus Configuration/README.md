# Defender Antivirus Configuration

Enterprise configuration for **Microsoft Defender Antivirus** on Windows 10 and 11: real-time and cloud protection, PUA blocking, network protection, scans and updates. Delivered as an Intune **Endpoint security > Antivirus > Microsoft Defender Antivirus** policy.

## Purpose

Microsoft Defender Antivirus is the foundation for every ASR policy in this folder, and for the compliance policies in `Compliance/Windows` that require antivirus, real-time protection and current signatures. This policy turns on the protections Microsoft recommends:

- **Always-on and cloud-delivered protection** with **block at first sight** (High cloud block level, 50-second extended cloud check).
- **Potentially unwanted app (PUA) blocking** and **network protection** in block mode.
- **Frequent security intelligence updates** and a **daily quick scan**, with a check for updates before each scan.
- Local admins **can't add their own exclusions** (*Disable Local Admin Merge*) and **can't see** the managed exclusion list.

Values follow the Windows MDM security baseline and Microsoft's Defender Antivirus guidance for Intune.

## Policy summary

| Item | Value |
|---|---|
| Policy name | `Windows - Defender Antivirus Configuration` (as shown in the screenshot) |
| Description | Enterprise Microsoft Defender Antivirus configuration (real-time, cloud, PUA, network protection, scans, updates). |
| Platform | Windows 10 and later |
| Profile type | Endpoint security > Antivirus > **Microsoft Defender Antivirus** (settings catalog format) |
| Graph endpoint | `POST https://graph.microsoft.com/beta/deviceManagement/configurationPolicies` |
| `platforms` / `technologies` | `windows10` / `mdm`. Check this against your export. Tenants that manage devices through Defender for Endpoint security settings management show `mdm,microsoftSense`. |
| File | `Defender-Antivirus-Configuration.json` (policy metadata only, see the note below) |
| Scope tags | Windows Admin. The screenshot doesn't show scope tags, so this is assumed from your other Windows policies. |
| Recommended assignment | **Device** groups: all corporate Windows devices. |
| Supported OS | Windows 10 1709 or later / Windows 11 (Pro, Enterprise, Education) |

> [!NOTE]
> **Why the JSON has no settings.** Microsoft Learn documents the CSPs and values in the tables below, but doesn't publish the **Microsoft Defender Antivirus template ID** or the settings catalog **definition IDs**.
>
> So the JSON only holds the verified policy metadata, with `templateId` as a placeholder and an empty `settings` array. Build the policy in the admin center (steps below), then export it with Graph and **replace this JSON with the export**.

## Configuration settings

### Real-time protection

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Allow Realtime Monitoring | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowRealtimeMonitoring` = 1 | Always-on protection. Required by your Windows compliance policies. |
| Allow Behavior Monitoring | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowBehaviorMonitoring` = 1 | Detects malicious behaviour, not just files. |
| Allow On Access Protection | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowOnAccessProtection` = 1 | Scans files when they're accessed. |
| Allow scanning of all downloaded files and attachments | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowIOAVProtection` = 1 | Scans downloads and attachments (IOAV). |
| Allow Script Scanning | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowScriptScanning` = 1 | Scans scripts (AMSI). Needed by the obfuscated-script and JS/VBScript ASR rules. |
| Real Time Scan Direction | **Monitor all files (bi-directional)** | `./Device/Vendor/MSFT/Policy/Config/Defender/RealTimeScanDirection` = 0 | Scans incoming and outgoing files. |

### Cloud protection

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Allow Cloud Protection | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowCloudProtection` = 1 | Cloud-delivered protection (MAPS). Required by several ASR rules. |
| Cloud Block Level | **High** | `./Device/Vendor/MSFT/Policy/Config/Defender/CloudBlockLevel` = 2 | Aggressively blocks unknown files while keeping client performance. Also needed for ASR user notifications. |
| Cloud Extended Timeout | **50** | `./Device/Vendor/MSFT/Policy/Config/Defender/CloudExtendedTimeout` = 50 | Holds suspicious files for up to 60 seconds (10 + 50) while the cloud decides. |
| Submit Samples Consent | **Send safe samples automatically** | `./Device/Vendor/MSFT/Policy/Config/Defender/SubmitSamplesConsent` = 1 | Needed for block at first sight. The security baseline uses *Send all samples*; *safe samples* avoids uploading documents that may contain business data. |

### Scanning

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Allow Archive Scanning | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowArchiveScanning` = 1 | Scans `.zip`, `.cab` and other archives. |
| Allow Email Scanning | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowEmailScanning` = 1 | Scans mailbox files. |
| Allow Full Scan Removable Drive Scanning | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowFullScanRemovableDriveScanning` = 1 | Includes USB drives in full scans (alongside the [USB ASR rule](../Block%20Untrusted%20EXE%20from%20USB)). |
| Allow scanning of network files | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowScanningNetworkFiles` = 1 | Scans files opened from network shares. |
| Scan Parameter | **Quick scan** | `./Device/Vendor/MSFT/Policy/Config/Defender/ScanParameter` = 1 | Type of scheduled scan. Real-time protection covers the rest. |
| Schedule Quick Scan Time | **720** (12:00) | `./Device/Vendor/MSFT/Policy/Config/Defender/ScheduleQuickScanTime` = 720 | Daily quick scan at midday, when devices are usually on. Minutes after midnight. |
| Check For Signatures Before Running Scan | **Enabled** | `./Device/Vendor/MSFT/Policy/Config/Defender/CheckForSignaturesBeforeRunningScan` = 1 | Scans always use the latest intelligence. |
| Disable Catchup Quick Scan | **Disabled** (catch-up on) | `./Device/Vendor/MSFT/Policy/Config/Defender/DisableCatchupQuickScan` = 0 | Runs a missed scheduled scan at the next opportunity. |
| Avg CPU Load Factor | **50** | `./Device/Vendor/MSFT/Policy/Config/Defender/AvgCPULoadFactor` = 50 | Limits scheduled-scan CPU use to 50%. |

### Updates

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| Signature Update Interval | **4** | `./Device/Vendor/MSFT/Policy/Config/Defender/SignatureUpdateInterval` = 4 | Checks for new security intelligence every 4 hours. |

### Defender

| Setting (admin center name) | Value | CSP / ID | What it does / why |
|---|---|---|---|
| PUA Protection | **PUA Protection on** (block) | `./Device/Vendor/MSFT/Policy/Config/Defender/PUAProtection` = 1 | Blocks potentially unwanted apps (adware, bundleware, coin miners). |
| Enable Network Protection | **Enabled (block mode)** | `./Device/Vendor/MSFT/Policy/Config/Defender/EnableNetworkProtection` = 1 | Blocks connections to malicious domains and IPs from any app. Also used by Defender for Endpoint web content filtering. |
| Allow User UI Access | **Allowed** | `./Device/Vendor/MSFT/Policy/Config/Defender/AllowUserUIAccess` = 1 | Users can see the Windows Security app and notifications (including ASR Warn prompts). |
| Days To Retain Cleaned Malware | **30** | `./Device/Vendor/MSFT/Policy/Config/Defender/DaysToRetainCleanedMalware` = 30 | Keeps quarantined items 30 days for investigation. |
| Disable Local Admin Merge | **Enabled** | `./Vendor/MSFT/Defender/Configuration/DisableLocalAdminMerge` = 1 | Local admins can't add their own exclusions or overrides; only Intune settings apply. |
| Hide Exclusions From Local Admins | **Enabled** | `./Vendor/MSFT/Defender/Configuration/HideExclusionsFromLocalAdmins` = 1 | Attackers with local admin can't read the exclusion list. |
| Enable File Hash Computation | **Enabled** | `./Vendor/MSFT/Defender/Configuration/EnableFileHashComputation` = 1 | Computes file hashes so Defender for Endpoint file indicators work. |
| Exclusions (paths / extensions / processes) | *Not configured* | `./Device/Vendor/MSFT/Policy/Config/Defender/ExcludedPaths` … | Add only vendor-documented exclusions, in a separate small policy if needed. |

> [!NOTE]
> **Tamper protection** isn't in this profile. Turn it on tenant-wide in the **Microsoft Defender portal > Settings > Endpoints > Advanced features**, or with **Endpoint security > Antivirus > Windows Security Experience**. With tamper protection on, some settings (such as Cloud Block Level) can only be changed through policy, not locally.

## Prerequisites

| Requirement | Details |
|---|---|
| Licensing | Microsoft Intune Plan 1. Defender Antivirus is included in Windows. Defender for Endpoint P1/P2 adds EDR, reporting and indicators. |
| Antivirus | No other antivirus active. If one is installed, Defender runs in **passive mode** and these settings don't protect the device. |
| Network | Access to the Defender cloud service and update endpoints |
| Enrollment | Intune-enrolled, or co-managed with the **Endpoint Protection** workload set to Intune |
| Role | **Endpoint Security Manager** or Intune Administrator, with the **Windows Admin** scope tag |

## Step-by-step: create the policy in the Intune admin center

1. Sign in to the [Microsoft Intune admin center](https://intune.microsoft.com).
2. Go to **Endpoint security > Antivirus > Create Policy**. Set **Platform** to **Windows** and **Profile** to **Microsoft Defender Antivirus**, then select **Create**.
3. **Basics**:
   - **Name**: `Windows - Defender Antivirus Configuration`
   - **Description**: Enterprise Microsoft Defender Antivirus configuration (real-time, cloud, PUA, network protection, scans, updates).
   - Select **Next**.
4. **Configuration settings**: set each setting in the tables above. Summary:

   | # | Setting | Value |
   |---|---|---|
   | 1 | Allow Realtime Monitoring / Behavior Monitoring / On Access Protection / IOAV / Script Scanning | Allowed |
   | 2 | Real Time Scan Direction | Monitor all files (bi-directional) |
   | 3 | Allow Cloud Protection | Allowed |
   | 4 | Cloud Block Level | High |
   | 5 | Cloud Extended Timeout | 50 |
   | 6 | Submit Samples Consent | Send safe samples automatically |
   | 7 | Allow Archive / Email / Full Scan Removable Drive / Network files scanning | Allowed |
   | 8 | Scan Parameter | Quick scan |
   | 9 | Schedule Quick Scan Time | 720 |
   | 10 | Check For Signatures Before Running Scan | Enabled |
   | 11 | Disable Catchup Quick Scan | Disabled |
   | 12 | Avg CPU Load Factor | 50 |
   | 13 | Signature Update Interval | 4 |
   | 14 | PUA Protection | PUA Protection on |
   | 15 | Enable Network Protection | Enabled (block mode) |
   | 16 | Allow User UI Access | Allowed |
   | 17 | Days To Retain Cleaned Malware | 30 |
   | 18 | Disable Local Admin Merge | Enabled |
   | 19 | Hide Exclusions From Local Admins | Enabled |
   | 20 | Enable File Hash Computation | Enabled |

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
    Where-Object displayName -like "*Microsoft Defender Antivirus*" | Select-Object id, displayName, templateFamily, platforms, technologies

# 2. After creating the policy in the admin center, export it with every setting and definition ID
$p = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$filter=name eq 'Windows - Defender Antivirus Configuration'").value[0]
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$($p.id)?`$expand=settings" |
    ConvertTo-Json -Depth 30 | Out-File ".\Defender-Antivirus-Configuration.json"
#    Remove id, createdDateTime, lastModifiedDateTime, settingCount and settings@odata.context before reusing it as an import body.

# 3. Import into another tenant
$body = Get-Content ".\Defender-Antivirus-Configuration.json" -Raw
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

- **Assign to device groups.** Use **one** antivirus policy per device for these settings.
- **Security baselines.** The **Windows security baseline** and the **Defender for Endpoint baseline** set many of the same Defender settings, such as Cloud Block Level, PUA and Network Protection. Different values cause **conflicts**. Either align values, or set the overlapping settings to *Not configured* in the baseline. (The baseline uses *Send all samples*; this policy uses *safe samples*.)
- **Other policy types.** Endpoint protection template profiles, settings catalog Defender policies and the *Defender Update controls* profile can overlap.
- **GPO.** On hybrid devices, a GPO under *Windows Components > Microsoft Defender Antivirus* can conflict. Remove it, or use *MDMWinsOverGP*.
- **ASR policies** in this folder depend on this policy (cloud protection, script scanning) but don't conflict with it.

## Validation

**In the admin center**
- Open the policy **> Device status / Per-setting status**. Every setting should show **Succeeded**.
- Check **Devices > Monitor > Assignment failures**.
- Check **Reports > Microsoft Defender Antivirus** (antivirus agent status) and **Endpoint security > Antivirus > Unhealthy endpoints**.

**On the device**
1. Sync: go to **Settings > Accounts > Access work or school >** your account **> Info > Sync**. Devices also check in about every 8 hours.
2. Check the effective configuration:
   ```powershell
   Get-MpComputerStatus | Select-Object AMRunningMode, RealTimeProtectionEnabled, BehaviorMonitorEnabled, IoavProtectionEnabled, AntivirusSignatureLastUpdated
   Get-MpPreference | Select-Object MAPSReporting, CloudBlockLevel, CloudExtendedTimeout, SubmitSamplesConsent, PUAProtection, EnableNetworkProtection, SignatureUpdateInterval, ScanParameters, ScanScheduleQuickScanTime, DisableLocalAdminMerge
   ```
   Expect `AMRunningMode = Normal`, `CloudBlockLevel = 2`, `CloudExtendedTimeout = 50`, `PUAProtection = 1`, `EnableNetworkProtection = 1` and `SignatureUpdateInterval = 4`.
3. Test with the EICAR test file, or `https://smartscreentestratings2.net` for network protection, from a test device.
- For MDM errors, check Event Viewer under *Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider > Admin*. You can also collect logs with `mdmdiagnosticstool.exe -area DeviceEnrollment;DeviceProvisioning -cab C:\Temp\mdm.cab`.

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| **Pending** | The device hasn't checked in | Sync the device. Check it's online. |
| **Not applicable** | Unsupported Windows edition or version | Upgrade the OS or edition. |
| **Conflict** | A security baseline or another Defender policy sets the same setting differently | Use **Per-setting status** to find the other policy. Configure each setting in only one policy. |
| **Error** | Invalid value | Fix the value and re-sync. |
| Settings applied but not effective | Defender in **passive mode** because another antivirus is active | Remove the other antivirus, or accept passive mode with EDR in block mode. |
| Local changes revert or are ignored | Tamper protection or *Disable Local Admin Merge* (expected) | Change the setting through Intune. |
| Assigned to a user group but not applied as expected | Device-scoped settings | Assign to **device** groups. |

No restart is needed. Defender picks up policy changes at the next policy refresh.

## Rollback

- **Unassign or delete** the policy. Policy-managed Defender settings are removed and **revert to Windows defaults** (for example Cloud Block Level default, PUA audit/off, network protection off). They aren't tattooed.
- Keep **real-time protection** and **cloud protection** on during any rollback. Your Windows compliance policies require them.

## References

- [Antivirus policy for endpoint security in Intune](https://learn.microsoft.com/intune/device-configuration/endpoint-security/antivirus)
- [Configure Microsoft Defender Antivirus using Intune](https://learn.microsoft.com/defender-endpoint/use-intune-config-manager-microsoft-defender-antivirus)
- [Policy CSP – Defender](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-defender)
- [Defender CSP (DisableLocalAdminMerge, HideExclusionsFromLocalAdmins)](https://learn.microsoft.com/windows/client-management/mdm/defender-csp)
- [Configure cloud protection](https://learn.microsoft.com/defender-endpoint/cloud-protection-configure)
- [Windows MDM security baseline settings](https://learn.microsoft.com/intune/device-security/security-baselines/ref-windows-mdm-settings)
