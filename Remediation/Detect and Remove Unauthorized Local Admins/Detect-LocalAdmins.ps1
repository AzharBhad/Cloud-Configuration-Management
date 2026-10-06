<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects unauthorized members of the local Administrators group on Windows 10 / Windows 11 devices.

.DESCRIPTION
    Lists every member of the local Administrators group (found by its well-known SID S-1-5-32-544,
    so it works on every Windows language) and reports the device when any member is not in
    $ExcludeList (the list of allowed members).

    Kept by default:
      - The built-in local Administrator account (SID ending -500), used by Windows LAPS.
      - Domain Admins (SID ending -512) on hybrid joined devices.
      - Microsoft Entra SIDs (S-1-12-1-...) are reported, but are only removed when
        $ProtectUnknownEntraSids is $false - see README.md.

    Exit codes (read by Intune):
      0 = The Administrators group only contains allowed members.
      1 = Unauthorized members found -> Intune runs the remediation script.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\LocalAdminsRemediation.log
#>

# Members of the local Administrators group that are allowed (kept)
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
# Global Administrator role from the device. Set to $false once your role SIDs are in $ExcludeList.
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
    $line = "{0} [DETECT] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
}

try {
    $decisions = @(Get-MemberDecisions -Members @(Get-AdministratorsMembers))
    $unauthorized = @($decisions | Where-Object { $_.Decision -ne 'Allowed' })
    Write-Log "Administrators members: $((@($decisions | ForEach-Object { "$($_.Name) [$($_.Sid)] $($_.Decision)" })) -join '; ')"

    if ($unauthorized.Count -gt 0) {
        $labels = @($unauthorized | ForEach-Object { "$($_.Name) ($($_.Sid))" })
        $summary = "Unauthorized local admins ($($unauthorized.Count)): $($labels -join '; ')"
        if ($summary.Length -gt 2000) { $summary = $summary.Substring(0, 2000) + '...' }
        Write-Output $summary
        exit 1
    }

    Write-Output 'The local Administrators group only contains allowed members.'
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
