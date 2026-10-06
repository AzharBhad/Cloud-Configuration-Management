<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Removes unauthorized members from the local Administrators group.

.DESCRIPTION
    Removes every member of the local Administrators group that is not in $ExcludeList
    (Remove-LocalGroupMember, with an ADSI fallback for orphaned SIDs). The accounts themselves
    are NOT deleted - they only lose administrator rights. Removal takes effect at the user's
    next sign-in.

    Safety rules:
      - Microsoft Entra SIDs (S-1-12-1-...) that are not in $ExcludeList are kept while
        $ProtectUnknownEntraSids is $true. They are reported as Protected, and the device stays
        non-compliant until you add your Entra role SIDs to $ExcludeList and set it to $false.
      - If removing members would leave no allowed member other than the built-in Administrator
        (-500), nothing is removed. The device must keep a working admin.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = The Administrators group only contains allowed members.
      1 = Members were protected, the safety rule stopped the removal, or a removal failed. See the log.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\LocalAdminsRemediation.log
#>

# Members of the local Administrators group that are allowed (kept) - keep in sync with the detection script
# Matched against the member's SID and name (DOMAIN\Name), wildcards allowed.
$ExcludeList = @(
    'S-1-5-21-*-500'    # Built-in local Administrator account (managed by Windows LAPS)
    'S-1-5-21-*-512'    # Domain Admins (hybrid joined devices)
    # Microsoft Entra roles - add your tenant's SIDs (see README.md), for example:
    # 'S-1-12-1-1111111111-2222222222-3333333333-4444444444'   # Global Administrator role
    # 'S-1-12-1-5555555555-6666666666-7777777777-8888888888'   # Microsoft Entra Joined Device Local Administrator role
)

# Microsoft Entra SIDs (S-1-12-1-...) not in $ExcludeList are reported but NOT removed while this
# is $true. Entra role SIDs look the same as user SIDs, so removing unknown ones could remove the
# Global Administrator role from the device. Set to $false once your role SIDs are in $ExcludeList. - keep in sync with the detection script
$ProtectUnknownEntraSids = $true

$AdministratorsSid = 'S-1-5-32-544'

function Test-Excluded {
    param([string]$Name)
    foreach ($pattern in $ExcludeList) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

# Returns every member of the local Administrators group with its SID and name.
# Uses ADSI because Get-LocalGroupMember fails when the group contains orphaned SIDs.
function Get-AdministratorsMembers {
    $groupName = (New-Object Security.Principal.SecurityIdentifier $AdministratorsSid).Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
    $group = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"
    foreach ($member in @($group.psbase.Invoke('Members'))) {
        $sidBytes = $member.GetType().InvokeMember('objectSid', 'GetProperty', $null, $member, $null)
        $sid = (New-Object Security.Principal.SecurityIdentifier($sidBytes, 0)).Value
        $name = try { (New-Object Security.Principal.SecurityIdentifier $sid).Translate([Security.Principal.NTAccount]).Value } catch { $sid }
        [pscustomobject]@{ Sid = $sid; Name = $name }
    }
}

# Sorts members into Allowed, Remove and Protected (unknown Entra SIDs kept for safety)
function Get-MemberDecisions {
    param($Members)
    foreach ($member in $Members) {
        $decision = if ((Test-Excluded -Name $member.Sid) -or (Test-Excluded -Name $member.Name)) { 'Allowed' }
                    elseif ($ProtectUnknownEntraSids -and $member.Sid -like 'S-1-12-1-*') { 'Protected' }
                    else { 'Remove' }
        [pscustomobject]@{ Sid = $member.Sid; Name = $member.Name; Decision = $decision }
    }
}

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\LocalAdminsRemediation.log"

function Write-Log {
    param([string]$Message)
    $line = "{0} [REMEDIATE] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

# True when at least one member other than the built-in Administrator would remain
function Test-AdminRemains {
    param($Decisions)
    return (@($Decisions | Where-Object { $_.Decision -ne 'Remove' -and $_.Sid -notlike 'S-1-5-21-*-500' }).Count -gt 0)
}

function Remove-AdminMember {
    param($Member)
    try {
        Remove-LocalGroupMember -SID $AdministratorsSid -Member $Member.Sid -ErrorAction Stop
        Write-Log "Removed $($Member.Name) ($($Member.Sid)) from Administrators."
        return $true
    }
    catch {
        Write-Log "Remove-LocalGroupMember failed for $($Member.Sid) ($($_.Exception.Message)). Trying ADSI."
    }
    try {
        $groupName = (New-Object Security.Principal.SecurityIdentifier $AdministratorsSid).Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
        $group = [ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group"
        $group.Remove("WinNT://$($Member.Sid)")
        Write-Log "Removed $($Member.Name) ($($Member.Sid)) from Administrators with ADSI."
        return $true
    }
    catch {
        Write-Log "Failed to remove $($Member.Name) ($($Member.Sid)): $($_.Exception.Message)"
        return $false
    }
}

function Exit-Remediation {
    param([int]$Code, [string]$Message)
    Write-Log $Message
    Write-Output $Message
    exit $Code
}

try {
    Write-Log 'Starting local Administrators remediation.'
    $decisions = @(Get-MemberDecisions -Members @(Get-AdministratorsMembers))
    $toRemove = @($decisions | Where-Object { $_.Decision -eq 'Remove' })
    $protected = @($decisions | Where-Object { $_.Decision -eq 'Protected' })

    if ($toRemove.Count -gt 0 -and -not (Test-AdminRemains -Decisions $decisions)) {
        Exit-Remediation 1 "Safety stop: removing $($toRemove.Count) member(s) would leave no admin other than the built-in Administrator. Nothing removed. Add the right accounts or groups to `$ExcludeList."
    }

    $failed = @()
    foreach ($member in $toRemove) {
        if (-not (Remove-AdminMember -Member $member)) { $failed += "$($member.Name) ($($member.Sid))" }
    }

    $removedCount = $toRemove.Count - $failed.Count
    $problems = @()
    if ($failed.Count -gt 0) { $problems += "could not remove: $($failed -join '; ')" }
    if ($protected.Count -gt 0) {
        $problems += "kept unknown Entra SIDs (`$ProtectUnknownEntraSids): $((@($protected | ForEach-Object { $_.Sid })) -join '; ')"
    }

    if ($problems.Count -gt 0) {
        Exit-Remediation 1 "Removed $removedCount unauthorized admin(s); $($problems -join '; ')."
    }
    Exit-Remediation 0 "Removed $removedCount unauthorized admin(s). The Administrators group only contains allowed members."
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
