<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects non-compliant BitLocker encryption settings on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Checks the Windows (OS) drive and every fixed data drive.

    OS drive (only when it is already encrypted or encrypting - turning BitLocker on is done by
    the separate "Detect and Enable BitLocker" remediation):
      - MissingTpmProtector      : no TPM key protector
      - MissingRecoveryPassword  : no recovery password protector
      - WeakEncryptionMethod     : encryption method not in $AllowedEncryptionMethods

    Fixed data drives:
      - NotEncrypted             : BitLocker is off
      - EncryptionPaused         : encryption was paused
      - Decrypting               : the drive is being decrypted
      - MissingRecoveryPassword  : no recovery password protector
      - AutoUnlockOff            : the drive does not unlock automatically when Windows starts
      - WeakEncryptionMethod     : encryption method not in $AllowedEncryptionMethods
      - Locked                   : the drive is locked (it can't be checked)

    Drives whose mount point (for example 'D:') matches $ExcludeList are not checked.
    Removable drives are not checked.

    Exit codes (read by Intune):
      0 = All checked drives have compliant encryption settings.
      1 = One or more settings are non-compliant -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\EncryptionSettingsRemediation.log
#>

# Drives to skip by mount point (wildcards allowed), e.g. @('D:', 'E:')
$ExcludeList = @()

# Encryption methods that are compliant (Aes128, Aes256, XtsAes128, XtsAes256)
$AllowedEncryptionMethods = @('XtsAes128', 'XtsAes256')

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\EncryptionSettingsRemediation.log"

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

function Test-HasProtector {
    param($Volume, [string]$Type)
    return (@($Volume.KeyProtector | Where-Object { [string]$_.KeyProtectorType -eq $Type }).Count -gt 0)
}

# Returns the issue names for one volume
function Get-VolumeIssues {
    param($Volume, [bool]$IsOsVolume)

    $status = [string]$Volume.VolumeStatus
    $method = [string]$Volume.EncryptionMethod
    $encrypted = $status -in 'FullyEncrypted', 'EncryptionInProgress'

    if ($IsOsVolume) {
        if (-not $encrypted) { return }
        if (-not (Test-HasProtector -Volume $Volume -Type 'Tpm')) { 'MissingTpmProtector' }
        if (-not (Test-HasProtector -Volume $Volume -Type 'RecoveryPassword')) { 'MissingRecoveryPassword' }
        if ($method -notin $AllowedEncryptionMethods) { "WeakEncryptionMethod:$method" }
        return
    }

    if ([string]$Volume.LockStatus -eq 'Locked') { 'Locked'; return }
    switch ($status) {
        'FullyDecrypted'       { 'NotEncrypted'; return }
        'EncryptionPaused'     { 'EncryptionPaused' }
        'DecryptionInProgress' { 'Decrypting'; return }
        'DecryptionPaused'     { 'Decrypting'; return }
    }
    if (-not (Test-HasProtector -Volume $Volume -Type 'RecoveryPassword')) { 'MissingRecoveryPassword' }
    if (-not $Volume.AutoUnlockEnabled) { 'AutoUnlockOff' }
    if ($method -notin $AllowedEncryptionMethods) { "WeakEncryptionMethod:$method" }
}

function Get-FixedDriveMountPoints {
    @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop |
        ForEach-Object { $_.DeviceID })
}

function Get-EncryptionIssues {
    $fixedDrives = Get-FixedDriveMountPoints
    foreach ($volume in @(Get-BitLockerVolume -ErrorAction Stop)) {
        $mountPoint = [string]$volume.MountPoint
        if (Test-Excluded -Name $mountPoint) { continue }
        $isOs = ([string]$volume.VolumeType -eq 'OperatingSystem')
        if (-not $isOs -and $fixedDrives -notcontains $mountPoint) { continue }

        foreach ($issue in @(Get-VolumeIssues -Volume $volume -IsOsVolume $isOs)) {
            [pscustomobject]@{ MountPoint = $mountPoint; IsOs = $isOs; Issue = $issue }
        }
    }
}

try {
    $issues = @(Get-EncryptionIssues)

    if ($issues.Count -gt 0) {
        $labels = @($issues | ForEach-Object { "$($_.MountPoint) $($_.Issue)" })
        Write-Log "Found $($issues.Count) encryption setting issue(s): $($labels -join '; ')"
        Write-Output "Non-compliant encryption settings ($($issues.Count)): $($labels -join '; ')"
        exit 1
    }

    Write-Log 'All checked drives have compliant encryption settings.'
    Write-Output 'All checked drives have compliant encryption settings.'
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
