<#
.SYNOPSIS
    Intune platform script.
    Turns on BitLocker for the Windows (OS) drive and saves the recovery key to
    Microsoft Entra ID and/or Active Directory.

.DESCRIPTION
    Encrypts the OS drive so company data stays protected if the device is lost or stolen,
    and keeps the recovery key in Microsoft Entra ID (Entra joined devices) and/or Active
    Directory (hybrid / domain joined devices), which helps meet compliance requirements.

    Actions, in this order:
      1. Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit (the BitLocker
         cmdlets only exist in 64-bit PowerShell).
      2. Skips the device if its computer name matches $ExcludeList.
      3. Reads the BitLocker state of the OS drive ($env:SystemDrive, normally C:).
         Stops (failure) if the drive is being decrypted or in an unknown state.
      4. Checks the TPM is present and ready. Stops (failure) if not.
      5. Adds a TPM protector if the drive has none (only when BitLocker still has to be turned on).
      6. Adds a recovery password protector if the drive has none.
      7. Backs up every recovery password to Microsoft Entra ID and/or Active Directory.
         If no backup succeeds and $RequireKeyBackup is $true, it stops WITHOUT encrypting.
      8. Turns BitLocker on, depending on the state found in step 3:
           Not encrypted        -> manage-bde -on (used space only, encryption method from
                                   Intune/Group Policy if set, otherwise $DefaultEncryptionMethod)
           Protection suspended -> Resume-BitLocker
           Encryption paused    -> manage-bde -resume
           Already protected    -> nothing to turn on (steps 6 and 7 still make sure the key is saved)
      9. Confirms the drive is protected or encrypting.

    The script is safe to run more than once: each step checks the current state first.
    Encryption continues in the background after the script ends. The device is never restarted.

    Exit codes:
      0 = BitLocker is on (or encryption has started) and the recovery key is saved.
      1 = Failed or stopped (see the log). Intune retries up to 3 times at the next check-ins.

.NOTES
    Intune settings (Devices > Scripts and remediations > Platform scripts):
      Run this script using the logged on credentials : No  (runs as SYSTEM - BitLocker needs admin rights)
      Enforce script signature check                  : No  (unless you sign the script)
      Run script in 64-bit PowerShell host            : Yes
    Log file: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\EnableBitLockerPlatformScript.log
#>

# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------

# Computer names to skip (wildcards allowed), e.g. @('KIOSK-*', 'LAB-PC01')
$ExcludeList = @()

# Only turn BitLocker on after the recovery key is saved to Entra ID or AD (strongly recommended)
$RequireKeyBackup = $true

# Used when no Intune / Group Policy encryption method is set: xts_aes128, xts_aes256, aes128 or aes256
$DefaultEncryptionMethod = 'xts_aes128'

# Maximum time for each manage-bde command (seconds)
$CommandTimeoutSeconds = 300

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\EnableBitLockerPlatformScript.log"

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
# Functions
# ---------------------------------------------------------------------------------------------

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

function Test-Excluded {
    param([string]$Name)
    foreach ($pattern in $ExcludeList) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

# Returns what needs doing for a BitLocker state, or $null when the drive is already protected
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

# True when the drive has any TPM-based protector (TPM, TPM+PIN, TPM+startup key, TPM+PIN+startup key)
function Test-HasTpmProtector {
    param($KeyProtectors)
    return (@($KeyProtectors | Where-Object { [string]$_.KeyProtectorType -like 'Tpm*' }).Count -gt 0)
}

# Reads AzureAdJoined / DomainJoined from dsregcmd /status output
function Get-JoinState {
    param([string[]]$DsregOutput)
    return @{
        EntraJoined  = [bool]($DsregOutput -match '^\s*AzureAdJoined\s*:\s*YES')
        DomainJoined = [bool]($DsregOutput -match '^\s*DomainJoined\s*:\s*YES')
    }
}

# Converts the Intune / Group Policy encryption method value (EncryptionMethodWithXtsOs) to a manage-bde name
function ConvertTo-ManageBdeMethod {
    param($PolicyValue)
    switch ([string]$PolicyValue) {
        '3' { return 'aes128' }
        '4' { return 'aes256' }
        '6' { return 'xts_aes128' }
        '7' { return 'xts_aes256' }
    }
    return $DefaultEncryptionMethod
}

function Get-EncryptionMethod {
    $policy = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE' -Name 'EncryptionMethodWithXtsOs' -ErrorAction SilentlyContinue
    if ($policy) { return (ConvertTo-ManageBdeMethod -PolicyValue $policy.EncryptionMethodWithXtsOs) }
    return $DefaultEncryptionMethod
}

function Get-OSVolume {
    return (Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop)
}

function Get-RecoveryPasswordIds {
    $volume = Get-OSVolume
    return @($volume.KeyProtector |
        Where-Object { [string]$_.KeyProtectorType -eq 'RecoveryPassword' } |
        ForEach-Object { $_.KeyProtectorId })
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

# Backs up every recovery password. Returns $true when at least one backup succeeded.
function Backup-RecoveryPasswords {
    $join = Get-JoinState -DsregOutput @(& "$env:SystemRoot\System32\dsregcmd.exe" /status)
    Write-Log "Join state: EntraJoined=$($join.EntraJoined), DomainJoined=$($join.DomainJoined)"

    $backedUp = $false
    foreach ($id in (Get-RecoveryPasswordIds)) {
        if ($join.EntraJoined) {
            try {
                BackupToAAD-BitLockerKeyProtector -MountPoint $env:SystemDrive -KeyProtectorId $id -ErrorAction Stop | Out-Null
                Write-Log "Recovery password $id saved to Microsoft Entra ID."
                $backedUp = $true
            }
            catch {
                Write-Log "Saving $id to Microsoft Entra ID failed: $($_.Exception.Message)"
            }
        }
        if ($join.DomainJoined) {
            try {
                Backup-BitLockerKeyProtector -MountPoint $env:SystemDrive -KeyProtectorId $id -ErrorAction Stop | Out-Null
                Write-Log "Recovery password $id saved to Active Directory."
                $backedUp = $true
            }
            catch {
                Write-Log "Saving $id to Active Directory failed: $($_.Exception.Message)"
            }
        }
    }
    return $backedUp
}

# Re-reads the drive state for up to 30 seconds while BitLocker starts
function Get-FinalState {
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $volume = Get-OSVolume
        $issue = Get-BitLockerIssue -VolumeStatus ([string]$volume.VolumeStatus) -ProtectionStatus ([string]$volume.ProtectionStatus)
        if (-not $issue) { break }
        Start-Sleep -Seconds 5
    }
    return @{
        Protected = (-not $issue)
        State     = "VolumeStatus=$($volume.VolumeStatus), ProtectionStatus=$($volume.ProtectionStatus), EncryptionPercentage=$($volume.EncryptionPercentage)"
    }
}

function Exit-Script {
    param([int]$Code, [string]$Message)
    Write-Log "$Message (exit code $Code)"
    Write-Output $Message
    exit $Code
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

try {
    $mountPoint = $env:SystemDrive
    Write-Log "===== Enable BitLocker started on $env:COMPUTERNAME for $mountPoint ====="

    # 2. Exclusions
    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Exit-Script 0 "$env:COMPUTERNAME is in the exclude list. Nothing changed."
    }

    # 3. Current state
    $volume = Get-OSVolume
    $issue = Get-BitLockerIssue -VolumeStatus ([string]$volume.VolumeStatus) -ProtectionStatus ([string]$volume.ProtectionStatus)
    Write-Log "Current state: VolumeStatus=$($volume.VolumeStatus), ProtectionStatus=$($volume.ProtectionStatus), action needed: $(if ($issue) { $issue } else { 'none' })"

    if ($issue -eq 'Decrypting') {
        Exit-Script 1 "Stopped: $mountPoint is being decrypted. Check for a policy or admin turning BitLocker off."
    }
    if ($issue -like 'UnknownState:*') {
        Exit-Script 1 "Stopped: $mountPoint is in an unexpected BitLocker state ($($volume.VolumeStatus))."
    }

    if ($issue) {
        # 4. TPM
        $tpm = Get-Tpm -ErrorAction Stop
        if (-not ($tpm.TpmPresent -and $tpm.TpmReady)) {
            Exit-Script 1 "Stopped: TPM not ready (TpmPresent=$($tpm.TpmPresent), TpmReady=$($tpm.TpmReady)). Turn on the TPM in the device firmware."
        }
        Write-Log 'TPM is present and ready.'

        # 5. TPM protector
        if (-not (Test-HasTpmProtector -KeyProtectors $volume.KeyProtector)) {
            Add-BitLockerKeyProtector -MountPoint $mountPoint -TpmProtector -ErrorAction Stop | Out-Null
            Write-Log 'Added a TPM protector.'
        }
    }

    # 6. Recovery password protector
    if ((Get-RecoveryPasswordIds).Count -eq 0) {
        Add-BitLockerKeyProtector -MountPoint $mountPoint -RecoveryPasswordProtector -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
        Write-Log 'Added a recovery password protector.'
    }

    # 7. Save the recovery key
    if (-not (Backup-RecoveryPasswords)) {
        if ($RequireKeyBackup) {
            if ($issue) {
                Exit-Script 1 "Stopped: the recovery key could not be saved to Microsoft Entra ID or Active Directory, so BitLocker was not turned on."
            }
            Exit-Script 1 "BitLocker is on, but the recovery key could not be saved to Microsoft Entra ID or Active Directory."
        }
        Write-Log 'Recovery key could not be saved; continuing because $RequireKeyBackup is $false.'
    }

    # 8. Turn BitLocker on
    switch ($issue) {
        'NotEncrypted' {
            $method = Get-EncryptionMethod
            Write-Log "Starting encryption with $method (used space only)."
            [void](Invoke-ManageBde -Arguments "-on $mountPoint -UsedSpaceOnly -SkipHardwareTest -EncryptionMethod $method")
        }
        'ProtectionSuspended' {
            Resume-BitLocker -MountPoint $mountPoint -ErrorAction Stop | Out-Null
            Write-Log 'Resumed BitLocker protection.'
        }
        'EncryptionPaused' {
            [void](Invoke-ManageBde -Arguments "-resume $mountPoint")
        }
    }

    # 9. Confirm
    $final = Get-FinalState
    Write-Log "Final state: $($final.State)"
    if (-not $final.Protected) {
        Exit-Script 1 "BitLocker is still not protecting $mountPoint ($($final.State))."
    }
    if ($issue) {
        Exit-Script 0 "BitLocker turned on for $mountPoint and the recovery key is saved ($($final.State))."
    }
    Exit-Script 0 "BitLocker was already on for $mountPoint; the recovery key is saved ($($final.State))."
}
catch {
    $message = "Enable BitLocker failed: $($_.Exception.Message)"
    Write-Log $message
    Write-Output $message
    exit 1
}
