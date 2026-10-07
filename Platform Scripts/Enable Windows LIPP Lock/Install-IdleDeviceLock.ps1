<#
.SYNOPSIS
    Intune platform script - Windows LIPP Lock.
    Installs a daily check that logs off all users when the device has been idle for 14 consecutive
    days, and flags the device so an Intune custom compliance policy marks it non-compliant.

.DESCRIPTION
    A platform script runs only once, so it can't watch for 14 idle days by itself. Instead it
    installs a small checker script and a scheduled task that runs it as SYSTEM every day and at
    every startup. The checker does the work:

      Checker (runs daily and at startup):
        1. Reads the user sessions on the device (quser) and how long each has been idle, and when
           each user profile was last used (Win32_UserProfile.LastUseTime).
        2. Works out the device's last activity: the most recent of - any session's last input,
           any profile's last use, and the time the lock was installed (so a device is never
           locked within $IdleDaysThreshold days of installing it).
        3. If the device has been idle for $IdleDaysThreshold days or more:
             - logs off every user session (logoff.exe) if $LogOffUsers is $true,
             - sets the lock flag Locked = 1 in HKLM\SOFTWARE\IntuneIdleDeviceLock,
             - writes event 2001 (Warning) to the Application event log.
        4. If the device is in use again and $KeepLockUntilCleared is $false, clears the lock flag
           (event 2002). With $KeepLockUntilCleared = $true (default) the device stays locked until
           IT clears it.
        5. Records LastActivity, IdleDays and LastCheck in the same registry key.

      An Intune custom compliance policy (discovery script + JSON rules in README.md) reads the lock
      flag and marks the device NON-COMPLIANT while Locked = 1. Conditional Access can then block
      access to company resources until IT reviews the device.

    This platform script, in order:
      1. Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit.
      2. If the computer name matches $ExcludeList: removes the task and checker if present, and stops.
      3. Creates C:\ProgramData\IntuneIdleDeviceLock, readable and writable only by SYSTEM and
         Administrators (the checker runs as SYSTEM, so users must not be able to change it).
      4. Writes the checker script there (only if it changed).
      5. Registers the scheduled task "Intune Idle Device Lock" (daily at $CheckTime, at startup,
         runs as SYSTEM, catches up if a run was missed).
      6. Records the install time (first install only - the idle grace period starts here).
      7. Runs the checker once now so the compliance flag exists straight away.
      8. Writes a summary line.

    Safe to run more than once. The device is never restarted.

    Exit codes:
      0 = Lock installed (or removed for an excluded device).
      1 = Install failed. See the log.

.NOTES
    Intune settings (Devices > Scripts and remediations > Platform scripts):
      Run this script using the logged on credentials : No  (runs as SYSTEM - installs a SYSTEM
                                                             scheduled task and writes HKLM)
      Enforce script signature check                  : No  (unless you sign the script)
      Run script in 64-bit PowerShell host            : Yes
    Logs: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IdleDeviceLockPlatformScript.log (install)
          C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IdleDeviceLock.log                 (daily checks)
#>

# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------

# Lock the device after this many consecutive idle days
$IdleDaysThreshold = 14

# Log off all user sessions when the device is locked
$LogOffUsers = $true

# $true  = once locked, the device stays locked (non-compliant) until IT clears it
# $false = the lock clears by itself at the next check after someone uses the device again
$KeepLockUntilCleared = $true

# Time of day for the daily check (24-hour, device local time)
$CheckTime = '09:00'

# Computer names to skip (wildcards allowed), e.g. @('KIOSK-*', 'LAB-*'). The lock is removed from these.
$ExcludeList = @()

$InstallFolder = "$env:ProgramData\IntuneIdleDeviceLock"
$CheckerPath = Join-Path $InstallFolder 'Invoke-IdleDeviceCheck.ps1'
$StateKey = 'HKLM:\SOFTWARE\IntuneIdleDeviceLock'
$TaskName = 'Intune Idle Device Lock'
$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IdleDeviceLockPlatformScript.log"

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
# The checker script installed on the device (runs daily as SYSTEM)
# ---------------------------------------------------------------------------------------------

$CheckerScript = @'
<#
    Intune Idle Device Lock - daily checker. Installed by the "Enable Windows LIPP Lock" Intune
    platform script. Runs as SYSTEM from the scheduled task "Intune Idle Device Lock".
    Do not edit here - change the platform script in Intune instead.
#>
param(
    [int]$IdleDaysThreshold = 14,
    [int]$LogOffUsers = 1,
    [int]$KeepLockUntilCleared = 1
)

$StateKey = 'HKLM:\SOFTWARE\IntuneIdleDeviceLock'
$EventSource = 'IntuneIdleDeviceLock'
$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\IdleDeviceLock.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

# Converts a quser IDLE TIME value to a TimeSpan: "." / "none" = 0, "5" = minutes,
# "1:05" = hours:minutes, "2+03:04" = days+hours:minutes
function ConvertFrom-QuserIdle {
    param([string]$Text)
    $Text = ([string]$Text).Trim()
    if ($Text -match '^(\d+)\+(\d+):(\d+)$') { return New-TimeSpan -Days $Matches[1] -Hours $Matches[2] -Minutes $Matches[3] }
    if ($Text -match '^(\d+):(\d+)$') { return New-TimeSpan -Hours $Matches[1] -Minutes $Matches[2] }
    if ($Text -match '^\d+$') { return New-TimeSpan -Minutes ([int]$Text) }
    return New-TimeSpan
}

# Parses quser output into sessions. The SESSIONNAME column is empty for disconnected sessions.
function ConvertFrom-QuserOutput {
    param([string[]]$Lines)
    foreach ($line in $Lines) {
        if ($line -match '^\s*>?(?<user>\S+)\s+(?:(?<session>\S+)\s+)?(?<id>\d+)\s+(?<state>Active|Disc\S*|\S+)\s+(?<idle>\S+)\s+(?<logon>\S.*)$' -and $Matches.user -ne 'USERNAME') {
            [pscustomobject]@{
                User  = $Matches.user
                Id    = [int]$Matches.id
                State = $Matches.state
                Idle  = ConvertFrom-QuserIdle -Text $Matches.idle
            }
        }
    }
}

# The most recent sign of use: session input, profile use, or the install time
function Get-LastActivity {
    param($Sessions, [datetime[]]$ProfileLastUse, $InstalledOn, [datetime]$Now)
    $candidates = @()
    foreach ($session in $Sessions) { $candidates += $Now - $session.Idle }
    foreach ($time in $ProfileLastUse) { if ($time) { $candidates += $time } }
    if ($InstalledOn) { $candidates += [datetime]$InstalledOn }
    if ($candidates.Count -eq 0) { return $Now }
    return ($candidates | Sort-Object -Descending | Select-Object -First 1)
}

function Get-QuserLines {
    $output = & "$env:ComSpec" /c "quser.exe 2>nul"
    return @($output | Where-Object { $_ })
}

function Get-ProfileLastUse {
    @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { -not $_.Special -and -not $_.Loaded -and $_.LastUseTime } |
        ForEach-Object { [datetime]$_.LastUseTime })
}

function Read-State {
    $values = Get-ItemProperty -Path $StateKey -ErrorAction SilentlyContinue
    $installedOn = $null
    if ($values -and $values.InstalledOn) {
        try { $installedOn = [datetime]::Parse($values.InstalledOn, [Globalization.CultureInfo]::InvariantCulture) } catch { }
    }
    return @{ InstalledOn = $installedOn; Locked = [bool]($values -and $values.Locked -eq 1) }
}

function Write-AuditEvent {
    param([int]$EventId, [string]$EntryType, [string]$Message)
    try {
        if (-not [Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName Application -Source $EventSource -ErrorAction Stop
        }
        Write-EventLog -LogName Application -Source $EventSource -EventId $EventId -EntryType $EntryType -Message $Message -ErrorAction Stop
    }
    catch { Write-Log "Could not write to the event log: $($_.Exception.Message)" }
}

function Invoke-IdleCheck {
    $now = Get-Date
    $state = Read-State
    $sessions = @(ConvertFrom-QuserOutput -Lines (Get-QuserLines))
    $lastActivity = Get-LastActivity -Sessions $sessions -ProfileLastUse (Get-ProfileLastUse) -InstalledOn $state.InstalledOn -Now $now
    $idleDays = [math]::Floor(($now - $lastActivity).TotalDays)
    $isIdle = $idleDays -ge $IdleDaysThreshold
    Write-Log ("Sessions: {0}. Last activity: {1:s}. Idle days: {2} (threshold {3}). Locked: {4}." -f $sessions.Count, $lastActivity, $idleDays, $IdleDaysThreshold, $state.Locked)

    $locked = $state.Locked
    $loggedOff = @()
    if ($isIdle) {
        if ($LogOffUsers -eq 1) {
            foreach ($session in $sessions) {
                & "$env:ComSpec" /c "logoff.exe $($session.Id) 2>nul"
                Write-Log "Logged off $($session.User) (session $($session.Id), $($session.State))."
                $loggedOff += $session.User
            }
        }
        if (-not $locked) {
            $locked = $true
            Set-ItemProperty -Path $StateKey -Name 'LockedOn' -Value ($now.ToString('s')) -ErrorAction Stop
            Write-AuditEvent -EventId 2001 -EntryType Warning -Message ("Device idle for {0} days (threshold {1}). Device locked (non-compliant). Users logged off: {2}." -f $idleDays, $IdleDaysThreshold, $(if ($loggedOff) { $loggedOff -join ', ' } else { 'none' }))
            Write-Log 'Device LOCKED.'
        }
    }
    elseif ($locked -and $KeepLockUntilCleared -ne 1) {
        $locked = $false
        Write-AuditEvent -EventId 2002 -EntryType Information -Message "Device in use again (idle $idleDays days). Lock cleared."
        Write-Log 'Device in use again. Lock cleared.'
    }

    Set-ItemProperty -Path $StateKey -Name 'Locked' -Value ([int]$locked) -Type DWord -ErrorAction Stop
    Set-ItemProperty -Path $StateKey -Name 'IdleDays' -Value ([int]$idleDays) -Type DWord -ErrorAction Stop
    Set-ItemProperty -Path $StateKey -Name 'LastActivity' -Value ($lastActivity.ToString('s')) -ErrorAction Stop
    Set-ItemProperty -Path $StateKey -Name 'LastCheck' -Value ($now.ToString('s')) -ErrorAction Stop
    return ("Idle days: {0} (threshold {1}). Locked: {2}. Logged off: {3}." -f $idleDays, $IdleDaysThreshold, $locked, $loggedOff.Count)
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not (Test-Path -Path $StateKey)) { New-Item -Path $StateKey -Force -ErrorAction Stop | Out-Null }
        $result = Invoke-IdleCheck
        Write-Log $result
        Write-Output $result
        exit 0
    }
    catch {
        Write-Log "Idle check failed: $($_.Exception.Message)"
        Write-Output "Idle check failed: $($_.Exception.Message)"
        exit 1
    }
}
'@

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

# Arguments the scheduled task passes to the checker
function Get-CheckerArguments {
    return ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -IdleDaysThreshold {1} -LogOffUsers {2} -KeepLockUntilCleared {3}' -f
        $CheckerPath, [int]$IdleDaysThreshold, [int][bool]$LogOffUsers, [int][bool]$KeepLockUntilCleared)
}

# Locks the folder down to SYSTEM and Administrators
function Protect-InstallFolder {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {
        $identity = New-Object Security.Principal.SecurityIdentifier $sid
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $InstallFolder -AclObject $acl -ErrorAction Stop
}

# Writes the checker only when its content changed. Returns 'Written' or 'Unchanged'.
function Install-CheckerScript {
    if ((Test-Path -LiteralPath $CheckerPath) -and ((Get-Content -LiteralPath $CheckerPath -Raw -ErrorAction SilentlyContinue) -eq $CheckerScript)) {
        return 'Unchanged'
    }
    [IO.File]::WriteAllText($CheckerPath, $CheckerScript, [Text.Encoding]::ASCII)
    return 'Written'
}

function Register-IdleTask {
    $powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $action = New-ScheduledTaskAction -Execute $powershell -Argument (Get-CheckerArguments)
    $triggers = @(
        New-ScheduledTaskTrigger -Daily -At $CheckTime
        New-ScheduledTaskTrigger -AtStartup
    )
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal `
        -Description 'Windows LIPP Lock: logs off users and flags the device non-compliant after a long idle period. Installed by Intune.' `
        -Force -ErrorAction Stop | Out-Null
}

function Remove-IdleLock {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Log "Removed scheduled task '$TaskName'."
    }
    if (Test-Path -LiteralPath $InstallFolder) {
        Remove-Item -LiteralPath $InstallFolder -Recurse -Force -ErrorAction Stop
        Write-Log "Removed $InstallFolder."
    }
    if (Test-Path -Path $StateKey) {
        Remove-Item -Path $StateKey -Recurse -Force -ErrorAction Stop
        Write-Log "Removed $StateKey."
    }
}

# Runs the checker once now (time-limited) and returns its summary line
function Invoke-CheckerNow {
    $outFile = Join-Path $env:TEMP ("idlecheck-{0}.txt" -f [guid]::NewGuid())
    try {
        $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList (Get-CheckerArguments) -PassThru -WindowStyle Hidden -RedirectStandardOutput $outFile
        if (-not $process.WaitForExit(300000)) {
            try { $process.Kill() } catch { }
            return 'First check timed out (the scheduled task will run it).'
        }
        return ((Get-Content -LiteralPath $outFile -ErrorAction SilentlyContinue) -join ' ')
    }
    finally {
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

try {
    Write-Log "===== Windows LIPP Lock install started on $env:COMPUTERNAME (threshold $IdleDaysThreshold days) ====="

    # 2. Excluded devices
    if (Test-Excluded -Name $env:COMPUTERNAME) {
        Remove-IdleLock
        $message = "$env:COMPUTERNAME is excluded. Idle device lock not installed (removed if present)."
        Write-Log $message
        Write-Output $message
        exit 0
    }

    # 3-4. Folder and checker
    if (-not (Test-Path -LiteralPath $InstallFolder)) {
        New-Item -Path $InstallFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    Protect-InstallFolder
    Write-Log "Checker script: $(Install-CheckerScript) ($CheckerPath)."

    # 5. Scheduled task
    Register-IdleTask
    Write-Log "Scheduled task '$TaskName' registered (daily at $CheckTime and at startup, as SYSTEM)."

    # 6. State key and install time (kept from the first install - the grace period starts here)
    if (-not (Test-Path -Path $StateKey)) { New-Item -Path $StateKey -Force -ErrorAction Stop | Out-Null }
    if (-not (Get-ItemProperty -Path $StateKey -Name 'InstalledOn' -ErrorAction SilentlyContinue)) {
        Set-ItemProperty -Path $StateKey -Name 'InstalledOn' -Value ((Get-Date).ToString('s')) -ErrorAction Stop
        Write-Log 'Recorded install time.'
    }
    Set-ItemProperty -Path $StateKey -Name 'IdleDaysThreshold' -Value ([int]$IdleDaysThreshold) -Type DWord -ErrorAction Stop

    # 7. First check
    $firstCheck = Invoke-CheckerNow
    Write-Log "First check: $firstCheck"

    # 8. Summary
    $message = "Windows LIPP Lock installed: checks daily at $CheckTime and at startup; locks after $IdleDaysThreshold idle days. $firstCheck"
    Write-Log $message
    Write-Output $message
    exit 0
}
catch {
    $message = "Windows LIPP Lock install failed: $($_.Exception.Message)"
    Write-Log $message
    Write-Output $message
    exit 1
}
