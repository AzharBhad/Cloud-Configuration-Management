<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Repairs OneDrive for work or school sync for the signed-in user.

.DESCRIPTION
    Runs as the signed-in user. Fixes, by issue:
      NotRunning        -> Starts OneDrive.exe /background.
      NotSignedIn       -> Starts OneDrive. If the "Silently sign in users to the OneDrive sync app
                           with their Windows credentials" policy (SilentAccountConfig) is on,
                           OneDrive signs in by itself. If it is off, the user must sign in - Skipped.
      SyncFolderMissing -> Resets OneDrive (OneDrive.exe /reset) and starts it again, but only when
                           $AllowReset is $true. A reset re-syncs all files, so it is off by default.
      NotInstalled      -> Skipped. Deploy OneDrive with Intune (it is part of Microsoft 365 Apps and
                           Windows) - a user-context script can't install it for all users.

    No files are deleted and the device is not restarted.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = OneDrive is installed, signed in, its folder exists and it is running.
      1 = A problem remains (skipped or not fixed). See the log.

.NOTES
    Run as      : The signed-in user (Run this script using the logged-on credentials = Yes)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : %TEMP%\OneDriveSyncRemediation.log (in the user's profile)
#>

# User names to skip (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

# Allow OneDrive.exe /reset when the sync folder is missing (re-syncs everything)
$AllowReset = $false

# How long to wait for OneDrive to start or sign in (seconds)
$StartWaitSeconds = 60

$AccountKey = 'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1'
$LogFile = "$env:TEMP\OneDriveSyncRemediation.log"

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

function Get-OneDrivePath {
    $paths = @(
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    )
    return ($paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1)
}

# Same logic as the detection script
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

function Get-CurrentIssue {
    $account = Get-ItemProperty -Path $AccountKey -ErrorAction SilentlyContinue
    $folderExists = [bool]($account -and $account.UserFolder -and (Test-Path -LiteralPath $account.UserFolder))
    return (Get-OneDriveIssue -ExePath (Get-OneDrivePath) -Account $account -FolderExists $folderExists -Running (Test-OneDriveRunning))
}

function Start-OneDrive {
    param([string]$ExePath)
    if (-not (Test-OneDriveRunning)) {
        Start-Process -FilePath $ExePath -ArgumentList '/background' -ErrorAction Stop
        Write-Log 'Started OneDrive.'
    }
    # Give OneDrive time to start and, with silent sign-in, to set up the account
    for ($i = 0; $i -lt $StartWaitSeconds; $i += 5) {
        Start-Sleep -Seconds 5
        if (-not (Get-CurrentIssue)) { break }
    }
}

function Test-SilentSignInPolicy {
    $value = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive' -Name 'SilentAccountConfig' -ErrorAction SilentlyContinue).SilentAccountConfig
    return ($value -eq 1)
}

function Exit-Remediation {
    param([int]$Code, [string]$Message)
    Write-Log $Message
    Write-Output $Message
    exit $Code
}

try {
    Write-Log "Starting OneDrive sync remediation for $env:USERNAME."

    if (Test-Excluded -Name $env:USERNAME) {
        Exit-Remediation 0 "$env:USERNAME is excluded from the OneDrive check."
    }

    $exePath = Get-OneDrivePath
    $issue = Get-CurrentIssue
    if (-not $issue) { Exit-Remediation 0 'OneDrive is already healthy.' }
    Write-Log "Issue found: $issue"

    switch ($issue) {
        'NotInstalled' {
            Exit-Remediation 1 'Skipped: OneDrive is not installed. Deploy it with Intune.'
        }
        'NotSignedIn' {
            if (-not (Test-SilentSignInPolicy)) {
                Start-OneDrive -ExePath $exePath
                Exit-Remediation 1 "Skipped: OneDrive is not signed in and the SilentAccountConfig policy is off. The user must sign in (OneDrive was started)."
            }
            Start-OneDrive -ExePath $exePath
        }
        'SyncFolderMissing' {
            if (-not $AllowReset) {
                Exit-Remediation 1 'Skipped: the OneDrive sync folder is missing. Set $AllowReset = $true to reset OneDrive automatically, or reset it by hand.'
            }
            Write-Log 'Resetting OneDrive (OneDrive.exe /reset).'
            Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue |
                Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId } |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Process -FilePath $exePath -ArgumentList '/reset' -Wait -ErrorAction Stop
            Start-OneDrive -ExePath $exePath
        }
        'NotRunning' {
            Start-OneDrive -ExePath $exePath
        }
    }

    $remaining = Get-CurrentIssue
    if ($remaining) {
        Exit-Remediation 1 "OneDrive still has a problem ($remaining). It may need more time to sign in or sync; the next run checks again."
    }
    Exit-Remediation 0 "OneDrive repaired ($issue fixed)."
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
