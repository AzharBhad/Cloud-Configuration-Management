<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects expired certificates in the personal certificate store on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Checks the stores in $StoreNames (default: personal store "My") for certificates
    that expired more than $ExpiredForDays days ago.

    Which certificates are checked depends on how Intune runs the script:
      - As System (logged-on credentials = No)  -> device certificates  (Cert:\LocalMachine\My)
      - As the user (logged-on credentials = Yes) -> the signed-in user's certificates (Cert:\CurrentUser\My)

    Not counted as stale:
      - Certificates matching $ExcludeList (subject, issuer, friendly name or thumbprint, wildcards allowed).
      - Encryption certificates (Secure Email / EFS) when $KeepEncryptionCerts is $true, because their
        private keys are still needed to open old encrypted email and files.

    Exit codes (read by Intune):
      0 = No expired certificates found -> device is compliant, remediation does not run.
      1 = Expired certificates found    -> Intune runs the remediation script.

.NOTES
    Run as      : System for device certificates, or the logged-on user for user certificates
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : System: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ExpiredCertificatesRemediation.log
                  User  : %TEMP%\ExpiredCertificatesRemediation.log
#>

# Certificates to keep - matched against Subject, Issuer, FriendlyName and Thumbprint, wildcards allowed
$ExcludeList = @(
    '*Microsoft Intune MDM Device CA*',   # Intune enrollment certificate
    '*MS-Organization-Access*'            # Microsoft Entra device certificate
)

# Certificate stores to clean (names under LocalMachine / CurrentUser). Do not add Root or CA - see README.
$StoreNames = @('My')

# Only count certificates that expired more than this many days ago (0 = as soon as they expire)
$ExpiredForDays = 0

# Keep expired Secure Email / EFS certificates so old encrypted email and files can still be opened
$KeepEncryptionCerts = $true

$IsSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
$StoreLocation = if ($IsSystem) { 'LocalMachine' } else { 'CurrentUser' }
$LogFile = if ($IsSystem) {
    "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\ExpiredCertificatesRemediation.log"
} else {
    "$env:TEMP\ExpiredCertificatesRemediation.log"
}

function Write-Log {
    param([string]$Message)
    $line = "{0} [DETECT] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Test-Excluded {
    param($Certificate)
    foreach ($pattern in $ExcludeList) {
        if ($Certificate.Subject -like $pattern -or
            $Certificate.Issuer -like $pattern -or
            $Certificate.FriendlyName -like $pattern -or
            $Certificate.Thumbprint -like $pattern) { return $true }
    }
    return $false
}

function Test-EncryptionCert {
    param($Certificate)
    # 1.3.6.1.5.5.7.3.4 = Secure Email, 1.3.6.1.4.1.311.10.3.4 = Encrypting File System
    foreach ($eku in $Certificate.EnhancedKeyUsageList) {
        if ($eku.ObjectId -in '1.3.6.1.5.5.7.3.4', '1.3.6.1.4.1.311.10.3.4') { return $true }
    }
    return $false
}

function Test-IsStale {
    param($Certificate, [datetime]$Now)
    if ($Certificate.NotAfter -ge $Now.AddDays(-$ExpiredForDays)) { return $false }
    if (Test-Excluded -Certificate $Certificate) { return $false }
    if ($KeepEncryptionCerts -and (Test-EncryptionCert -Certificate $Certificate)) { return $false }
    return $true
}

function Get-CertLabel {
    param($Certificate)
    $name = if ($Certificate.Subject) { $Certificate.Subject } else { $Certificate.FriendlyName }
    return "{0} (expired {1:yyyy-MM-dd}, {2})" -f $name, $Certificate.NotAfter, $Certificate.Thumbprint
}

function Get-StaleCertificates {
    $now = Get-Date
    foreach ($storeName in $StoreNames) {
        $path = "Cert:\$StoreLocation\$storeName"
        Get-ChildItem -Path $path -ErrorAction SilentlyContinue |
            Where-Object { Test-IsStale -Certificate $_ -Now $now } |
            ForEach-Object { "$storeName\" + (Get-CertLabel -Certificate $_) }
    }
}

try {
    $found = @(Get-StaleCertificates)

    if ($found.Count -gt 0) {
        Write-Log "Found $($found.Count) expired certificate(s) in $StoreLocation`: $($found -join '; ')"
        # Intune shows the last line of output in the admin center (max 2048 characters)
        $summary = "Expired certificates in $StoreLocation ({0}): {1}" -f $found.Count, ($found -join '; ')
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) + '...' }
        Write-Output $summary
        exit 1
    }

    Write-Log "No expired certificates found in $StoreLocation."
    Write-Output "No expired certificates found in $StoreLocation."
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
