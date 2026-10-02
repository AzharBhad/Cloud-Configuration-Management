<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Removes the expired certificates found by Detect-ExpiredCertificates.ps1.

.DESCRIPTION
    Removes certificates from the stores in $StoreNames (default: personal store "My")
    that expired more than $ExpiredForDays days ago, using the same rules as the detection script.

    Which certificates are removed depends on how Intune runs the script:
      - As System (logged-on credentials = No)  -> device certificates  (Cert:\LocalMachine\My)
      - As the user (logged-on credentials = Yes) -> the signed-in user's certificates (Cert:\CurrentUser\My)

    Each certificate is removed together with its private key (Remove-Item -DeleteKey).
    If the key can't be deleted, the certificate is still removed and the leftover key is logged.

    Kept (never removed):
      - Certificates matching $ExcludeList.
      - Encryption certificates (Secure Email / EFS) when $KeepEncryptionCerts is $true.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = All expired certificates removed.
      1 = One or more expired certificates could not be removed.

.NOTES
    Run as      : System for device certificates, or the logged-on user for user certificates
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : System: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ExpiredCertificatesRemediation.log
                  User  : %TEMP%\ExpiredCertificatesRemediation.log
    No restart is needed.
#>

# Certificates to keep - keep in sync with the detection script
$ExcludeList = @(
    '*Microsoft Intune MDM Device CA*',   # Intune enrollment certificate
    '*MS-Organization-Access*'            # Microsoft Entra device certificate
)

# Certificate stores to clean - keep in sync with the detection script
$StoreNames = @('My')

# Only remove certificates that expired more than this many days ago - keep in sync with the detection script
$ExpiredForDays = 0

# Keep expired Secure Email / EFS certificates - keep in sync with the detection script
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
    $line = "{0} [REMEDIATE] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
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

function Remove-StaleCertificate {
    param([string]$StoreName, $Certificate)

    $label = "$StoreName\" + (Get-CertLabel -Certificate $Certificate)
    $path = "Cert:\$StoreLocation\$StoreName\$($Certificate.Thumbprint)"

    if ($Certificate.HasPrivateKey) {
        try {
            Remove-Item -Path $path -DeleteKey -ErrorAction Stop
            Write-Log "Removed $label and its private key."
            return $true
        }
        catch {
            Write-Log "Could not delete the private key of $label ($($_.Exception.Message)). Removing the certificate only."
        }
    }

    try {
        Remove-Item -Path $path -ErrorAction Stop
        Write-Log "Removed $label."
        return $true
    }
    catch {
        Write-Log "Failed to remove $label`: $($_.Exception.Message)"
        return $false
    }
}

try {
    Write-Log "Starting expired certificate removal in $StoreLocation."
    $now = Get-Date
    $failed = @()
    $removed = 0

    foreach ($storeName in $StoreNames) {
        $stale = @(Get-ChildItem -Path "Cert:\$StoreLocation\$storeName" -ErrorAction SilentlyContinue |
            Where-Object { Test-IsStale -Certificate $_ -Now $now })

        foreach ($certificate in $stale) {
            if (Remove-StaleCertificate -StoreName $storeName -Certificate $certificate) {
                $removed++
            }
            else {
                $failed += "$storeName\" + (Get-CertLabel -Certificate $certificate)
            }
        }
    }

    if ($failed.Count -gt 0) {
        $summary = "Removed $removed expired certificate(s) from $StoreLocation. Not removed: $($failed -join '; ')"
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) + '...' }
        Write-Log $summary
        Write-Output $summary
        exit 1
    }

    Write-Log "Removed $removed expired certificate(s) from $StoreLocation."
    Write-Output "Removed $removed expired certificate(s) from $StoreLocation."
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
