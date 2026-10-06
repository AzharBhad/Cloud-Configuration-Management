<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Rotates the BitLocker recovery password of the Windows (OS) drive.

.DESCRIPTION
    Steps, in this order:
      1. Adds a NEW recovery password protector to the OS drive.
      2. Backs up the new recovery password to Microsoft Entra ID (Entra joined devices)
         and/or Active Directory (domain/hybrid joined devices).
      3. Only if the backup succeeded: removes the OLD recovery password protectors and records
         the rotation time in HKLM:\SOFTWARE\IntuneRemediation\BitLockerKeyRotation.
         If the backup failed: removes the new protector again and keeps the old ones,
         so the drive always has a recovery password that is saved somewhere.

    The drive stays encrypted the whole time; nothing is decrypted and the device is not restarted.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    The rotation interval itself is $RotationDays in the detection script. See README.md.

    Exit codes (read by Intune):
      0 = Recovery password rotated and backed up.
      1 = Rotation failed or was skipped; the old recovery password is still in place.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerKeyRotationRemediation.log
#>

# Computer names to skip (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

$StateKey = 'HKLM:\SOFTWARE\IntuneRemediation\BitLockerKeyRotation'
$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerKeyRotationRemediation.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} [REMEDIATE] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
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

function Get-JoinState {
    param([string[]]$DsregOutput)
    return @{
        EntraJoined  = [bool]($DsregOutput -match '^\s*AzureAdJoined\s*:\s*YES')
        DomainJoined = [bool]($DsregOutput -match '^\s*DomainJoined\s*:\s*YES')
    }
}

function Get-RecoveryPasswordIds {
    param([string]$MountPoint)
    $volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    return @($volume.KeyProtector |
        Where-Object { [string]$_.KeyProtectorType -eq 'RecoveryPassword' } |
        ForEach-Object { $_.KeyProtectorId })
}

# Returns $true when the protector was backed up to at least one directory
function Backup-RecoveryPassword {
    param([string]$MountPoint, [string]$KeyProtectorId)

    $join = Get-JoinState -DsregOutput @(& "$env:SystemRoot\System32\dsregcmd.exe" /status)
    Write-Log "Join state: EntraJoined=$($join.EntraJoined), DomainJoined=$($join.DomainJoined)"

    $backedUp = $false
    if ($join.EntraJoined) {
        try {
            BackupToAAD-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $KeyProtectorId -ErrorAction Stop | Out-Null
            Write-Log "Recovery password $KeyProtectorId backed up to Microsoft Entra ID."
            $backedUp = $true
        }
        catch {
            Write-Log "Backup of $KeyProtectorId to Microsoft Entra ID failed: $($_.Exception.Message)"
        }
    }
    if ($join.DomainJoined) {
        try {
            Backup-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $KeyProtectorId -ErrorAction Stop | Out-Null
            Write-Log "Recovery password $KeyProtectorId backed up to Active Directory."
            $backedUp = $true
        }
        catch {
            Write-Log "Backup of $KeyProtectorId to Active Directory failed: $($_.Exception.Message)"
        }
    }
    return $backedUp
}

function Exit-Remediation {
    param([int]$Code, [string]$Message)
    Write-Log $Message
    Write-Output $Message
    exit $Code
}

try {
    $mountPoint = $env:SystemDrive
    Write-Log "Starting BitLocker recovery key rotation for $mountPoint."

    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Exit-Remediation 0 "$env:COMPUTERNAME is excluded from BitLocker key rotation."
    }

    $volume = Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop
    if (-not (Test-VolumeProtected -VolumeStatus ([string]$volume.VolumeStatus) -ProtectionStatus ([string]$volume.ProtectionStatus))) {
        Exit-Remediation 0 "$mountPoint is not BitLocker protected. Nothing to rotate."
    }

    # 1. Add a new recovery password
    $oldIds = Get-RecoveryPasswordIds -MountPoint $mountPoint
    Add-BitLockerKeyProtector -MountPoint $mountPoint -RecoveryPasswordProtector -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
    $newIds = @(Get-RecoveryPasswordIds -MountPoint $mountPoint | Where-Object { $oldIds -notcontains $_ })
    if ($newIds.Count -ne 1) {
        Exit-Remediation 1 "Could not identify the new recovery password protector (found $($newIds.Count)). Old protectors kept."
    }
    $newId = $newIds[0]
    Write-Log "Added new recovery password protector $newId."

    # 2. Back it up
    if (-not (Backup-RecoveryPassword -MountPoint $mountPoint -KeyProtectorId $newId)) {
        Remove-BitLockerKeyProtector -MountPoint $mountPoint -KeyProtectorId $newId -ErrorAction SilentlyContinue | Out-Null
        Exit-Remediation 1 "Rotation skipped: the new recovery password could not be backed up, so it was removed again. Old protectors kept."
    }

    # 3. Remove the old recovery passwords
    $failed = @()
    foreach ($oldId in $oldIds) {
        try {
            Remove-BitLockerKeyProtector -MountPoint $mountPoint -KeyProtectorId $oldId -ErrorAction Stop | Out-Null
            Write-Log "Removed old recovery password protector $oldId."
        }
        catch {
            Write-Log "Failed to remove old recovery password protector $oldId`: $($_.Exception.Message)"
            $failed += $oldId
        }
    }

    New-Item -Path $StateKey -Force -ErrorAction Stop | Out-Null
    Set-ItemProperty -Path $StateKey -Name 'LastRotation' -Value ((Get-Date).ToString('o', [Globalization.CultureInfo]::InvariantCulture)) -ErrorAction Stop

    if ($failed.Count -gt 0) {
        Exit-Remediation 1 "New recovery password $newId backed up, but old protectors could not be removed: $($failed -join ', ')"
    }
    Exit-Remediation 0 "BitLocker recovery password rotated. New protector $newId backed up; $($oldIds.Count) old protector(s) removed."
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
