<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Turns BitLocker on for the Windows (OS) drive when Detect-BitLocker.ps1 finds it off,
    suspended or paused.

.DESCRIPTION
    Steps, in this order:
      1. Checks the TPM is present and ready. Without a TPM the drive can't be protected silently,
         so the device is skipped.
      2. Makes sure the drive has a TPM protector and a recovery password protector
         (adds them if missing).
      3. Backs up the recovery password(s) to Microsoft Entra ID (Entra joined devices) and/or
         Active Directory (domain/hybrid joined devices).
         If $RequireKeyBackup is $true and no backup succeeds, it STOPS here without encrypting,
         so a drive is never encrypted with a recovery key nobody has.
      4. Fixes the drive:
           Not encrypted       -> manage-bde -on (used space only, encryption method from
                                  Intune/Group Policy if set, otherwise $DefaultEncryptionMethod)
           Protection suspended -> Resume-BitLocker
           Encryption paused   -> manage-bde -resume
           Being decrypted     -> Skipped and logged (someone or a policy is turning BitLocker off)

    Encryption continues in the background after the script ends; the user can keep working.
    The device is never restarted.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = BitLocker is on (or encryption has started) and the recovery key is backed up.
      1 = BitLocker could not be turned on, or was skipped. See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerRemediation.log
#>

# Computer names to skip (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

# Only encrypt after the recovery key is saved to Entra ID or AD (strongly recommended)
$RequireKeyBackup = $true

# Used when no Intune / Group Policy encryption method is set: xts_aes128, xts_aes256, aes128 or aes256
$DefaultEncryptionMethod = 'xts_aes128'

# Maximum time for each manage-bde command (seconds)
$CommandTimeoutSeconds = 300

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\BitLockerRemediation.log"

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

# Same logic as the detection script
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

# Reads AzureAdJoined / DomainJoined from dsregcmd /status output
function Get-JoinState {
    param([string[]]$DsregOutput)
    return @{
        EntraJoined  = [bool]($DsregOutput -match '^\s*AzureAdJoined\s*:\s*YES')
        DomainJoined = [bool]($DsregOutput -match '^\s*DomainJoined\s*:\s*YES')
    }
}

# Encryption method set by Intune / Group Policy for OS drives, converted to a manage-bde name
function Get-EncryptionMethod {
    $policy = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE' -Name 'EncryptionMethodWithXtsOs' -ErrorAction SilentlyContinue
    if ($policy) {
        switch ([int]$policy.EncryptionMethodWithXtsOs) {
            3 { return 'aes128' }
            4 { return 'aes256' }
            6 { return 'xts_aes128' }
            7 { return 'xts_aes256' }
        }
    }
    return $DefaultEncryptionMethod
}

function Invoke-ManageBde {
    param([string]$Arguments)
    $outFile = Join-Path $env:TEMP ("manage-bde-{0}.txt" -f [guid]::NewGuid())
    try {
        $process = Start-Process -FilePath "$env:SystemRoot\System32\manage-bde.exe" -ArgumentList $Arguments `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile
        if (-not $process.WaitForExit($CommandTimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            Write-Log "manage-bde $Arguments timed out after $CommandTimeoutSeconds seconds."
            return $false
        }
        $output = (Get-Content -Path $outFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() }) -join ' | '
        Write-Log "manage-bde $Arguments -> exit code $($process.ExitCode): $output"
        return ($process.ExitCode -eq 0)
    }
    finally {
        Remove-Item -Path $outFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-ProtectorsOfType {
    param([string]$MountPoint, [string]$Type)
    $volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
    return @($volume.KeyProtector | Where-Object { [string]$_.KeyProtectorType -eq $Type })
}

# Returns $true when at least one recovery password was backed up
function Backup-RecoveryPasswords {
    param([string]$MountPoint)

    $join = Get-JoinState -DsregOutput @(& "$env:SystemRoot\System32\dsregcmd.exe" /status)
    Write-Log "Join state: EntraJoined=$($join.EntraJoined), DomainJoined=$($join.DomainJoined)"

    $backedUp = $false
    foreach ($protector in (Get-ProtectorsOfType -MountPoint $MountPoint -Type 'RecoveryPassword')) {
        $id = $protector.KeyProtectorId
        if ($join.EntraJoined) {
            try {
                BackupToAAD-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $id -ErrorAction Stop | Out-Null
                Write-Log "Recovery password $id backed up to Microsoft Entra ID."
                $backedUp = $true
            }
            catch {
                Write-Log "Backup of $id to Microsoft Entra ID failed: $($_.Exception.Message)"
            }
        }
        if ($join.DomainJoined) {
            try {
                Backup-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $id -ErrorAction Stop | Out-Null
                Write-Log "Recovery password $id backed up to Active Directory."
                $backedUp = $true
            }
            catch {
                Write-Log "Backup of $id to Active Directory failed: $($_.Exception.Message)"
            }
        }
    }
    return $backedUp
}

# Checks the drive state, retrying for up to 30 seconds while BitLocker starts
function Test-BitLockerProtected {
    param([string]$MountPoint)
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $volume = Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop
        $state = "VolumeStatus=$($volume.VolumeStatus), ProtectionStatus=$($volume.ProtectionStatus), EncryptionPercentage=$($volume.EncryptionPercentage)"
        $issue = Get-BitLockerIssue -VolumeStatus ([string]$volume.VolumeStatus) -ProtectionStatus ([string]$volume.ProtectionStatus)
        if (-not $issue) { break }
        Start-Sleep -Seconds 5
    }
    Write-Log "$MountPoint now: $state"
    return @{ Protected = (-not $issue); State = $state }
}

function Exit-Remediation {
    param([int]$Code, [string]$Message)
    Write-Log $Message
    Write-Output $Message
    exit $Code
}

try {
    $mountPoint = $env:SystemDrive
    Write-Log "Starting BitLocker remediation for $mountPoint."

    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Exit-Remediation 0 "$env:COMPUTERNAME is excluded from the BitLocker check."
    }

    $volume = Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop
    $issue = Get-BitLockerIssue -VolumeStatus ([string]$volume.VolumeStatus) -ProtectionStatus ([string]$volume.ProtectionStatus)

    if (-not $issue) {
        Exit-Remediation 0 "BitLocker is already protecting $mountPoint."
    }
    if ($issue -eq 'Decrypting') {
        Exit-Remediation 1 "Skipped: $mountPoint is being decrypted ($($volume.VolumeStatus)). Check for a policy or admin turning BitLocker off."
    }
    if ($issue -like 'UnknownState:*') {
        Exit-Remediation 1 "Skipped: $mountPoint is in an unexpected BitLocker state ($($volume.VolumeStatus))."
    }

    # 1. TPM
    $tpm = Get-Tpm -ErrorAction Stop
    if (-not ($tpm.TpmPresent -and $tpm.TpmReady)) {
        Exit-Remediation 1 "Skipped: TPM not ready (TpmPresent=$($tpm.TpmPresent), TpmReady=$($tpm.TpmReady)). Turn on / clear the TPM in the device firmware."
    }

    # 2. Key protectors
    if ((Get-ProtectorsOfType -MountPoint $mountPoint -Type 'Tpm').Count -eq 0) {
        Add-BitLockerKeyProtector -MountPoint $mountPoint -TpmProtector -ErrorAction Stop | Out-Null
        Write-Log "Added TPM protector to $mountPoint."
    }
    if ((Get-ProtectorsOfType -MountPoint $mountPoint -Type 'RecoveryPassword').Count -eq 0) {
        Add-BitLockerKeyProtector -MountPoint $mountPoint -RecoveryPasswordProtector -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
        Write-Log "Added recovery password protector to $mountPoint."
    }

    # 3. Recovery key backup
    $backedUp = Backup-RecoveryPasswords -MountPoint $mountPoint
    if (-not $backedUp) {
        if ($RequireKeyBackup) {
            Exit-Remediation 1 "Skipped: the recovery key could not be backed up to Microsoft Entra ID or Active Directory, so BitLocker was not turned on. See the log."
        }
        Write-Log 'Recovery key backup failed, continuing because $RequireKeyBackup is $false.'
    }

    # 4. Turn BitLocker on
    switch ($issue) {
        'NotEncrypted' {
            $method = Get-EncryptionMethod
            Write-Log "Starting encryption of $mountPoint with $method (used space only)."
            [void](Invoke-ManageBde -Arguments "-on $mountPoint -UsedSpaceOnly -SkipHardwareTest -EncryptionMethod $method")
        }
        'ProtectionSuspended' {
            Resume-BitLocker -MountPoint $mountPoint -ErrorAction Stop | Out-Null
            Write-Log "Resumed BitLocker protection on $mountPoint."
        }
        'EncryptionPaused' {
            [void](Invoke-ManageBde -Arguments "-resume $mountPoint")
        }
    }

    $result = Test-BitLockerProtected -MountPoint $mountPoint
    if ($result.Protected) {
        Exit-Remediation 0 "BitLocker turned on for $mountPoint ($($result.State))."
    }
    Exit-Remediation 1 "BitLocker is still not protecting $mountPoint ($($result.State)). See the log."
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
