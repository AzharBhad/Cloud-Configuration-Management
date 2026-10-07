# Enable Credential Guard

An Intune **platform script** that turns on **Windows Defender Credential Guard** on Windows 10 and Windows 11 Enterprise and Education devices.

Why use it:

- **Protects cached credentials from credential theft tools.** Credential Guard uses virtualization-based security (VBS) to move NTLM password hashes, Kerberos ticket-granting tickets and credentials that apps store as domain credentials into an isolated environment. Malware running on the device - even as administrator - can't read them, so tools like Mimikatz come away empty.
- **Prevents Pass-the-Hash and Pass-the-Ticket attacks.** Without the hashes and tickets, attackers can't reuse them to move to other machines and accounts in your network.

Microsoft recommends turning Credential Guard on **before** a device joins a domain or a domain user signs in for the first time, so secrets are never exposed.

## Files

| File | Purpose |
|---|---|
| `Enable-CredentialGuard.ps1` | The platform script you upload to Intune. |
| `README.md` | This document. |

## Typical actions

### When to use this script

| Scenario | Why this script helps |
|---|---|
| **New device setup** (Autopilot) | Credential Guard is on before users sign in and before secrets are cached. |
| **Windows 10, or Windows 11 before 22H2** | These versions don't turn Credential Guard on by default. |
| **Devices where it was never enabled** | One-time fix for a group of existing Enterprise / Education devices. |
| **Security baseline / audit** | Meets Credential Guard requirements in CIS, Microsoft security baselines, Cyber Essentials Plus, ISO 27001 controls. |
| **No Settings catalog policy yet** | The supported long-term way is an Intune policy (see below); this script works where you can't use one. |

> **Prefer an Intune policy for ongoing management.** Microsoft's supported way is **Settings catalog > Device Guard > Credential Guard** (or **Endpoint security > Account protection**). A policy is enforced continuously; this script runs once. Use the script where a policy isn't an option, or to fix devices once. Don't use both with different values.

> **Windows 11 22H2 and later** already turns Credential Guard on by default on eligible Enterprise / Education devices that meet the hardware requirements. On those devices the script finds it **running** and changes nothing.

### What the script does on the device

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | 64-bit check | Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit. | Already 64-bit. |
| 2 | Exclusions | Stops with success if the computer name matches `$ExcludeList`. | Name not in the list. |
| 3 | Current state | Reads `Win32_DeviceGuard`. **Running** or **configured and waiting for a restart** = nothing to do (success). | - |
| 4 | Requirements | **Stops with failure** if the edition isn't Enterprise / Education, the device doesn't report hardware virtualization support for VBS, or UEFI Secure Boot is off. | `$AllowUnsupportedEdition` skips the edition check only. |
| 5 | Policy check | **Stops with failure** if Group Policy (`HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard`) or Intune (`...\PolicyManager\current\device\DeviceGuard`) sets `LsaCfgFlags` or `EnableVirtualizationBasedSecurity` to `0` - a local change would be overridden. | No such policy. |
| 6 | Turn on | Writes only the values that differ (table below). | Values already correct. |
| 7 | Summary | Writes one line saying Credential Guard is enabled and a **restart is required**. | - |

Registry values written (as documented by Microsoft in *Configure Credential Guard*):

| Key | Value | Data |
|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard` | `EnableVirtualizationBasedSecurity` | `1` - turn on VBS |
| `HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard` | `RequirePlatformSecurityFeatures` | `1` = Secure Boot, `3` = Secure Boot + DMA protection |
| `HKLM\SYSTEM\CurrentControlSet\Control\Lsa` | `LsaCfgFlags` | `2` = enabled **without** UEFI lock (default), `1` = enabled **with** UEFI lock |

**Credential Guard starts at the next restart.** The script never restarts the device.

### Before you deploy: what Credential Guard blocks

Credential Guard blocks protocols that expose passwords. Test these on a pilot group first:

| Affected | Effect | Fix |
|---|---|---|
| **Wi-Fi / VPN using PEAP-MSCHAPv2 or EAP-MSCHAPv2** | Single sign-on with the user's Windows credentials stops working - users are prompted, or the connection fails if prompting isn't allowed. | Move to **certificate-based** authentication (EAP-TLS / PEAP-TLS), for example with Intune SCEP/PKCS certificates. |
| **NTLMv1**, **WDigest** | Single sign-on blocked; users must type credentials. | Move to NTLMv2 / Kerberos. |
| **Kerberos unconstrained delegation**, **DES** encryption | Blocked, including for typed and saved credentials. | Use constrained or resource-based constrained delegation; AES encryption. |
| **Generation 1 Hyper-V / Azure VMs** | Credential Guard isn't supported. | Generation 2 VMs only. |

## Settings in the script

At the top of `Enable-CredentialGuard.ps1`:

| Setting | Default | What it does |
|---|---|---|
| `$UseUefiLock` | `$false` | `$false` = enable **without** UEFI lock - you can turn Credential Guard off remotely later (recommended by Microsoft if you want remote control). `$true` = **with** UEFI lock - malware can't turn it off by editing the registry, but turning it off later needs someone at the device to confirm a firmware prompt. |
| `$PlatformSecurityLevel` | `'Auto'` | `'Auto'` = Secure Boot + DMA protection when the device supports DMA protection, otherwise Secure Boot. `1` = Secure Boot. `3` = Secure Boot + DMA protection. |
| `$AllowUnsupportedEdition` | `$false` | Try on editions other than Enterprise / Education. Credential Guard isn't supported there; leave `$false`. |
| `$ExcludeList` | `@()` | Computer names to skip (wildcards allowed). |

Example - maximum protection with UEFI lock, skip lab machines:

```powershell
$UseUefiLock = $true
$PlatformSecurityLevel = 3
$ExcludeList = @('LAB-*')
```

## How Intune runs it

| Intune behavior | What it means for this script |
|---|---|
| **Runs once** per device | Turns Credential Guard on once. If someone turns it off later, the script won't notice - use a Settings catalog policy to keep it enforced. |
| **Re-runs after you change the script** | Safe: running or pending devices are left alone; only differing values are written. |
| **Re-runs for every new user** who signs in (device assignment) | Safe for the same reason. |
| **Retries 3 times** after a failure | Devices that don't meet the requirements (edition, virtualization, Secure Boot) fail every time - that is how they show up in the report. Fix the device, then re-run. |
| **30-minute time limit** | The script takes seconds. |
| **Runs before Win32 apps** | Good - Credential Guard is configured early in device setup. |

## Prerequisites

- **Windows 10 or Windows 11 Enterprise or Education** (including IoT Enterprise). **Not supported on Pro, Pro Education or Home.**
- License: **Windows Enterprise E3/E5** or **Education A3/A5** (Credential Guard is an Enterprise feature).
- Hardware:
  - 64-bit CPU with **virtualization extensions** (Intel VT-x / AMD-V) and second-level address translation, turned on in the firmware.
  - **UEFI** firmware with **Secure Boot** turned on.
  - **TPM 1.2 or 2.0** recommended (binds the protection to the hardware).
  - For DMA protection (level 3): Kernel DMA Protection support (IOMMU).
- Virtual machines: **Generation 2** Hyper-V / Azure VMs only, on a Hyper-V host with an **IOMMU**.
- Devices **enrolled in Intune** and **Microsoft Entra joined** or **hybrid joined**. Devices that are only Entra *registered* don't receive platform scripts.
- No Group Policy or Intune policy that turns Credential Guard or VBS off.
- An Intune role that can add platform scripts, such as **Intune Administrator** or **Policy and Profile Manager**.

Microsoft's **HVCI and Credential Guard hardware readiness tool** (download center ID 53337) can check a device in advance.

## Step-by-step: add the script in Intune

1. Edit the settings at the top of `Enable-CredentialGuard.ps1` if needed.
2. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
3. Go to **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**.
4. **Basics**
   - **Name**: `Enable Credential Guard`
   - **Description**: `Turns on Windows Defender Credential Guard (VBS) to protect credentials against Pass-the-Hash and Pass-the-Ticket. Restart required.`
   - Select **Next**.
5. **Script settings**
   - **Script location**: browse to `Enable-CredentialGuard.ps1`.
   - **Run this script using the logged on credentials**: **No**. The script must run as **SYSTEM**: it writes `HKLM\SYSTEM` and reads the Device Guard and Secure Boot state, which need admin rights.
   - **Enforce script signature check**: **No** (unless you sign the script).
   - **Run script in 64-bit PowerShell host**: **Yes**. (The script also relaunches itself in 64-bit if left at No.)
   - Select **Next**.
6. **Scope tags**: choose scope tags if you use them, then select **Next**.
7. **Assignments**
   - Under **Included groups**, select a **device group** of Windows Enterprise / Education devices (for example an Autopilot device group). Credential Guard is a device setting, so assign to devices, not users. Start with a small **pilot group** and test Wi-Fi, VPN and line-of-business apps.
   - Select **Next**.
8. **Review + add**: check the settings and select **Add**.
9. **Restart the devices.** Credential Guard starts after the next restart. On new Autopilot devices this happens during setup; for existing devices, wait for the next Windows Update restart or use **Devices > All devices > (device) > Restart** in Intune.

## Step-by-step: check the results

1. Go to **Devices > Scripts and remediations > Platform scripts** and open **Enable Credential Guard**.
2. Open **Device status**:
   - **Success** - Credential Guard is running, or configured and waiting for a restart.
   - **Failed** - the device doesn't meet the requirements, or a policy blocks it. The result message says which (available through Microsoft Graph (beta): `deviceManagement/deviceManagementScripts/{id}/deviceRunStates`, property `resultMessage`), and the log has the details.
3. Check a device **after a restart**:
   - **System Information** (`msinfo32`) > **System Summary**: **Virtualization-based security Services Running** lists **Credential Guard**.
   - PowerShell (elevated):
     ```powershell
     (Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard).SecurityServicesRunning
     ```
     The result contains **1** when Credential Guard is running.
   - Don't rely on `LsaIso.exe` in Task Manager - Microsoft doesn't recommend it as a check.
4. For an ongoing fleet view, deploy a Credential Guard **Settings catalog** policy as well - its report under **Devices > Configuration** shows each device's state.

## Running it again

- **For all assigned devices:** edit the script (any change, even a comment or a setting), then upload the new version in the script's **Properties > Script settings**. Intune runs it again on every assigned device.
- **For specific devices** (for example after turning on Secure Boot): remove them from the assigned group, wait for the next check-in, then add them back. Or assign the script to a new group containing just those devices.
- **New users:** a device-assigned script runs again when a new user signs in; that is safe.

## Undo

**Enabled without UEFI lock** (default) - as an administrator, set these values to `0` (Microsoft notes that deleting them may not turn Credential Guard off - they must be `0`), then restart:

```powershell
Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\Lsa -Name LsaCfgFlags -Value 0 -Type DWord
New-Item -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard -Force | Out-Null
Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard -Name LsaCfgFlags -Value 0 -Type DWord
Restart-Computer
```

Or use an Intune **Settings catalog** policy: **Device Guard > Credential Guard = Disabled**.

**Enabled with UEFI lock** (`$UseUefiLock = $true`) - the setting is stored in the firmware. Follow Microsoft's *Disable Credential Guard with UEFI lock* procedure (bcdedit commands), which needs **someone at the device** to confirm a firmware prompt at restart.

Remove the script's assignment first, or it may run again.

## Troubleshooting

- **Script log on the device**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\CredentialGuardPlatformScript.log` - the state found, edition, requirement checks, policy check and each registry value written.
- **Intune Management Extension logs** in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`:
  - `IntuneManagementExtension.log` - when the script was received and run, and its result.
  - `AgentExecutor.log` - the PowerShell run itself, including exit code and any error output.
- **Event Viewer**: **Windows Logs > System**, source **Wininit** - Credential Guard (LsaIso) start events after the restart.

| Message | Cause and fix |
|---|---|
| `Not supported: Microsoft Windows 11 Pro` | Credential Guard needs Enterprise or Education. Upgrade the edition (Windows Enterprise E3/E5 subscription activation upgrades Pro automatically), then re-run. |
| `Not supported: the device does not report hardware virtualization support` | Turn on Intel VT-x / AMD-V (and VT-d / IOMMU for DMA protection) in the firmware. For VMs: use a Generation 2 VM on a Hyper-V host with an IOMMU. |
| `Not supported: UEFI Secure Boot is off` | Turn on Secure Boot in the firmware. Devices installed in legacy BIOS mode need converting to UEFI (`mbr2gpt`) first. |
| `Blocked by policy: ...` | A Group Policy or Intune policy turns Credential Guard or VBS off. Find it (`gpresult /h report.html`, or Intune **Devices > Configuration** and **Endpoint security > Account protection**) and change it. |
| Success, but Credential Guard isn't running after a restart | Check `msinfo32`. If VBS is **Enabled but not running**, a hardware requirement isn't met (often virtualization off in firmware or an incompatible hypervisor driver). Microsoft's hardware readiness tool shows which. |
| Wi-Fi / VPN prompts for credentials or fails after the restart | The connection uses MS-CHAPv2. Move it to certificate-based authentication (EAP-TLS / PEAP-TLS). |

**Test on one device without Intune:** run the script as SYSTEM with [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec), then restart:

```cmd
psexec -i -s powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Enable-CredentialGuard.ps1
```

## Exit codes

| Exit code | Meaning | What Intune does |
|---|---|---|
| `0` | Credential Guard is running, configured and waiting for a restart, or the device is excluded. | Reports **Success**. Doesn't run again unless the script changes or a new user signs in. |
| `1` | Requirements not met (edition, virtualization, Secure Boot), blocked by policy, or the script failed. See the log. | Reports **Failed** and runs it again at the next three check-ins. |

The script uses `0` (not `3010`) when a restart is needed, because Intune treats any non-zero exit code as a failure. The result message says **RESTART REQUIRED** instead.
