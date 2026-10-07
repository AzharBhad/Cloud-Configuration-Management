<#
.SYNOPSIS
    Intune platform script.
    Removes expired, retired and legacy-CA certificates from the Windows certificate stores to
    prevent authentication and trust issues.

.DESCRIPTION
    Cleans up three kinds of certificates:
      - Expired       : certificates in the personal store that expired more than $ExpiredForDays days ago.
      - Retired       : any certificate whose thumbprint is listed in $RetiredThumbprints.
      - Legacy CA     : certificates issued by a retired certificate authority listed in
                        $LegacyAuthorities, and (SYSTEM only) that authority's own root and
                        intermediate CA certificates in the Trusted Root and Intermediate CA stores.

    Which stores are cleaned depends on how Intune runs the script:
      - As SYSTEM (logged on credentials = No)   -> device certificates:
            Cert:\LocalMachine\My  (expired, retired, issued by a legacy CA)
            Cert:\LocalMachine\Root and \CA  (legacy CA certificates and retired thumbprints only)
      - As the user (logged on credentials = Yes) -> the signed-in user's certificates:
            Cert:\CurrentUser\My   (expired, retired, issued by a legacy CA)
        The user's Root store is never changed - Windows would show the user a confirmation prompt.

    Never removed:
      - Certificates matching $ExcludeList (subject, issuer, friendly name or thumbprint).
      - Expired root and intermediate CA certificates that aren't on the legacy/retired lists -
        Windows keeps them on purpose to check older signed software.
      - Encryption certificates (Secure Email / EFS) while $KeepEncryptionCerts is $true - their
        private keys are still needed to open old encrypted email and files.

    Actions, in this order:
      1. Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit.
      2. Works out the context (SYSTEM or user) and the stores to clean.
      3. Finds the certificates to remove and logs the reason for each.
      4. Stops here if $ReportOnly is $true (nothing is changed).
      5. Exports each certificate (public part, .cer) to a backup folder so it can be re-imported.
      6. Removes each certificate, with its private key where there is one.
      7. Writes a summary line.

    The script is safe to run more than once: it only acts on certificates that still match.
    No restart is needed.

    Exit codes:
      0 = All matching certificates removed (or none found, or $ReportOnly).
      1 = One or more certificates could not be removed, or the script failed. See the log.

.NOTES
    Intune settings (Devices > Scripts and remediations > Platform scripts):
      Run this script using the logged on credentials : No for device certificates (SYSTEM - needed to
                                                        change LocalMachine stores); Yes for user
                                                        certificates (deploy a second copy)
      Enforce script signature check                  : No  (unless you sign the script)
      Run script in 64-bit PowerShell host            : Yes
    Log file: SYSTEM: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\CertificateCleanupPlatformScript.log
              User  : %TEMP%\CertificateCleanupPlatformScript.log
#>

# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------

# Retired certificate authorities. Matched against the certificate's Issuer (for leaf certificates)
# and Subject (for CA certificates in Root/CA), wildcards allowed. Empty = no legacy CA cleanup.
# e.g. @('*CN=Contoso Legacy Root CA*', '*CN=Contoso Issuing CA 01*')
$LegacyAuthorities = @()

# Specific certificates to remove from every store this script cleans, by thumbprint.
# e.g. @('3A1B2C3D4E5F60718293A4B5C6D7E8F901234567')
$RetiredThumbprints = @()

# Certificates to keep - matched against Subject, Issuer, FriendlyName and Thumbprint, wildcards allowed
$ExcludeList = @(
    '*Microsoft Intune MDM Device CA*',   # Intune enrollment certificate
    '*MS-Organization-Access*',           # Microsoft Entra device certificate
    '*MS-Organization-P2P-Access*'        # Microsoft Entra P2P certificates (Windows manages these)
)

# Personal stores cleaned of expired, retired and legacy-issued certificates
$LeafStores = @('My')

# Only remove certificates that expired more than this many days ago (0 = as soon as they expire)
$ExpiredForDays = 0

# Keep Secure Email / EFS certificates so old encrypted email and files can still be opened
$KeepEncryptionCerts = $true

# $true = only report what would be removed; change nothing
$ReportOnly = $false

# Where removed certificates are exported (public part only) so they can be re-imported
$BackupRoot = if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    "$env:ProgramData\IntuneCertCleanup\Backup"
} else {
    "$env:LOCALAPPDATA\IntuneCertCleanup\Backup"
}

# ---------------------------------------------------------------------------------------------
# Relaunch in 64-bit PowerShell when started in 32-bit
# ---------------------------------------------------------------------------------------------

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $powershell64) {
        & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
}

# ---------------------------------------------------------------------------------------------
# Context, stores and log
# ---------------------------------------------------------------------------------------------

$IsSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
$StoreLocation = if ($IsSystem) { 'LocalMachine' } else { 'CurrentUser' }
# CA stores are only cleaned as SYSTEM; the user's Root store would prompt the user
$CaStores = if ($IsSystem) { @('Root', 'CA') } else { @() }
$LogFile = if ($IsSystem) {
    "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\CertificateCleanupPlatformScript.log"
} else {
    "$env:TEMP\CertificateCleanupPlatformScript.log"
}

# ---------------------------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Test-MatchesAny {
    param([string[]]$Values, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        foreach ($value in $Values) {
            if ($value -and $value -like $pattern) { return $true }
        }
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

# Returns why a certificate should be removed, or $null to keep it.
# $IsCaStore is $true for Root and CA stores, which are never cleaned by expiry.
function Get-RemovalReason {
    param($Certificate, [bool]$IsCaStore, [datetime]$Now)

    if (Test-MatchesAny -Values @($Certificate.Subject, $Certificate.Issuer, $Certificate.FriendlyName, $Certificate.Thumbprint) -Patterns $ExcludeList) {
        return $null
    }

    $retired = @($RetiredThumbprints | ForEach-Object { ($_ -replace '\s', '').ToUpperInvariant() })
    if ($retired -contains ([string]$Certificate.Thumbprint).ToUpperInvariant()) { return 'RetiredThumbprint' }

    if ($IsCaStore) {
        if (Test-MatchesAny -Values @($Certificate.Subject) -Patterns $LegacyAuthorities) { return 'LegacyAuthority' }
        return $null
    }

    if ($KeepEncryptionCerts -and (Test-EncryptionCert -Certificate $Certificate)) { return $null }
    if (Test-MatchesAny -Values @($Certificate.Issuer) -Patterns $LegacyAuthorities) { return 'IssuedByLegacyAuthority' }
    if ($Certificate.NotAfter -lt $Now.AddDays(-$ExpiredForDays)) { return 'Expired' }
    return $null
}

function Get-CertLabel {
    param($Certificate)
    $name = if ($Certificate.Subject) { $Certificate.Subject } else { $Certificate.FriendlyName }
    return "{0} (issuer {1}, expires {2:yyyy-MM-dd}, {3})" -f $name, $Certificate.Issuer, $Certificate.NotAfter, $Certificate.Thumbprint
}

# Finds every certificate to remove in the stores this context cleans
function Get-CertificatesToRemove {
    param([datetime]$Now)
    $stores = @($LeafStores | ForEach-Object { @{ Name = $_; IsCa = $false } }) +
              @($CaStores | ForEach-Object { @{ Name = $_; IsCa = $true } })
    foreach ($store in $stores) {
        foreach ($certificate in @(Get-ChildItem -Path "Cert:\$StoreLocation\$($store.Name)" -ErrorAction SilentlyContinue)) {
            $reason = Get-RemovalReason -Certificate $certificate -IsCaStore $store.IsCa -Now $Now
            if ($reason) {
                [pscustomobject]@{ Store = $store.Name; Reason = $reason; Certificate = $certificate }
            }
        }
    }
}

function Export-CertificateBackup {
    param($Item, [string]$Folder)
    $file = Join-Path $Folder ("{0}-{1}.cer" -f $Item.Store, $Item.Certificate.Thumbprint)
    [IO.File]::WriteAllBytes($file, $Item.Certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
    return $file
}

# Removes one certificate, with its private key where possible. Returns $true when removed.
function Remove-CertificateItem {
    param($Item)
    $path = "Cert:\$StoreLocation\$($Item.Store)\$($Item.Certificate.Thumbprint)"
    $label = "$($Item.Store)\" + (Get-CertLabel -Certificate $Item.Certificate)

    if ($Item.Certificate.HasPrivateKey) {
        try {
            Remove-Item -Path $path -DeleteKey -ErrorAction Stop
            Write-Log "Removed [$($Item.Reason)] $label and its private key."
            return $true
        }
        catch {
            Write-Log "Could not delete the private key of $label ($($_.Exception.Message)). Removing the certificate only."
        }
    }
    try {
        Remove-Item -Path $path -ErrorAction Stop
        Write-Log "Removed [$($Item.Reason)] $label."
        return $true
    }
    catch {
        Write-Log "Failed to remove $label`: $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

try {
    $now = Get-Date
    Write-Log "===== Certificate cleanup started ($StoreLocation; stores: $(($LeafStores + $CaStores) -join ', '); ReportOnly=$ReportOnly) ====="
    if (-not $IsSystem) { Write-Log 'Running as the user: Root and CA stores are not cleaned.' }

    # 3. Find
    $items = @(Get-CertificatesToRemove -Now $now)
    foreach ($item in $items) {
        Write-Log "Found [$($item.Reason)] $($item.Store)\$(Get-CertLabel -Certificate $item.Certificate)"
    }
    $byReason = @($items | Group-Object -Property Reason | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '

    if ($items.Count -eq 0) {
        $message = "No expired, retired or legacy CA certificates found in $StoreLocation."
        Write-Log $message
        Write-Output $message
        exit 0
    }

    # 4. Report only
    if ($ReportOnly) {
        $message = "Report only: $($items.Count) certificate(s) would be removed from $StoreLocation ($byReason). See the log."
        Write-Log $message
        Write-Output $message
        exit 0
    }

    # 5. Backup
    $backupFolder = Join-Path $BackupRoot $now.ToString('yyyyMMdd-HHmmss')
    New-Item -Path $backupFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    foreach ($item in $items) {
        try {
            [void](Export-CertificateBackup -Item $item -Folder $backupFolder)
        }
        catch {
            Write-Log "Backup of $($item.Certificate.Thumbprint) failed: $($_.Exception.Message)"
        }
    }
    Write-Log "Backed up $($items.Count) certificate(s) to $backupFolder"

    # 6. Remove
    $failed = @()
    foreach ($item in $items) {
        if (-not (Remove-CertificateItem -Item $item)) {
            $failed += "$($item.Store)\$($item.Certificate.Thumbprint)"
        }
    }

    # 7. Summary
    $removed = $items.Count - $failed.Count
    if ($failed.Count -gt 0) {
        $message = "Removed $removed of $($items.Count) certificate(s) from $StoreLocation ($byReason). Not removed: $($failed -join ', '). Backup: $backupFolder"
        Write-Log $message
        Write-Output $message
        exit 1
    }

    $message = "Removed $removed certificate(s) from $StoreLocation ($byReason). Backup: $backupFolder"
    Write-Log $message
    Write-Output $message
    exit 0
}
catch {
    $message = "Certificate cleanup failed: $($_.Exception.Message)"
    Write-Log $message
    Write-Output $message
    exit 1
}
