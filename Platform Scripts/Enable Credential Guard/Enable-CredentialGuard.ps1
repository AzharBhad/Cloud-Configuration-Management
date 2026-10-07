<#
.SYNOPSIS
    Intune platform script.
    Turns on Windows Defender Credential Guard to protect cached credentials from credential theft
    tools and prevent Pass-the-Hash and Pass-the-Ticket attacks.

.DESCRIPTION
    Credential Guard uses virtualization-based security (VBS) to isolate NTLM password hashes,
    Kerberos ticket-granting tickets and credentials stored by applications as domain credentials,
    so that malware - even running as administrator - can't extract them (Mimikatz-style tools,
    Pass-the-Hash, Pass-the-Ticket).

    Actions, in this order:
      1. Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit (so it writes the
         64-bit registry).
      2. Skips the device if its computer name matches $ExcludeList.
      3. Reads the current state (Win32_DeviceGuard):
           Running         -> nothing to do (for example enabled by default on Windows 11 22H2+).
           Pending restart -> already configured, waiting for a restart; nothing to do.
      4. Checks the requirements and stops (failure) if one is missing:
           - Windows Enterprise or Education edition (not Pro, not Home)
           - Hardware virtualization support for VBS (hypervisor support reported by Windows)
           - UEFI Secure Boot turned on
      5. Stops (failure) if Group Policy or Intune explicitly turns Credential Guard or VBS off -
         a local registry change would be overridden. Fix the policy instead.
      6. Writes only the values that differ:
           HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard
               EnableVirtualizationBasedSecurity = 1
               RequirePlatformSecurityFeatures   = 1 (Secure Boot) or 3 (Secure Boot + DMA protection)
           HKLM\SYSTEM\CurrentControlSet\Control\Lsa
               LsaCfgFlags = 2 (without UEFI lock, default) or 1 (with UEFI lock, $UseUefiLock)
      7. Writes a summary line. Credential Guard starts at the NEXT RESTART; the script never
         restarts the device.

    Exit codes:
      0 = Credential Guard is running, or configured and waiting for a restart.
      1 = Requirements not met, blocked by policy, or the script failed. See the log.

.NOTES
    Intune settings (Devices > Scripts and remediations > Platform scripts):
      Run this script using the logged on credentials : No  (runs as SYSTEM - writes HKLM\SYSTEM and
                                                             reads Device Guard / Secure Boot state)
      Enforce script signature check                  : No  (unless you sign the script)
      Run script in 64-bit PowerShell host            : Yes
    Log file: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\CredentialGuardPlatformScript.log
#>

# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------

# $false = enable WITHOUT UEFI lock (default) - Credential Guard can later be turned off remotely.
# $true  = enable WITH UEFI lock - stronger (malware can't turn it off with a registry change), but
#          turning it off later needs someone at the device to confirm a firmware prompt.
$UseUefiLock = $false

# Platform security level for virtualization-based security:
#   'Auto' = Secure Boot + DMA protection when the device supports DMA protection, otherwise Secure Boot
#   1      = Secure Boot
#   3      = Secure Boot + DMA protection
$PlatformSecurityLevel = 'Auto'

# $true = also try on editions other than Enterprise / Education (Credential Guard isn't supported
#         there, so normally leave this $false)
$AllowUnsupportedEdition = $false

# Computer names to skip (wildcards allowed), e.g. @('LAB-*', 'VM-GEN1-*')
$ExcludeList = @()

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\CredentialGuardPlatformScript.log"

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

$DeviceGuardKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
$LsaKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$PolicyKeys = @{
    'Group Policy' = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
    'Intune (MDM)' = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceGuard'
}

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

# Enterprise and Education editions support Credential Guard; Pro, Pro Education and Home don't
function Test-SupportedEdition {
    param([string]$Caption)
    return ($Caption -match '\b(Enterprise|Education)\b' -and $Caption -notmatch '\bPro\b')
}

# Running / PendingRestart / Off, from Win32_DeviceGuard (1 = Credential Guard)
function Get-CredentialGuardState {
    param([int[]]$Running, [int[]]$Configured)
    if ($Running -contains 1) { return 'Running' }
    if ($Configured -contains 1) { return 'PendingRestart' }
    return 'Off'
}

# Value for RequirePlatformSecurityFeatures. AvailableSecurityProperties 3 = DMA protection.
function Get-PlatformSecurityValue {
    param($Setting, [int[]]$AvailableProperties)
    if ([string]$Setting -eq 'Auto') {
        if ($AvailableProperties -contains 3) { return 3 }
        return 1
    }
    return [int]$Setting
}

# Returns the policy source that turns Credential Guard or VBS off, or $null
function Get-PolicyBlock {
    param([hashtable]$PolicyValues)
    foreach ($source in $PolicyValues.Keys) {
        $values = $PolicyValues[$source]
        if (-not $values) { continue }
        foreach ($name in 'LsaCfgFlags', 'EnableVirtualizationBasedSecurity') {
            if ($null -ne $values[$name] -and [int]$values[$name] -eq 0) { return "$source sets $name = 0" }
        }
    }
    return $null
}

# Returns the registry values that need changing: @{ Path; Name; Value; Current }
function Get-RequiredChanges {
    param([hashtable]$Current, [int]$PlatformValue, [bool]$UefiLock)
    $desired = @(
        @{ Path = $DeviceGuardKey; Name = 'EnableVirtualizationBasedSecurity'; Value = 1 }
        @{ Path = $DeviceGuardKey; Name = 'RequirePlatformSecurityFeatures'; Value = $PlatformValue }
        @{ Path = $LsaKey; Name = 'LsaCfgFlags'; Value = $(if ($UefiLock) { 1 } else { 2 }) }
    )
    foreach ($item in $desired) {
        $now = $Current[$item.Name]
        if ($null -eq $now -or [int]$now -ne $item.Value) {
            [pscustomobject]@{ Path = $item.Path; Name = $item.Name; Value = $item.Value; Current = $now }
        }
    }
}

function Read-RegistryValue {
    param([string]$Path, [string]$Name)
    $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($item) { return $item.$Name }
    return $null
}

function Test-SecureBoot {
    try { return [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { return $false }
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
    Write-Log "===== Enable Credential Guard started on $env:COMPUTERNAME ====="

    # 2. Exclusions
    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Exit-Script 0 "$env:COMPUTERNAME is excluded. Nothing changed."
    }

    # 3. Current state
    $deviceGuard = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
    $state = Get-CredentialGuardState -Running @($deviceGuard.SecurityServicesRunning) -Configured @($deviceGuard.SecurityServicesConfigured)
    $available = @($deviceGuard.AvailableSecurityProperties)
    Write-Log ("Credential Guard state: {0}. VBS status: {1}. Available security properties: {2}." -f $state, $deviceGuard.VirtualizationBasedSecurityStatus, ($available -join ','))

    if ($state -eq 'Running') {
        Exit-Script 0 'Credential Guard is already running. Nothing changed.'
    }
    if ($state -eq 'PendingRestart') {
        Exit-Script 0 'Credential Guard is configured and will start at the next restart. Nothing changed.'
    }

    # 4. Requirements
    $caption = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption
    if (-not (Test-SupportedEdition -Caption $caption) -and -not $AllowUnsupportedEdition) {
        Exit-Script 1 "Not supported: $caption. Credential Guard needs Windows Enterprise or Education."
    }
    # AvailableSecurityProperties 1 = hypervisor support; VirtualizationBasedSecurityStatus 2 = VBS running
    $hypervisorReady = ($available -contains 1) -or ([int]$deviceGuard.VirtualizationBasedSecurityStatus -eq 2)
    if (-not $hypervisorReady) {
        Exit-Script 1 'Not supported: the device does not report hardware virtualization support for VBS. Turn on virtualization (Intel VT-x / AMD-V) in the firmware, or check the device is a Generation 2 VM.'
    }
    if (-not (Test-SecureBoot)) {
        Exit-Script 1 'Not supported: UEFI Secure Boot is off (or the device boots in legacy BIOS mode). Turn on Secure Boot in the firmware.'
    }
    Write-Log "Requirements met: $caption, virtualization support, Secure Boot on."

    # 5. Policy that turns it off
    $policyValues = @{}
    foreach ($source in $PolicyKeys.Keys) {
        $policyValues[$source] = @{
            LsaCfgFlags                       = Read-RegistryValue -Path $PolicyKeys[$source] -Name 'LsaCfgFlags'
            EnableVirtualizationBasedSecurity = Read-RegistryValue -Path $PolicyKeys[$source] -Name 'EnableVirtualizationBasedSecurity'
        }
    }
    $block = Get-PolicyBlock -PolicyValues $policyValues
    if ($block) {
        Exit-Script 1 "Blocked by policy: $block. Change that policy to enable Credential Guard."
    }

    # 6. Registry
    $platformValue = Get-PlatformSecurityValue -Setting $PlatformSecurityLevel -AvailableProperties $available
    $current = @{
        EnableVirtualizationBasedSecurity = Read-RegistryValue -Path $DeviceGuardKey -Name 'EnableVirtualizationBasedSecurity'
        RequirePlatformSecurityFeatures   = Read-RegistryValue -Path $DeviceGuardKey -Name 'RequirePlatformSecurityFeatures'
        LsaCfgFlags                       = Read-RegistryValue -Path $LsaKey -Name 'LsaCfgFlags'
    }
    $changes = @(Get-RequiredChanges -Current $current -PlatformValue $platformValue -UefiLock $UseUefiLock)
    foreach ($change in $changes) {
        if (-not (Test-Path -Path $change.Path)) { New-Item -Path $change.Path -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $change.Path -Name $change.Name -PropertyType DWord -Value $change.Value -Force -ErrorAction Stop | Out-Null
        Write-Log "Set $($change.Path)\$($change.Name) = $($change.Value) (was $(if ($null -eq $change.Current) { 'not set' } else { $change.Current }))."
    }

    # 7. Summary
    $lockText = if ($UseUefiLock) { 'with UEFI lock' } else { 'without UEFI lock' }
    $levelText = if ($platformValue -eq 3) { 'Secure Boot + DMA protection' } else { 'Secure Boot' }
    Exit-Script 0 "Credential Guard enabled ($lockText, $levelText; $($changes.Count) value(s) changed). RESTART REQUIRED - it starts at the next restart."
}
catch {
    $message = "Enable Credential Guard failed: $($_.Exception.Message)"
    Write-Log $message
    Write-Output $message
    exit 1
}
