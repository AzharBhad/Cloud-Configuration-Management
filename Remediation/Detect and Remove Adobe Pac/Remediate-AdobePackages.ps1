<#
.SYNOPSIS
    Intune Remediations - remediation script.
    Silently removes Adobe packages detected by Detect-AdobePackages.ps1.

.DESCRIPTION
    Removes Adobe software found in:
      1. Installed programs (Win32/MSI) - HKLM uninstall keys, 64-bit and 32-bit.
      2. Per-user installed programs - uninstall keys of every loaded user hive (HKU).
      3. Microsoft Store (AppX/MSIX) packages - removed for all users and de-provisioned
         so they are not installed for new users.

    Uninstall method per program:
      - MSI (product code GUID)         -> msiexec.exe /x {GUID} /qn /norestart
      - QuietUninstallString present    -> run it as-is
      - Adobe Creative Cloud desktop app -> Creative Cloud Uninstaller.exe -u
      - Other EXE uninstallers          -> skipped and logged (no known silent switch)

    Creative Cloud apps are removed before the Creative Cloud desktop app.
    Each uninstall has a timeout so the script finishes within Intune's limit.

    The 7-day schedule is set on the Intune assignment (Schedule: Daily, Repeats every 7 days).
    See README.md.

    Exit codes (read by Intune):
      0 = All Adobe packages removed.
      1 = One or more Adobe packages could not be removed.

.NOTES
    Run as      : System (Run this script using the logged-on credentials = No)
    Architecture: 64-bit PowerShell (Run script in 64-bit PowerShell = Yes)
    Log file    : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeRemediation.log
    A reboot may be needed to finish some uninstalls; the script does not force one.
#>

# Display names to keep (wildcards allowed) - keep in sync with the detection script
$ExcludeList = @()

# Maximum time to wait for a single uninstall (minutes)
$UninstallTimeoutMinutes = 15

$LogFile = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\AdobeRemediation.log"

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

function Test-IsAdobe {
    param([string]$Name, [string]$Publisher)
    return ($Name -like 'Adobe*' -or $Publisher -like 'Adobe*')
}

function Get-AdobeInstalledPrograms {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } |
        ForEach-Object {
            $paths += "Registry::HKEY_USERS\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        }

    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -and
                ($_.UninstallString -or $_.QuietUninstallString) -and
                -not $_.ParentKeyName -and
                (Test-IsAdobe -Name $_.DisplayName -Publisher $_.Publisher) -and
                -not (Test-Excluded -Name $_.DisplayName)
            }
    }
}

# Splits an uninstall command line into executable path and arguments
function Split-CommandLine {
    param([string]$CommandLine)
    $CommandLine = $CommandLine.Trim()
    if ($CommandLine -match '^"([^"]+)"\s*(.*)$') {
        return @{ FilePath = $Matches[1]; Arguments = $Matches[2] }
    }
    if ($CommandLine -match '^(.+?\.exe)\s*(.*)$') {
        return @{ FilePath = $Matches[1]; Arguments = $Matches[2] }
    }
    return @{ FilePath = $CommandLine; Arguments = '' }
}

function Invoke-Uninstall {
    param([string]$FilePath, [string]$Arguments, [string]$Name)

    Write-Log "Uninstalling '$Name': `"$FilePath`" $Arguments"
    $startParams = @{ FilePath = $FilePath; PassThru = $true; WindowStyle = 'Hidden' }
    if ($Arguments) { $startParams.ArgumentList = $Arguments }
    $process = Start-Process @startParams

    if (-not $process.WaitForExit($UninstallTimeoutMinutes * 60 * 1000)) {
        Write-Log "Timed out after $UninstallTimeoutMinutes minutes: '$Name'. Stopping uninstaller."
        try { $process.Kill() } catch { }
        return $false
    }

    # 0 = success, 3010 / 1641 = success, reboot required
    if ($process.ExitCode -in 0, 3010, 1641) {
        Write-Log "Removed '$Name' (exit code $($process.ExitCode))."
        return $true
    }
    Write-Log "Failed to remove '$Name' (exit code $($process.ExitCode))."
    return $false
}

function Remove-AdobeProgram {
    param($Program)

    $name = $Program.DisplayName
    $keyName = $Program.PSChildName

    # MSI: uninstall by product code
    if ($keyName -match '^\{[0-9A-Fa-f-]{36}\}$' -or $Program.UninstallString -match 'msiexec') {
        $productCode = if ($keyName -match '^\{[0-9A-Fa-f-]{36}\}$') { $keyName }
                       elseif ($Program.UninstallString -match '(\{[0-9A-Fa-f-]{36}\})') { $Matches[1] }
        if ($productCode) {
            return Invoke-Uninstall -FilePath "$env:SystemRoot\System32\msiexec.exe" `
                -Arguments "/x $productCode /qn /norestart" -Name $name
        }
    }

    # Vendor-provided silent uninstall command
    if ($Program.QuietUninstallString) {
        $cmd = Split-CommandLine $Program.QuietUninstallString
        return Invoke-Uninstall -FilePath $cmd.FilePath -Arguments $cmd.Arguments -Name $name
    }

    # Adobe Creative Cloud desktop app
    if ($Program.UninstallString -match 'Creative Cloud Uninstaller\.exe') {
        $cmd = Split-CommandLine $Program.UninstallString
        return Invoke-Uninstall -FilePath $cmd.FilePath -Arguments '-u' -Name $name
    }

    Write-Log "Skipped '$name': no silent uninstall method known. UninstallString: $($Program.UninstallString)"
    return $false
}

function Remove-AdobeAppxPackages {
    $success = $true

    $packages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -like '*Adobe*' -or $_.Publisher -like '*Adobe*') -and
            -not (Test-Excluded -Name $_.Name)
        }
    foreach ($package in $packages) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log "Removed AppX package '$($package.PackageFullName)' for all users."
        }
        catch {
            Write-Log "Failed to remove AppX package '$($package.PackageFullName)': $($_.Exception.Message)"
            $success = $false
        }
    }

    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*Adobe*' -and -not (Test-Excluded -Name $_.DisplayName) }
    foreach ($package in $provisioned) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -ErrorAction Stop | Out-Null
            Write-Log "Removed provisioned AppX package '$($package.PackageName)'."
        }
        catch {
            Write-Log "Failed to remove provisioned AppX package '$($package.PackageName)': $($_.Exception.Message)"
            $success = $false
        }
    }

    return $success
}

try {
    Write-Log 'Starting Adobe package removal.'
    $failed = @()

    # Remove Creative Cloud apps first and the Creative Cloud desktop app last
    $programs = @(Get-AdobeInstalledPrograms) |
        Sort-Object -Property @{ Expression = { $_.DisplayName -like 'Adobe Creative Cloud*' } }, DisplayName

    foreach ($program in $programs) {
        if (-not (Remove-AdobeProgram -Program $program)) {
            $failed += $program.DisplayName
        }
    }

    if (-not (Remove-AdobeAppxPackages)) {
        $failed += 'One or more AppX packages'
    }

    if ($failed.Count -gt 0) {
        Write-Log "Finished with failures: $($failed -join '; ')"
        Write-Output "Adobe removal incomplete. Not removed: $($failed -join '; ')"
        exit 1
    }

    Write-Log 'All Adobe packages removed.'
    Write-Output 'All Adobe packages removed.'
    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
