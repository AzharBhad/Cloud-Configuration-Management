<#
.SYNOPSIS
    Intune platform script.
    Audits the local Administrators group: finds devices with multiple local admin accounts,
    detects policy violations and privileged access risks, and writes reports for remediation teams.

.DESCRIPTION
    Read-only audit. The script never adds, removes or changes accounts or group membership.

    Actions, in this order:
      1. Relaunches itself in 64-bit PowerShell if Intune started it in 32-bit.
      2. Lists every member of the local Administrators group (found by its well-known SID
         S-1-5-32-544, so it works on every Windows language). Uses ADSI so orphaned SIDs of
         deleted accounts are included.
      3. For each member, records its name, SID, type (user or group), source (Local, Domain,
         EntraID, BuiltIn), and - for local accounts - enabled state and password settings.
      4. Checks each member and the device for findings:
           UnapprovedMember          (High)   member not in $ApprovedMembers
           MultipleAdminAccounts     (High)   more than $MaxAdminAccounts enabled admin user accounts
           LocalAccountNoPassword    (High)   local admin account that doesn't require a password
           OrphanedSid               (Medium) SID of a deleted account (can't be resolved)
           LocalAdminAccount         (Medium) local (non built-in) user account with admin rights
           PasswordNeverExpires      (Medium) local admin account whose password never expires
           StalePassword             (Medium) local admin password older than $MaxPasswordAgeDays days
           DirectDomainUser          (Low)    domain user added directly instead of through a group
           BuiltInAdminEnabled       (Low)    built-in Administrator enabled ($FlagBuiltInAdminEnabled)
      5. Writes the reports to $ReportFolder (readable only by SYSTEM and Administrators):
           LocalAdminAudit-<computer>-<time>.csv   one row per member, with its findings
           LocalAdminAudit-<computer>-<time>.json  device details, counts, findings, risk level
           LocalAdminAudit-Latest.csv / .json       copies of the newest report
         Keeps the newest $KeepReports reports and deletes older ones.
      6. Copies the reports to $ReportShare (optional, off by default), with a time limit.
      7. Writes a summary to the Application event log (source $EventSource):
           event 1000 (Information) = no findings, event 1001 (Warning) = findings.
      8. Writes one summary line (Intune keeps it as the script's result message).

    Exit codes:
      0 = Audit completed, no findings (or $ReportFindingsAsFailure is $false).
      1 = Audit completed WITH findings and $ReportFindingsAsFailure is $true - the device shows as
          "Failed" in Intune so it is easy to find - or the audit itself failed. See the log.

.NOTES
    Intune settings (Devices > Scripts and remediations > Platform scripts):
      Run this script using the logged on credentials : No  (runs as SYSTEM - reading account details,
                                                             writing the protected report folder and
                                                             the event log need admin rights)
      Enforce script signature check                  : No  (unless you sign the script)
      Run script in 64-bit PowerShell host            : Yes
    Log file: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\LocalAdminAuditPlatformScript.log
#>

# ---------------------------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------------------------

# Members of the Administrators group that are approved. Matched against SID and DOMAIN\Name,
# wildcards allowed. Add your Microsoft Entra role SIDs (see README.md).
$ApprovedMembers = @(
    'S-1-5-21-*-500'    # Built-in local Administrator account (managed by Windows LAPS)
    'S-1-5-21-*-512'    # Domain Admins (hybrid joined devices)
    # 'S-1-12-1-1111111111-2222222222-3333333333-4444444444'   # Global Administrator role
    # 'S-1-12-1-5555555555-6666666666-7777777777-8888888888'   # Entra Joined Device Local Administrator role
)

# Flag the device when it has more than this many ENABLED admin user accounts (groups not counted)
$MaxAdminAccounts = 1

# Flag local admin accounts whose password is older than this many days
$MaxPasswordAgeDays = 90

# Flag the built-in Administrator account when it is enabled. Set to $false if Windows LAPS manages it.
$FlagBuiltInAdminEnabled = $true

# Finding codes to ignore (wildcards allowed), e.g. @('DirectDomainUser', 'BuiltInAdminEnabled')
$ExcludeList = @()

# Where reports are written on the device, and how many to keep
$ReportFolder = "$env:ProgramData\IntuneAudit\LocalAdmins"
$KeepReports = 10

# Optional: also copy the reports to a file share, e.g. '\\fileserver\LocalAdminAudit$'
# The share must allow the computer account (Domain Computers) to write. Leave empty to skip.
$ReportShare = ''
$ShareCopyTimeoutSeconds = 120

# Application event log source used for the summary event
$EventSource = 'IntuneLocalAdminAudit'

# Report the device as "Failed" in Intune when findings are found (makes them easy to spot)
$ReportFindingsAsFailure = $true

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\LocalAdminAuditPlatformScript.log"

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

$AdministratorsSid = 'S-1-5-32-544'

$Severity = @{
    UnapprovedMember       = 'High'
    MultipleAdminAccounts  = 'High'
    LocalAccountNoPassword = 'High'
    OrphanedSid            = 'Medium'
    LocalAdminAccount      = 'Medium'
    PasswordNeverExpires   = 'Medium'
    StalePassword          = 'Medium'
    DirectDomainUser       = 'Low'
    BuiltInAdminEnabled    = 'Low'
}

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

# Local, Domain, EntraID, BuiltIn or Unknown, from the member's SID
function Get-MemberSource {
    param([string]$Sid, [string]$LocalDomainSid)
    if ($Sid -like 'S-1-12-1-*') { return 'EntraID' }
    if ($Sid -like 'S-1-5-32-*') { return 'BuiltIn' }
    if ($LocalDomainSid -and $Sid -like "$LocalDomainSid-*") { return 'Local' }
    if ($Sid -like 'S-1-5-21-*') { return 'Domain' }
    return 'Unknown'
}

# Returns the finding codes for one member (device-level findings are added separately)
function Get-MemberFindings {
    param($Member, [datetime]$Now)
    $findings = @()
    if (-not $Member.Approved) { $findings += 'UnapprovedMember' }
    if (-not $Member.Resolved) { $findings += 'OrphanedSid' }
    if ($Member.Source -eq 'Domain' -and $Member.Class -eq 'User') { $findings += 'DirectDomainUser' }

    if ($Member.Source -eq 'Local' -and $Member.Class -eq 'User') {
        $isBuiltInAdmin = $Member.Sid -like 'S-1-5-21-*-500'
        if ($isBuiltInAdmin) {
            if ($Member.Enabled -and $FlagBuiltInAdminEnabled) { $findings += 'BuiltInAdminEnabled' }
        }
        else {
            $findings += 'LocalAdminAccount'
        }
        if ($Member.Enabled) {
            if ($Member.PasswordRequired -eq $false) { $findings += 'LocalAccountNoPassword' }
            if ($Member.PasswordNeverExpires -eq $true) { $findings += 'PasswordNeverExpires' }
            if ($Member.PasswordLastSet -and ($Now - [datetime]$Member.PasswordLastSet).TotalDays -gt $MaxPasswordAgeDays) {
                $findings += 'StalePassword'
            }
        }
    }
    return @($findings | Where-Object { -not (Test-MatchesAny -Values @($_) -Patterns $ExcludeList) })
}

# Enabled individual admin accounts: local users that are enabled, plus domain and Entra user accounts
function Get-AdminAccountCount {
    param($Members)
    return @($Members | Where-Object {
            $_.Class -eq 'User' -and ($_.Source -ne 'Local' -or $_.Enabled)
        }).Count
}

# High if any High finding, Medium if any Medium, Low if any Low, otherwise None
function Get-RiskLevel {
    param([string[]]$Codes)
    foreach ($level in 'High', 'Medium', 'Low') {
        if (@($Codes | Where-Object { $Severity[$_] -eq $level }).Count -gt 0) { return $level }
    }
    return 'None'
}

function Get-LocalDomainSid {
    $builtInAdmin = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -like 'S-1-5-21-*-500' } | Select-Object -First 1
    if ($builtInAdmin) { return $builtInAdmin.SID.AccountDomainSid.Value }
    return $null
}

# Reads every member of the local Administrators group through ADSI
function Get-AdministratorsMembers {
    $groupName = (New-Object Security.Principal.SecurityIdentifier $AdministratorsSid).Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"
    foreach ($member in @($group.psbase.Invoke('Members'))) {
        $type = $member.GetType()
        $sidBytes = $type.InvokeMember('objectSid', 'GetProperty', $null, $member, $null)
        $sid = (New-Object Security.Principal.SecurityIdentifier($sidBytes, 0)).Value
        $class = try { [string]$type.InvokeMember('Class', 'GetProperty', $null, $member, $null) } catch { 'Unknown' }
        $resolved = $true
        $name = try { (New-Object Security.Principal.SecurityIdentifier $sid).Translate([Security.Principal.NTAccount]).Value } catch { $resolved = $false; $sid }
        [pscustomobject]@{ Sid = $sid; Name = $name; Class = $class; Resolved = $resolved }
    }
}

# Adds source, approval and local account details to each member
function Add-MemberDetails {
    param($Members, [string]$LocalDomainSid)
    foreach ($member in $Members) {
        $source = Get-MemberSource -Sid $member.Sid -LocalDomainSid $LocalDomainSid
        $details = [ordered]@{
            Name                 = $member.Name
            Sid                  = $member.Sid
            Class                = $member.Class
            Source               = $source
            Resolved             = $member.Resolved
            Approved             = (Test-MatchesAny -Values @($member.Sid, $member.Name) -Patterns $ApprovedMembers)
            Enabled              = $null
            PasswordRequired     = $null
            PasswordNeverExpires = $null
            PasswordLastSet      = $null
        }
        if ($source -eq 'Local' -and $member.Class -eq 'User') {
            $localUser = Get-LocalUser -SID $member.Sid -ErrorAction SilentlyContinue
            if ($localUser) {
                $details.Enabled = $localUser.Enabled
                $details.PasswordRequired = $localUser.PasswordRequired
                $details.PasswordNeverExpires = ($null -eq $localUser.PasswordExpires)
                $details.PasswordLastSet = if ($localUser.PasswordLastSet) { $localUser.PasswordLastSet.ToString('s') } else { $null }
            }
        }
        [pscustomobject]$details
    }
}

function Get-DeviceInfo {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    $dsreg = @(& "$env:SystemRoot\System32\dsregcmd.exe" /status)
    return [ordered]@{
        ComputerName = $env:COMPUTERNAME
        SerialNumber = if ($bios) { $bios.SerialNumber } else { $null }
        OS           = if ($os) { "$($os.Caption) $($os.Version)" } else { $null }
        Domain       = if ($computer -and $computer.PartOfDomain) { $computer.Domain } else { $null }
        EntraJoined  = [bool]($dsreg -match '^\s*AzureAdJoined\s*:\s*YES')
        DomainJoined = [bool]($dsreg -match '^\s*DomainJoined\s*:\s*YES')
    }
}

# Creates the report folder readable only by SYSTEM and Administrators
function Initialize-ReportFolder {
    if (-not (Test-Path -LiteralPath $ReportFolder)) {
        New-Item -Path $ReportFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in 'S-1-5-18', $AdministratorsSid) {
        $identity = New-Object Security.Principal.SecurityIdentifier $sid
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $ReportFolder -AclObject $acl -ErrorAction Stop
}

function Remove-OldReports {
    $reports = @(Get-ChildItem -LiteralPath $ReportFolder -Filter "LocalAdminAudit-$env:COMPUTERNAME-*.json" -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending)
    foreach ($old in ($reports | Select-Object -Skip $KeepReports)) {
        $csv = [IO.Path]::ChangeExtension($old.FullName, '.csv')
        Remove-Item -LiteralPath $old.FullName, $csv -Force -ErrorAction SilentlyContinue
    }
}

function Copy-ReportsToShare {
    param([string[]]$Paths)
    $job = Start-Job -ScriptBlock {
        param($Files, $Share)
        Copy-Item -LiteralPath $Files -Destination $Share -Force -ErrorAction Stop
    } -ArgumentList $Paths, $ReportShare
    if (Wait-Job -Job $job -Timeout $ShareCopyTimeoutSeconds) {
        $copyError = $null
        Receive-Job -Job $job -ErrorAction SilentlyContinue -ErrorVariable copyError | Out-Null
        Remove-Job -Job $job -Force
        if ($copyError) { Write-Log "Copy to $ReportShare failed: $($copyError[0].Exception.Message)"; return $false }
        Write-Log "Reports copied to $ReportShare."
        return $true
    }
    Stop-Job -Job $job
    Remove-Job -Job $job -Force
    Write-Log "Copy to $ReportShare timed out after $ShareCopyTimeoutSeconds seconds."
    return $false
}

function Write-AuditEvent {
    param([int]$EventId, [string]$EntryType, [string]$Message)
    try {
        if (-not [Diagnostics.EventLog]::SourceExists($EventSource)) {
            New-EventLog -LogName Application -Source $EventSource -ErrorAction Stop
        }
        Write-EventLog -LogName Application -Source $EventSource -EventId $EventId -EntryType $EntryType -Message $Message -ErrorAction Stop
    }
    catch {
        Write-Log "Could not write to the event log: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

try {
    Write-Log "===== Local admin audit started on $env:COMPUTERNAME ====="
    $now = Get-Date
    $stamp = $now.ToString('yyyyMMdd-HHmmss')

    # 2-3. Members and their details
    $members = @(Add-MemberDetails -Members @(Get-AdministratorsMembers) -LocalDomainSid (Get-LocalDomainSid))
    Write-Log "Administrators group has $($members.Count) member(s)."

    # 4. Findings
    $rows = @()
    $allFindings = @()
    foreach ($member in $members) {
        $codes = @(Get-MemberFindings -Member $member -Now $now)
        foreach ($code in $codes) {
            $allFindings += [pscustomobject]@{ Code = $code; Severity = $Severity[$code]; Member = $member.Name; Sid = $member.Sid }
        }
        $row = [ordered]@{ ComputerName = $env:COMPUTERNAME; AuditTime = $now.ToString('s') }
        foreach ($property in $member.PSObject.Properties) { $row[$property.Name] = $property.Value }
        $row.Findings = ($codes -join ';')
        $rows += [pscustomobject]$row
        Write-Log ("Member {0} [{1}] {2}/{3} approved={4} findings={5}" -f $member.Name, $member.Sid, $member.Source, $member.Class, $member.Approved, $row.Findings)
    }

    $adminAccountCount = Get-AdminAccountCount -Members $members
    if ($adminAccountCount -gt $MaxAdminAccounts -and -not (Test-MatchesAny -Values @('MultipleAdminAccounts') -Patterns $ExcludeList)) {
        $allFindings += [pscustomobject]@{
            Code = 'MultipleAdminAccounts'; Severity = $Severity['MultipleAdminAccounts']
            Member = "$adminAccountCount enabled admin accounts (limit $MaxAdminAccounts)"; Sid = $null
        }
    }

    $codesFound = @($allFindings | ForEach-Object { $_.Code })
    $risk = Get-RiskLevel -Codes $codesFound
    Write-Log "Enabled admin accounts: $adminAccountCount. Findings: $($allFindings.Count). Risk: $risk."

    # 5. Reports
    Initialize-ReportFolder
    $baseName = Join-Path $ReportFolder "LocalAdminAudit-$env:COMPUTERNAME-$stamp"
    $summary = [ordered]@{
        AuditTime         = $now.ToString('s')
        Device            = Get-DeviceInfo
        MemberCount       = $members.Count
        AdminAccountCount = $adminAccountCount
        MaxAdminAccounts  = $MaxAdminAccounts
        RiskLevel         = $risk
        FindingCount      = $allFindings.Count
        Findings          = $allFindings
        Members           = $members
    }
    $rows | Export-Csv -LiteralPath "$baseName.csv" -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$baseName.json" -Encoding UTF8 -ErrorAction Stop
    Copy-Item -LiteralPath "$baseName.csv" -Destination (Join-Path $ReportFolder 'LocalAdminAudit-Latest.csv') -Force -ErrorAction Stop
    Copy-Item -LiteralPath "$baseName.json" -Destination (Join-Path $ReportFolder 'LocalAdminAudit-Latest.json') -Force -ErrorAction Stop
    Remove-OldReports
    Write-Log "Reports written: $baseName.csv / .json"

    # 6. Optional file share
    if ($ReportShare) { [void](Copy-ReportsToShare -Paths @("$baseName.csv", "$baseName.json")) }

    # 7-8. Event log and summary line
    $grouped = @($allFindings | Group-Object -Property Code | ForEach-Object { "$($_.Name) x$($_.Count)" })
    $findingText = if ($grouped.Count -gt 0) { $grouped -join ', ' } else { 'none' }
    $message = "Local admin audit: $($members.Count) member(s), $adminAccountCount enabled admin account(s), risk $risk, findings: $findingText. Report: $baseName.csv"

    if ($allFindings.Count -gt 0) {
        Write-AuditEvent -EventId 1001 -EntryType Warning -Message $message
        Write-Log $message
        Write-Output $message
        if ($ReportFindingsAsFailure) { exit 1 }
        exit 0
    }

    Write-AuditEvent -EventId 1000 -EntryType Information -Message $message
    Write-Log $message
    Write-Output $message
    exit 0
}
catch {
    $message = "Local admin audit failed: $($_.Exception.Message)"
    Write-Log $message
    Write-Output $message
    exit 1
}
