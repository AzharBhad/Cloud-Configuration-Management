# Detect and Remove Expired Certificates

An Intune **Remediations** package that finds expired certificates in the personal certificate store on Windows 10 and Windows 11 devices and removes them, together with their private keys. Intune runs it every 7 days, so certificates that expire later (for example old SCEP or PKCS certificates after renewal) are cleaned up on the next run.

Expired certificates left in the store can be picked by apps, VPN and Wi-Fi clients instead of the valid one, which causes authentication failures and certificate selection prompts.

## Files

| File | Purpose |
|---|---|
| `Detect-ExpiredCertificates.ps1` | Detection script. Exits `1` if any expired certificate is found, `0` if none. |
| `Remediate-ExpiredCertificates.ps1` | Remediation script. Runs only when detection exits `1`, and removes every expired certificate it finds. |
| `README.md` | This document. |

## What the remediation does

Intune Remediations run as a pair of scripts on a schedule:

1. Intune runs the **detection script** on the device.
2. If no expired certificates are found, the device is reported as **Without issues** and nothing else happens.
3. If expired certificates are found, Intune runs the **remediation script**, which removes them.
4. Intune runs the **detection script again** to confirm the result and reports the device as **Issue fixed** or **Failed**.
5. The cycle repeats every 7 days.

### Device certificates or user certificates

The same scripts work for both. Which certificates they clean depends on the **Run this script using the logged-on credentials** setting in Intune:

| Setting | Runs as | Certificates cleaned | Typical certificates there |
|---|---|---|---|
| **No** | System | Device: `Cert:\LocalMachine\My` | Device SCEP/PKCS certificates for Wi-Fi, VPN, 802.1X |
| **Yes** | Signed-in user | User: `Cert:\CurrentUser\My` | User SCEP/PKCS certificates, client authentication certificates |

To clean both, create **two** remediations from the same scripts: one with the setting **No** and one with **Yes**.

### What counts as stale

A certificate is removed when **all** of these are true:

- It is in a store listed in `$StoreNames` (default: the personal store `My` only).
- It expired more than `$ExpiredForDays` days ago (default `0`: as soon as it expires).
- It does not match anything in `$ExcludeList`.
- It is not an encryption certificate (Secure Email or EFS), unless `$KeepEncryptionCerts` is set to `$false`.

### Kept by default

| Kept | Why |
|---|---|
| Certificates issued by **Microsoft Intune MDM Device CA** | The device's Intune enrollment certificate. Removing it, even expired, can break Intune management. |
| **MS-Organization-Access** certificates | The device's Microsoft Entra join certificate. |
| **Secure Email** and **EFS** certificates | Their private keys are still needed to open old encrypted email and files. Deleting them makes that content unreadable for good. |
| Everything in the **Root** and **Intermediate CA** stores | Windows keeps expired root and intermediate certificates on purpose. They are still used to check older signed and timestamped software. Do not add `Root` or `CA` to `$StoreNames`. |

### How each certificate is removed

| Step | What happens |
|---|---|
| Certificate with a private key | `Remove-Item Cert:\<Location>\My\<Thumbprint> -DeleteKey` removes the certificate and its private key. |
| Private key can't be deleted | The certificate is still removed, and the leftover key is logged. Some smart card and TPM-protected keys can't be deleted this way. |
| Certificate without a private key | `Remove-Item Cert:\<Location>\My\<Thumbprint>` |

No restart is needed. Removing certificates takes seconds, so the scripts have no time limits of their own.

### Changing what is kept or removed (optional)

At the top of **both** scripts:

```powershell
# Keep certificates by Subject, Issuer, FriendlyName or Thumbprint (wildcards allowed)
$ExcludeList = @(
    '*Microsoft Intune MDM Device CA*',
    '*MS-Organization-Access*',
    '*CN=Legacy App*'
)

# Only remove certificates that expired more than 30 days ago
$ExpiredForDays = 30

# Also remove expired Secure Email / EFS certificates (not recommended)
$KeepEncryptionCerts = $false
```

All four settings (`$ExcludeList`, `$StoreNames`, `$ExpiredForDays`, `$KeepEncryptionCerts`) must match in both scripts. Otherwise detection keeps finding certificates that remediation won't remove, and the device is reported as **Failed** on every run.

## Prerequisites

- Devices running **Windows 10 or Windows 11** (Enterprise, Professional or Education), enrolled in Intune and Microsoft Entra joined or hybrid joined.
- One of these licenses for the users: Windows 10/11 Enterprise E3 or E5, Windows 10/11 Education A3 or A5, or Windows 10/11 VDA per user.
- An Intune role that can create and assign Remediations, such as Intune Administrator.

## Step-by-step: create the remediation in Intune

Do these steps once for device certificates. Repeat them with the changes noted for user certificates if you want both.

1. Sign in to the **Microsoft Intune admin center**: <https://intune.microsoft.com>.
2. Go to **Devices > Manage devices > Scripts and remediations**, open the **Remediations** tab, and select **+ Create**.
3. **Basics**
   - **Name**: `Detect and Remove Expired Certificates - Device` (or `- User`)
   - **Description**: `Removes expired certificates from the personal certificate store. Runs every 7 days.`
   - **Publisher**: your name or team.
   - Select **Next**.
4. **Settings**
   - **Detection script file**: upload `Detect-ExpiredCertificates.ps1`.
   - **Remediation script file**: upload `Remediate-ExpiredCertificates.ps1`.
   - **Run this script using the logged-on credentials**: **No** for device certificates (runs as SYSTEM). **Yes** for user certificates.
   - **Enforce script signature check**: **No** (unless you sign the scripts).
   - **Run script in 64-bit PowerShell**: **Yes**.
   - Select **Next**.
5. **Scope tags**: choose scope tags if you use them, then select **Next**.
6. **Assignments**
   - Under **Included groups**, select a **device group** for the device version, or a **user group** for the user version. Test on a small pilot group first.
   - Next to the group, select the schedule (it shows **Daily** by default) and set:
     - **Frequency**: **Daily**
     - **Repeats every**: **7** days
     - **Start time**: a time devices are usually on, for example `12:00`
     - **Use UTC**: as you prefer
   - Select **Apply**, then **Next**.
7. **Review + create**: check the settings and select **Create**.

## Step-by-step: check the results

1. Go to **Devices > Manage devices > Scripts and remediations > Remediations** and open the remediation.
2. **Overview** shows how many devices are **Without issues**, **With issues**, **Issue fixed** and **Failed**.
3. **Device status** lists each device. Add the columns **Pre-remediation detection output**, **Remediation output** and **Post-remediation detection output** to see which certificates were found (subject, expiry date and thumbprint) and how many were removed.
4. To run it on one device right away instead of waiting for the schedule, open the device under **Devices > All devices** and select **... > Run remediation**.

## Troubleshooting

- **Log file on the device**
  - Device version: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ExpiredCertificatesRemediation.log`
  - User version: `%TEMP%\ExpiredCertificatesRemediation.log` in the user's profile. Users can't write to the Intune log folder.

  Both scripts log every certificate found and whether it was removed.
- **Intune Management Extension log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log` shows when the scripts ran and their exit codes.
- **See the certificates yourself**: open `certlm.msc` (device) or `certmgr.msc` (user) > **Personal > Certificates**, or run:
  ```powershell
  Get-ChildItem Cert:\LocalMachine\My | Where-Object NotAfter -lt (Get-Date) | Select-Object Subject, Issuer, NotAfter, Thumbprint
  ```
- **Device reports "Failed"**: look in the log for `Failed to remove`. Usually the certificate is in use or protected by a smart card or TPM. Remove it by hand, or add its thumbprint to `$ExcludeList`.
- **"Could not delete the private key"**: the certificate was removed but its key was left on the device. This is not counted as a failure.
- **An Intune certificate profile shows an error after cleanup**: Intune reissues certificates from SCEP/PKCS profiles on the next sync. If a profile keeps failing, check that it is still assigned and that the certificate connector or NDES server is working.
- **User version shows "Without issues" on every device**: it only runs when a user is signed in, and it only checks that user's certificates.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | `0` | No expired certificates found. Remediation does not run. |
| Detection | `1` | Expired certificates found. Intune runs the remediation script. |
| Remediation | `0` | All expired certificates removed. |
| Remediation | `1` | One or more expired certificates could not be removed. See the log. |
