<#
.SYNOPSIS
    Intune Remediations - detection script.
    Detects OneDrive for work or school sync problems for the signed-in user on
    Windows 10 / Windows 11 devices.

.DESCRIPTION
    Runs as the signed-in user (OneDrive runs per user). Reports the user when:
      - NotInstalled      : OneDrive.exe is not installed (per-machine or per-user)
      - NotSignedIn       : no work or school account is set up in OneDrive (Business1)
      - SyncFolderMissing : the account is set up but its sync folder no longer exists
      - NotRunning        : OneDrive is not running in the user's session

    Users whose user name matches $ExcludeList are always reported as compliant.

    Exit codes (read by Intune):
      0 = OneDrive is installed, signed in, its folder exists and it is running.
      1 = A sync problem was found -> Intune runs the remediation script.

.NOTES
    Run as      : The signed-in user (Run this script using the logged-on credentials = Yes)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : %TEMP%\OneDriveSyncRemediation.log (in the user's profile)
#>

# User names to skip (wildcards allowed), e.g. @('kiosk*', 'svc_*')
$ExcludeList = @()

$AccountKey = 'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1'
$LogFile = "$env:TEMP\OneDriveSyncRemediation.log"

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

function Get-OneDrivePath {
    $paths = @(
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    )
    return ($paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1)
}

# Returns the first OneDrive problem, or $null when OneDrive is healthy
function Get-OneDriveIssue {
    param([string]$ExePath, $Account, [bool]$FolderExists, [bool]$Running)
    if (-not $ExePath) { return 'NotInstalled' }
    if (-not $Account -or -not $Account.UserEmail) { return 'NotSignedIn' }
    if (-not $FolderExists) { return 'SyncFolderMissing' }
    if (-not $Running) { return 'NotRunning' }
    return $null
}

function Test-OneDriveRunning {
    $sessionId = (Get-Process -Id $PID).SessionId
    return [bool](Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId })
}

try {
    if (Test-Excluded -Name $env:USERNAME) {
        Write-Log "$env:USERNAME is in the exclude list. Skipping."
        Write-Output "$env:USERNAME is excluded from the OneDrive check."
        exit 0
    }

    $exePath = Get-OneDrivePath
    $account = Get-ItemProperty -Path $AccountKey -ErrorAction SilentlyContinue
    $folderExists = [bool]($account -and $account.UserFolder -and (Test-Path -LiteralPath $account.UserFolder))
    $issue = Get-OneDriveIssue -ExePath $exePath -Account $account -FolderExists $folderExists -Running (Test-OneDriveRunning)
    $state = "User=$env:USERNAME, Account=$($account.UserEmail), Folder=$($account.UserFolder)"

    if ($issue) {
        Write-Log "OneDrive issue '$issue'. $state"
        Write-Output "OneDrive sync problem ($issue). $state"
        exit 1
    }

    Write-Log "OneDrive is healthy. $state"
    Write-Output "OneDrive is healthy. $state"
    exit 0
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output "Detection error: $($_.Exception.Message)"
    # Treat errors as non-compliant so the device is reported and remediation is attempted
    exit 1
}
