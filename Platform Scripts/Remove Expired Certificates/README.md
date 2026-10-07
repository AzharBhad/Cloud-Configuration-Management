# Remove Expired Certificates

An Intune **platform script** that removes old, invalid and retired certificates from the certificate stores on Windows 10 and Windows 11 devices.

Why use it:

- **Removes expired certificates.** Old certificates left in the personal store can be picked by Wi-Fi, VPN, browsers and apps instead of the valid one. That causes failed sign-ins and certificate selection prompts.
- **Removes retired certificates.** Removes any certificate you list by thumbprint, for example after a key compromise or a certificate replacement.
- **Cleans up after a legacy certificate authority.** When you retire a CA (any CA - you list it), the script removes the certificates it issued, plus its own root and intermediate certificates from the trusted stores, so devices stop trusting it.
- **Prevents authentication and trust issues.** Devices are left with only current, trusted certificates.

Every removed certificate is **backed up first** (public part, `.cer`), and a **report-only** mode lets you see what would be removed before changing anything.

## Files

| File | Purpose |
|---|---|
| `Remove-StaleCertificates.ps1` | The platform script you upload to Intune. |
| `README.md` | This document. |

## Typical actions

### When to use this script

| Scenario | Why this script helps |
|---|---|
| **Retiring a certificate authority** (PKI migration, moving to Microsoft Cloud PKI, an old ADCS server) | Removes everything the old CA issued and stops devices trusting it. Set `$LegacyAuthorities`. |
| **Certificate replaced or compromised** | Removes a specific certificate from every device. Set `$RetiredThumbprints`. |
| **Wi-Fi / VPN authentication problems** | Removes expired client certificates that clients pick by mistake. |
| **After a migration** (from Configuration Manager, another MDM, or a tenant move) | Cleans up certificates from the old environment. |
| **One-time clean-up** before a security review | Run in **report-only** mode first, then for real. |

> A platform script runs **once** per device. For ongoing removal of certificates as they expire, use the **Detect and Remove Expired Certificates** remediation in `Remediation/`, which runs on a schedule.

### Device certificates and user certificates

The script cleans different stores depending on the **Run this script using the logged on credentials** setting:

| Setting | Runs as | Stores cleaned |
|---|---|---|
| **No** | SYSTEM | `LocalMachine\My` (expired, retired, issued by a legacy CA), plus `LocalMachine\Root` and `LocalMachine\CA` (legacy CA certificates and retired thumbprints only) |
| **Yes** | Signed-in user | `CurrentUser\My` (expired, retired, issued by a legacy CA) |

To clean both, add the script **twice** in Intune: once with **No** (assigned to devices) and once with **Yes** (assigned to users). As the user, the Root store is never changed, because Windows would show the user a confirmation prompt.

### What gets removed

| Reason (in the log) | Which certificates | Stores |
|---|---|---|
| `Expired` | Expired more than `$ExpiredForDays` days ago (default 0) | Personal (`My`) only |
| `IssuedByLegacyAuthority` | Issuer matches `$LegacyAuthorities` - even if not expired | Personal (`My`) |
| `LegacyAuthority` | The legacy CA's own certificate: subject matches `$LegacyAuthorities` | Root and CA (SYSTEM only) |
| `RetiredThumbprint` | Thumbprint is in `$RetiredThumbprints` | Every store the script cleans |

### What is never removed

| Kept | Why |
|---|---|
| Anything matching `$ExcludeList` | By default: the **Intune enrollment** certificate (Microsoft Intune MDM Device CA), the **Microsoft Entra device** certificate (MS-Organization-Access) and Entra **P2P** certificates. Removing them can break Intune management or Entra sign-in. |
| Expired **root and intermediate** CA certificates not on your lists | Windows keeps expired roots on purpose: they are still used to check older signed and timestamped software. Root/CA stores are only cleaned for the CAs and thumbprints **you** list. |
| **Secure Email** and **EFS** certificates (while `$KeepEncryptionCerts` is `$true`) | Their private keys are needed to open old encrypted email and files. Deleting them makes that content unreadable for good. Listing a thumbprint in `$RetiredThumbprints` still removes it. |

### What the script does on the device

| Step | Action | What happens | When it is skipped |
|---|---|---|---|
| 1 | 64-bit check | Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit. | Already 64-bit. |
| 2 | Context | Works out SYSTEM or user, and which stores to clean. | - |
| 3 | Find | Checks every certificate in those stores against the rules above and logs each match with its reason. | - |
| 4 | Report only | Stops without changing anything and reports how many would be removed. | `$ReportOnly` is `$false` (default). |
| 5 | Back up | Exports each certificate's public part to `<backup folder>\<yyyyMMdd-HHmmss>\<store>-<thumbprint>.cer`. | Nothing to remove. |
| 6 | Remove | Removes each certificate with its private key (`Remove-Item -DeleteKey`). If the key can't be deleted (some smart card / TPM keys), the certificate is still removed and the leftover key is logged. | Nothing to remove. |
| 7 | Summary | Writes one line: how many were removed, by reason, and the backup folder. | - |

No restart is needed. Running it again is safe - it only acts on certificates that still match.

## Settings in the script

At the top of `Remove-StaleCertificates.ps1`:

| Setting | Default | What it does |
|---|---|---|
| `$LegacyAuthorities` | `@()` (off) | Retired CAs, matched against the **Issuer** of personal certificates and the **Subject** of Root/CA certificates. Wildcards allowed. |
| `$RetiredThumbprints` | `@()` (off) | Thumbprints of specific certificates to remove. Spaces and upper/lower case don't matter. |
| `$ExcludeList` | Intune MDM, MS-Organization-Access, MS-Organization-P2P-Access | Certificates to keep, matched on Subject, Issuer, FriendlyName or Thumbprint. |
| `$LeafStores` | `@('My')` | Personal stores to clean. |
| `$ExpiredForDays` | `0` | Only remove certificates that expired more than this many days ago. |
| `$KeepEncryptionCerts` | `$true` | Keep Secure Email / EFS certificates. |
| `$ReportOnly` | `$false` | `$true` = report what would be removed and change nothing. |
| `$BackupRoot` | SYSTEM: `C:\ProgramData\IntuneCertCleanup\Backup` - user: `%LOCALAPPDATA%\IntuneCertCleanup\Backup` | Where removed certificates are backed up. |

Example - retire an old ADCS hierarchy and one compromised certificate, keep certificates for 30 days after expiry, and do a dry run first:

```powershell
$LegacyAuthorities = @(
    '*CN=Contoso Root CA 2010*'
    '*CN=Contoso Issuing CA 01*'
)
$RetiredThumbprints = @('3A1B2C3D4E5F60718293A4B5C6D7E8F901234567')
$ExpiredForDays = 30
$ReportOnly = $true
```

Find a CA's exact name with `certlm.msc` (device) or `certmgr.msc` (user): open the certificate and copy **Issued By** / **Issued To**, or run `Get-ChildItem Cert:\LocalMachine\Root | Select-Object Subject, Thumbprint`.

## How Intune runs it

| Intune behavior | What it means for this script |
|---|---|
| **Runs once** per device | One clean-up per device. Certificates that expire later are not removed - use the **Detect and Remove Expired Certificates** remediation for that. |
| **Re-runs after you change the script** | Changing `$LegacyAuthorities`, `$RetiredThumbprints` or turning off `$ReportOnly` and uploading again runs the clean-up again on every device. Safe - only matching certificates are touched. |
| **Re-runs for every new user** who signs in (device assignment) | Safe - the device stores are cleaned again, usually with nothing left to remove. |
| **Retries 3 times** after a failure | Certificates that couldn't be removed (in use, protected) get three more tries. |
| **30-minute time limit** | The script takes seconds. |
| **Runs before Win32 apps** | Certificates installed later by apps are not checked until the script runs again. |

## Prerequisites

- **Windows 10 or Windows 11** (Pro, Enterprise or Education).
- Devices **enrolled in Intune** and **Microsoft Entra joined** or **hybrid joined**. Devices that are only Entra *registered* don't receive platform scripts.
- For a legacy CA clean-up: the **replacement certificates already deployed** (SCEP/PKCS profiles from the new CA, and its trusted certificate profile). Otherwise Wi-Fi, VPN and other certificate-based sign-ins will stop working when the old certificates are removed.
- If a **Group Policy or Intune trusted certificate profile** still deploys the legacy CA, remove that first - otherwise the certificate comes back.
- An Intune role that can add platform scripts, such as **Intune Administrator** or **Policy and Profile Manager**.

## Step-by-step: add the script in Intune

1. Edit the settings at the top of `Remove-StaleCertificates.ps1`. For a first run, set `$ReportOnly = $true`.
2. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
3. Go to **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**.
4. **Basics**
   - **Name**: `Remove Expired Certificates - Device` (or `- User` for the user copy)
   - **Description**: `Removes expired, retired and legacy CA certificates. Backs up each certificate first.`
   - Select **Next**.
5. **Script settings**
   - **Script location**: browse to `Remove-StaleCertificates.ps1`.
   - **Run this script using the logged on credentials**: **No** for device certificates - the script must run as **SYSTEM** to change the device (LocalMachine) stores. **Yes** for the user copy, which cleans the signed-in user's own certificates.
   - **Enforce script signature check**: **No** (unless you sign the script).
   - **Run script in 64-bit PowerShell host**: **Yes**. (The script also relaunches itself in 64-bit if left at No.)
   - Select **Next**.
6. **Scope tags**: choose scope tags if you use them, then select **Next**.
7. **Assignments**
   - Device copy: select a **device group**, for example all Windows 10/11 corporate devices.
   - User copy: select a **user group** - it runs for those users on their devices.
   - Start with a small **pilot group**. Select **Next**.
8. **Review + add**: check the settings and select **Add**.
9. After checking the report-only results, set `$ReportOnly = $false` and upload the script again (**Properties > Script settings**). Intune runs it again on every assigned device.

## Step-by-step: check the results

1. Go to **Devices > Scripts and remediations > Platform scripts** and open the script.
2. Open **Device status** (device copy) or **User status** (user copy):
   - **Success** - every matching certificate was removed, nothing matched, or it ran in report-only mode.
   - **Failed** - one or more certificates couldn't be removed. Intune retries 3 times.
3. The summary line is stored as the script's result message, available through Microsoft Graph (beta): `deviceManagement/deviceManagementScripts/{id}/deviceRunStates`, property `resultMessage`. For example: `Removed 4 certificate(s) from LocalMachine (Expired x3, LegacyAuthority x1). Backup: ...`.
4. Check a device:
   ```powershell
   Get-Content C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\CertificateCleanupPlatformScript.log -Tail 30
   Get-ChildItem Cert:\LocalMachine\My | Where-Object NotAfter -lt (Get-Date) | Select-Object Subject, Issuer, NotAfter
   Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like '*Contoso Root CA 2010*'
   ```
5. Test Wi-Fi, VPN and other certificate-based sign-ins on a pilot device.

## Running it again

- **For all assigned devices:** edit the script (any change, even a comment or a setting), then upload the new version in the script's **Properties > Script settings**. Intune runs it again on every assigned device.
- **For specific devices:** remove them from the assigned group, wait for the next check-in, then add them back. Or assign the script to a new group containing just those devices.
- **New users:** a device-assigned script runs again when a new user signs in.

## Undo

Every removed certificate's **public part** is in the backup folder (`C:\ProgramData\IntuneCertCleanup\Backup\<date-time>\` for the device copy). Re-import a CA certificate or a certificate without a private key:

```powershell
# Root / intermediate CA certificate (run as administrator)
Import-Certificate -FilePath 'C:\ProgramData\IntuneCertCleanup\Backup\20261007-091500\Root-<thumbprint>.cer' -CertStoreLocation Cert:\LocalMachine\Root

# Personal certificate (public part only)
Import-Certificate -FilePath '...\My-<thumbprint>.cer' -CertStoreLocation Cert:\LocalMachine\My
```

**Private keys can't be restored** - they are deleted with the certificate. A personal certificate brought back from the backup has no private key, so it can't be used for sign-in. Issue a new certificate instead (Intune SCEP/PKCS profiles reissue automatically). That is why report-only mode and a pilot group come first.

Remove the script's assignment first, or it may run again.

## Troubleshooting

- **Script log**: device copy `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\CertificateCleanupPlatformScript.log`; user copy `%TEMP%\CertificateCleanupPlatformScript.log` in the user's profile. Lists every certificate found with its reason, the backup folder, and each removal.
- **Intune Management Extension logs** in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs`:
  - `IntuneManagementExtension.log` - when the script was received and run, and its result.
  - `AgentExecutor.log` - the PowerShell run itself, including exit code and any error output.

| Problem | Cause and fix |
|---|---|
| `Failed to remove ...` | The certificate is in use or protected (smart card, TPM, some CA stores). Remove it by hand in `certlm.msc` / `certmgr.msc`, or add it to `$ExcludeList`. |
| A legacy CA certificate comes back | A Group Policy (Public Key Policies > Trusted Root Certification Authorities) or an Intune trusted certificate profile still deploys it. Remove it there, then run the script again. |
| Wi-Fi / VPN stopped working after the clean-up | The replacement certificate from the new CA isn't on the device yet. Check the SCEP/PKCS and trusted certificate profiles in Intune; restore the old CA certificate from the backup until they are deployed. |
| Nothing removed | Check `$LegacyAuthorities` patterns against the exact Issuer / Subject text (use wildcards, for example `'*CN=Contoso Issuing CA 01*'`), and check the script ran in the right context (SYSTEM for device stores). |
| `Could not delete the private key ...` | The certificate was removed but its key was left on the device (some smart card / TPM keys). Not counted as a failure. |
| User copy didn't touch Root | By design - removing from the user's Root store prompts the user. Clean Root with the device (SYSTEM) copy. |

**Test on one device without Intune:** run the script as SYSTEM with [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec), with `$ReportOnly = $true` first:

```cmd
psexec -i -s powershell.exe -ExecutionPolicy Bypass -File C:\Temp\Remove-StaleCertificates.ps1
```

## Exit codes

| Exit code | Meaning | What Intune does |
|---|---|---|
| `0` | All matching certificates removed, none found, or report-only mode. | Reports **Success**. Doesn't run again unless the script changes or a new user signs in. |
| `1` | One or more certificates couldn't be removed, or the script failed. See the log. | Reports **Failed** and runs it again at the next three check-ins. |
