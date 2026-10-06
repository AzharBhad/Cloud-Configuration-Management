<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Fixes the non-compliant BitLocker encryption settings found by Detect-EncryptionSettings.ps1.

.DESCRIPTION
    Every new recovery password is backed up to Microsoft Entra ID (Entra joined devices) and/or
    Active Directory (domain/hybrid joined devices). A data drive is only encrypted after its
    recovery password is backed up.

    Fixes:
      MissingTpmProtector (OS)      -> Add-BitLockerKeyProtector -TpmProtector
      MissingRecoveryPassword       -> Add-BitLockerKeyProtector -RecoveryPasswordProtector, then back up
      NotEncrypted (data drive)     -> add + back up a recovery password, then
                                       manage-bde -on <drive> -UsedSpaceOnly (encryption method from
                                       Intune/Group Policy if set, otherwise $DefaultEncryptionMethod),
                                       then turn on auto-unlock. Only when the OS drive is protected.
      EncryptionPaused (data drive) -> manage-bde -resume
      AutoUnlockOff (data drive)    -> Enable-BitLockerAutoUnlock (needs the OS drive protected)

    Not fixed (Skipped and logged):
      WeakEncryptionMethod -> changing the method needs a full decrypt and re-encrypt. Do it by hand.
      Decrypting           -> someone or a policy is turning BitLocker off on purpose.
      Locked               -> the drive must be unlocked first.

    Encryption keeps running in the background. The device is never restarted.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = All issues fixed.
      1 = One or more issues were skipped or could not be fixed. See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\EncryptionSettingsRemediation.log
#>

# Drives to skip by mount point (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

# Encryption methods that are compliant - keep in sync with the detection script
$AllowedEncryptionMethods = @('XtsAes128', 'XtsAes256')

# Used for data drives when no Intune / Group Policy method is set: xts_aes128, xts_aes256, aes128 or aes256
$DefaultEncryptionMethod = 'xts_aes128'

# Maximum time for each manage-bde command (seconds)
$CommandTimeoutSeconds = 300

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\EncryptionSettingsRemediation.log"

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

function Test-HasProtector {
    param($Volume, [string]$Type)
    return (@($Volume.KeyProtector | Where-Object { [string]$_.KeyProtectorType -eq $Type }).Count -gt 0)
}

# Same logic as the detection script
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

function Get-JoinState {
    param([string[]]$DsregOutput)
    return @{
        EntraJoined  = [bool]($DsregOutput -match '^\s*AzureAdJoined\s*:\s*YES')
        DomainJoined = [bool]($DsregOutput -match '^\s*DomainJoined\s*:\s*YES')
    }
}

$script:JoinState = $null

# Returns $true when the protector was backed up to at least one directory
function Backup-RecoveryPassword {
    param([string]$MountPoint, [string]$KeyProtectorId)

    if (-not $script:JoinState) {
        $script:JoinState = Get-JoinState -DsregOutput @(& "$env:SystemRoot\System32\dsregcmd.exe" /status)
        Write-Log "Join state: EntraJoined=$($script:JoinState.EntraJoined), DomainJoined=$($script:JoinState.DomainJoined)"
    }

    $backedUp = $false
    if ($script:JoinState.EntraJoined) {
        try {
            BackupToAAD-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $KeyProtectorId -ErrorAction Stop | Out-Null
            Write-Log "$MountPoint recovery password $KeyProtectorId backed up to Microsoft Entra ID."
            $backedUp = $true
        }
        catch { Write-Log "$MountPoint backup to Microsoft Entra ID failed: $($_.Exception.Message)" }
    }
    if ($script:JoinState.DomainJoined) {
        try {
            Backup-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $KeyProtectorId -ErrorAction Stop | Out-Null
            Write-Log "$MountPoint recovery password $KeyProtectorId backed up to Active Directory."
            $backedUp = $true
        }
        catch { Write-Log "$MountPoint backup to Active Directory failed: $($_.Exception.Message)" }
    }
    return $backedUp
}

# Adds a recovery password and backs it up. Removes it again if the backup fails.
function Add-BackedUpRecoveryPassword {
    param([string]$MountPoint)
    $before = @((Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop).KeyProtector |
        Where-Object { [string]$_.KeyProtectorType -eq 'RecoveryPassword' } | ForEach-Object { $_.KeyProtectorId })
    Add-BitLockerKeyProtector -MountPoint $MountPoint -RecoveryPasswordProtector -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
    $newId = @((Get-BitLockerVolume -MountPoint $MountPoint -ErrorAction Stop).KeyProtector |
        Where-Object { [string]$_.KeyProtectorType -eq 'RecoveryPassword' -and $before -notcontains $_.KeyProtectorId } |
        ForEach-Object { $_.KeyProtectorId }) | Select-Object -First 1
    if (-not $newId) { Write-Log "$MountPoint could not find the new recovery password protector."; return $false }
    Write-Log "$MountPoint added recovery password protector $newId."

    if (Backup-RecoveryPassword -MountPoint $MountPoint -KeyProtectorId $newId) { return $true }
    Remove-BitLockerKeyProtector -MountPoint $MountPoint -KeyProtectorId $newId -ErrorAction SilentlyContinue | Out-Null
    Write-Log "$MountPoint removed the new recovery password again because it could not be backed up."
    return $false
}

function Get-DataDriveEncryptionMethod {
    $policy = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE' -Name 'EncryptionMethodWithXtsFdv' -ErrorAction SilentlyContinue
    if ($policy) {
        switch ([int]$policy.EncryptionMethodWithXtsFdv) {
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

function Test-OsDriveProtected {
    $os = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    return ([string]$os.VolumeStatus -eq 'EncryptionInProgress' -or
            ([string]$os.VolumeStatus -eq 'FullyEncrypted' -and [string]$os.ProtectionStatus -eq 'On'))
}

function Enable-AutoUnlock {
    param([string]$MountPoint)
    if (-not (Test-OsDriveProtected)) {
        Write-Log "$MountPoint auto-unlock skipped: the OS drive is not BitLocker protected."
        return $false
    }
    try {
        Enable-BitLockerAutoUnlock -MountPoint $MountPoint -ErrorAction Stop | Out-Null
        Write-Log "$MountPoint auto-unlock turned on."
        return $true
    }
    catch {
        Write-Log "$MountPoint auto-unlock failed: $($_.Exception.Message)"
        return $false
    }
}

# Fixes one issue. Returns $true when fixed.
function Repair-Issue {
    param($Item)
    $mp = $Item.MountPoint
    switch -Wildcard ($Item.Issue) {
        'MissingTpmProtector' {
            Add-BitLockerKeyProtector -MountPoint $mp -TpmProtector -ErrorAction Stop | Out-Null
            Write-Log "$mp added TPM protector."
            return $true
        }
        'MissingRecoveryPassword' {
            return (Add-BackedUpRecoveryPassword -MountPoint $mp)
        }
        'NotEncrypted' {
            if (-not (Test-OsDriveProtected)) {
                Write-Log "$mp skipped: encrypt the OS drive first (data drives need it for auto-unlock)."
                return $false
            }
            if (-not (Add-BackedUpRecoveryPassword -MountPoint $mp)) {
                Write-Log "$mp skipped: not encrypting without a backed-up recovery password."
                return $false
            }
            $method = Get-DataDriveEncryptionMethod
            if (-not (Invoke-ManageBde -Arguments "-on $mp -UsedSpaceOnly -EncryptionMethod $method")) { return $false }
            return (Enable-AutoUnlock -MountPoint $mp)
        }
        'EncryptionPaused' {
            return (Invoke-ManageBde -Arguments "-resume $mp")
        }
        'AutoUnlockOff' {
            return (Enable-AutoUnlock -MountPoint $mp)
        }
        'WeakEncryptionMethod:*' {
            Write-Log "$mp skipped $($Item.Issue): changing the encryption method needs a full decrypt and re-encrypt. Do it by hand."
            return $false
        }
        'Decrypting' {
            Write-Log "$mp skipped: the drive is being decrypted. Check for a policy or admin turning BitLocker off."
            return $false
        }
        'Locked' {
            Write-Log "$mp skipped: the drive is locked. Unlock it first."
            return $false
        }
        default {
            Write-Log "$mp skipped unknown issue $($Item.Issue)."
            return $false
        }
    }
}

try {
    Write-Log 'Starting encryption settings remediation.'
    $notFixed = @()

    # OS drive first, so data drives can use auto-unlock
    $items = @(Get-EncryptionIssues | Sort-Object -Property @{ Expression = { -not $_.IsOs } })
    foreach ($item in $items) {
        try {
            if (-not (Repair-Issue -Item $item)) { $notFixed += "$($item.MountPoint) $($item.Issue)" }
        }
        catch {
            Write-Log "$($item.MountPoint) $($item.Issue) failed: $($_.Exception.Message)"
            $notFixed += "$($item.MountPoint) $($item.Issue)"
        }
    }

    if ($notFixed.Count -gt 0) {
        $message = "Fixed $($items.Count - $notFixed.Count) of $($items.Count) encryption issue(s). Not fixed: $($notFixed -join '; ')"
        Write-Log $message
        Write-Output $message
        exit 1
    }

    Write-Log "Fixed $($items.Count) encryption issue(s)."
    Write-Output "Fixed $($items.Count) encryption issue(s)."
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
