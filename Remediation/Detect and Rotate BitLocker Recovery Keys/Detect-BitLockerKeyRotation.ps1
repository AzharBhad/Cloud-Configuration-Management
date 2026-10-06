<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects when the BitLocker recovery password of the Windows (OS) drive is due for rotation
    on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Only runs on devices where the OS drive is BitLocker protected (fully encrypted with protection
    On, or encryption in progress). Other devices are reported as compliant - use the
    "Detect and Enable BitLocker" remediation for those.

    The OS drive needs rotation when:
      - It has no recovery password protector, or
      - The last rotation done by this remediation was more than $RotationDays days ago, or has
        never been done (the first run rotates every device once).

    The last rotation time is stored in HKLM:\SOFTWARE\IntuneRemediation\BitLockerKeyRotation
    (value LastRotation) by the remediation script.

    Devices whose computer name matches $ExcludeList are always reported as compliant.

    Exit codes (read by Intune):
      0 = Recovery password is current -> remediation does not run.
      1 = Rotation is due              -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerKeyRotationRemediation.log
#>

# Computer names to skip (wildcards allowed), e.g. @('KIOSK-*')
$ExcludeList = @()

# Rotate the recovery password when it is older than this many days
$RotationDays = 90

$StateKey = 'HKLM:\SOFTWARE\IntuneRemediation\BitLockerKeyRotation'
$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerKeyRotationRemediation.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} [DETECT] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Test-Excluded {
    param([string]$Name)
    foreach ($pattern in $ExcludeList) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

function Test-VolumeProtected {
    param([string]$VolumeStatus, [string]$ProtectionStatus)
    return ($VolumeStatus -eq 'EncryptionInProgress' -or
            ($VolumeStatus -eq 'FullyEncrypted' -and $ProtectionStatus -eq 'On'))
}

# Returns the reason rotation is due, or $null when the recovery password is current
function Get-RotationReason {
    param([int]$RecoveryPasswordCount, $LastRotation, [datetime]$Now)
    if ($RecoveryPasswordCount -eq 0) { return 'No recovery password protector' }
    if (-not $LastRotation) { return 'Never rotated by this remediation' }
    $age = ($Now - [datetime]$LastRotation).TotalDays
    if ($age -gt $RotationDays) { return ("Last rotated {0:N0} days ago (limit {1})" -f $age, $RotationDays) }
    return $null
}

function Get-LastRotation {
    $value = (Get-ItemProperty -Path $StateKey -Name 'LastRotation' -ErrorAction SilentlyContinue).LastRotation
    if (-not $value) { return $null }
    try { return [datetime]::Parse($value, [Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
}

try {
    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Write-Log "$env:COMPUTERNAME is in the exclude list. Skipping."
        Write-Output "$env:COMPUTERNAME is excluded from BitLocker key rotation."
        exit 0
    }

    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    if (-not (Test-VolumeProtected -VolumeStatus ([string]$volume.VolumeStatus) -ProtectionStatus ([string]$volume.ProtectionStatus))) {
        Write-Log "$env:SystemDrive is not BitLocker protected ($($volume.VolumeStatus), $($volume.ProtectionStatus)). Nothing to rotate."
        Write-Output "$env:SystemDrive is not BitLocker protected. Nothing to rotate."
        exit 0
    }

    $recoveryPasswords = @($volume.KeyProtector | Where-Object { [string]$_.KeyProtectorType -eq 'RecoveryPassword' })
    $lastRotation = Get-LastRotation
    $reason = Get-RotationReason -RecoveryPasswordCount $recoveryPasswords.Count -LastRotation $lastRotation -Now (Get-Date)

    if ($reason) {
        Write-Log "Rotation due: $reason"
        Write-Output "BitLocker recovery key rotation due: $reason"
        exit 1
    }

    Write-Log "Recovery password is current (last rotated $lastRotation)."
    Write-Output "BitLocker recovery key is current (last rotated $lastRotation)."
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
