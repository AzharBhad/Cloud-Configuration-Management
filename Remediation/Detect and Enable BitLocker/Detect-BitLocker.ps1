<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects when BitLocker is not protecting the Windows (OS) drive on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Reads the BitLocker state of the OS drive ($env:SystemDrive, normally C:) and reports
    the device when the drive is:
      - Not encrypted                (VolumeStatus FullyDecrypted)
      - Encrypted but not protected  (protection suspended, or waiting for activation)
      - Encryption paused            (VolumeStatus EncryptionPaused)
      - Being decrypted              (VolumeStatus DecryptionInProgress / DecryptionPaused)

    Compliant when the drive is fully encrypted with protection On, or encryption is in progress.
    Devices whose computer name matches $ExcludeList are always reported as compliant.

    Exit codes (read by Intune):
      0 = BitLocker is protecting the OS drive (or encryption is in progress) -> remediation does not run.
      1 = BitLocker is off, suspended, paused or decrypting -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerRemediation.log
#>

# Computer names to skip (wildcards allowed), e.g. @('KIOSK-*', 'LAB-PC01')
$ExcludeList = @()

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerRemediation.log"

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

# Returns the issue name for a BitLocker state, or $null when the drive is protected
function Get-BitLockerIssue {
    param([string]$VolumeStatus, [string]$ProtectionStatus)
    switch ($VolumeStatus) {
        'FullyDecrypted'       { return 'NotEncrypted' }
        'EncryptionPaused'     { return 'EncryptionPaused' }
        'DecryptionInProgress' { return 'Decrypting' }
        'DecryptionPaused'     { return 'Decrypting' }
        'EncryptionInProgress' { return $null }
        'FullyEncrypted'       { if ($ProtectionStatus -eq 'On') { return $null } else { return 'ProtectionSuspended' } }
        default                { return "UnknownState:$VolumeStatus" }
    }
}

try {
    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Write-Log "$env:COMPUTERNAME is in the exclude list. Skipping."
        Write-Output "$env:COMPUTERNAME is excluded from the BitLocker check."
        exit 0
    }

    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    $volumeStatus = [string]$volume.VolumeStatus
    $protectionStatus = [string]$volume.ProtectionStatus
    $issue = Get-BitLockerIssue -VolumeStatus $volumeStatus -ProtectionStatus $protectionStatus
    $state = "$env:SystemDrive VolumeStatus=$volumeStatus, ProtectionStatus=$protectionStatus, EncryptionPercentage=$($volume.EncryptionPercentage)"

    if ($issue) {
        Write-Log "BitLocker issue '$issue': $state"
        Write-Output "BitLocker not protecting the OS drive ($issue): $state"
        exit 1
    }

    Write-Log "BitLocker OK: $state"
    Write-Output "BitLocker OK: $state"
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
