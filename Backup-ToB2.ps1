param(
    [switch]$NonInteractive,
    [switch]$Setup
)

<#
.SYNOPSIS
    Sync a local folder to a Backblaze B2 bucket using rclone.
    Can run interactively to build a .env and create a Scheduled Task,
    or non-interactively (for Task Scheduler) using that .env.

.DESCRIPTION
    - Interactive mode:
        * Asks for all required backup settings (local path, remote path, logs, etc.).
        * Lets the user customize rclone performance parameters.
        * Writes a .env file alongside the script.
        * Prompts for scheduling (daily, weekly, or at logon) and creates a Scheduled Task
          that runs this script non-interactively.
    - Non-interactive mode:
        * Loads configuration from the .env file only.
        * Ensures rclone is installed.
        * Runs rclone sync and logs output.
        * Intended to be called from Windows Task Scheduler.

.NOTES
    - Run the interactive setup as Administrator (required for:
        * rclone system-wide install
        * scheduled task creation
        * updating system PATH)
    - The .env file lives next to this script by default.
    - Do NOT commit real secrets in a public repo.
#>

# -------------------------
# BASIC SETUP
# -------------------------

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptPath  = $MyInvocation.MyCommand.Path
$EnvFilePath = Join-Path $ScriptDir ".env"

# Set a default log file in case we log before reading .env
if (-not $global:LogFile) {
    $global:LogFile = "C:\Logs\B2Backup.log"
}

# -------------------------
# FUNCTIONS
# -------------------------

function Write-Log {
    param(
        [string]$Message
    )

    if (-not $global:LogFile) {
        $global:LogFile = "C:\Logs\B2Backup.log"
    }

    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $Entry = "$Timestamp - $Message"
    Write-Output $Entry

    $LogDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    $Entry | Out-File -Append -FilePath $LogFile -Encoding UTF8
}

function Ensure-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Host "This script must be run as Administrator. Please re-run with elevated privileges." -ForegroundColor Red
        Write-Log "ERROR: Script not run as Administrator."
        exit 1
    }
}

function Load-DotEnv {
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Host "ERROR: .env file not found at '$Path'." -ForegroundColor Red
        Write-Log "ERROR: .env file not found at '$Path'."
        exit 1
    }

    $envTable = @{}

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }            # skip empty
        if ($line.StartsWith("#")) { return } # skip comments

        $idx = $line.IndexOf("=")
        if ($idx -lt 1) { return }

        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()

        # Strip surrounding quotes if present
        if (($val.StartsWith('"') -and $val.EndsWith('"')) -or
            ($val.StartsWith("'") -and $val.EndsWith("'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }

        $envTable[$key] = $val

        # Also set as process environment variable for child processes (e.g. rclone)
        [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
    }

    return $envTable
}

function Write-DotEnv {
    param(
        [string]$Path,
        [hashtable]$EnvVars
    )

    $lines = @()
    $lines += "# .env for B2 backup script"
    $lines += "# Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "# Edit with care."

    foreach ($key in ($EnvVars.Keys | Sort-Object)) {
        $val = $EnvVars[$key]
        if ($null -eq $val) { $val = "" }
        $lines += "$key=$val"
    }

    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $lines | Set-Content -Path $Path -Encoding UTF8

    Write-Host "Wrote configuration to '$Path'." -ForegroundColor Green
    Write-Log "Wrote .env configuration to '$Path'."
}

function Update-SystemPath {
    param(
        [string]$NewPathEntry
    )

    $envKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    $currentPath = (Get-ItemProperty -Path $envKey -Name Path).Path

    if ($currentPath -notlike "*$NewPathEntry*") {
        $newPath = $currentPath.TrimEnd(';') + ";" + $NewPathEntry
        Set-ItemProperty -Path $envKey -Name Path -Value $newPath
        Write-Log "Added '$NewPathEntry' to system PATH."

        # Notify system of environment change
        $signature = @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
"@
        Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue | Out-Null
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x1A
        $result = [UIntPtr]::Zero
        [Win32]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
        Write-Log "Broadcasted environment change."
    }
    else {
        Write-Log "System PATH already contains '$NewPathEntry'."
    }
}

function Install-Rclone {
    param(
        [string]$InstallDir,
        [string]$DownloadUrl
    )

    Write-Log "rclone not found. Installing to '$InstallDir'..."

    if (-not (Test-Path $InstallDir)) {
        New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
        Write-Log "Created directory '$InstallDir'."
    }

    $tempDir = New-Item -ItemType Directory -Path ([IO.Path]::Combine($env:TEMP, "rclone_install")) -Force
    $zipPath = Join-Path $tempDir.FullName "rclone.zip"

    # Ensure TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Log "Downloading rclone from $DownloadUrl to $zipPath..."
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
    }
    catch {
        Write-Log "ERROR: Failed to download rclone. $_"
        throw "Failed to download rclone."
    }

    Write-Log "Extracting rclone archive..."
    try {
        Expand-Archive -Path $zipPath -DestinationPath $tempDir.FullName -Force
    }
    catch {
        Write-Log "ERROR: Failed to extract rclone. $_"
        throw "Failed to extract rclone."
    }

    $rcloneExe = Get-ChildItem -Path $tempDir.FullName -Recurse -Filter "rclone.exe" | Select-Object -First 1
    if (-not $rcloneExe) {
        Write-Log "ERROR: Could not find rclone.exe in extracted files."
        throw "rclone.exe not found in archive."
    }

    $RcloneExePath = Join-Path $InstallDir "rclone.exe"

    Write-Log "Copying rclone.exe to '$InstallDir'..."
    Copy-Item -Path $rcloneExe.FullName -Destination $RcloneExePath -Force

    # Cleanup
    Remove-Item -Path $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Temporary install files cleaned up."

    # Add to PATH
    Update-SystemPath -NewPathEntry $InstallDir

    Write-Log "rclone installation completed."
}

function Ensure-Rclone {
    param(
        [string]$InstallDir,
        [string]$DownloadUrl
    )

    $RcloneExePath = Join-Path $InstallDir "rclone.exe"

    # Check explicit path
    if (Test-Path $RcloneExePath) {
        Write-Log "Found rclone at '$RcloneExePath'."
        return
    }

    # Check PATH
    $cmd = Get-Command rclone -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Log "rclone already available in PATH at '$($cmd.Source)'."
        return
    }

    Install-Rclone -InstallDir $InstallDir -DownloadUrl $DownloadUrl
}

function Cleanup-Logs {
    param(
        [string]$LogPath,
        [int]$RetentionDays
    )

    if (Test-Path $LogPath) {
        $logItem = Get-Item $LogPath -ErrorAction SilentlyContinue
        if ($null -ne $logItem -and $logItem.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays)) {
            Write-Log "Log file older than $RetentionDays days. Rotating..."
            Remove-Item $LogPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-RcloneRemote {
    param(
        [string]$Remote
    )
    Write-Log "Testing rclone remote: '$Remote'..."
    try {
        & rclone ls $Remote 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "WARNING: rclone remote '$Remote' may not be configured correctly. Please run 'rclone config'."
        }
        else {
            Write-Log "rclone remote '$Remote' appears reachable."
        }
    }
    catch {
        Write-Log "WARNING: Failed to validate rclone remote '$Remote'. $_"
    }
}

function Setup-ScheduledTask {
    param(
        [string]$ScriptFullPath,
        [string]$DefaultTaskName = "B2Backup"
    )

    Write-Host ""
    Write-Host "=== Scheduled Task Configuration ===" -ForegroundColor Cyan
    Write-Host "This will create or update a Windows Scheduled Task that runs this script non-interactively."
    Write-Host ""

    # Ensure ScheduledTasks module
    if (-not (Get-Module -ListAvailable -Name ScheduledTasks)) {
        try {
            Import-Module ScheduledTasks -ErrorAction Stop
        }
        catch {
            Write-Host "ERROR: The ScheduledTasks module is not available on this system." -ForegroundColor Red
            Write-Log "ERROR: ScheduledTasks module not available. $_"
            return
        }
    }
    else {
        Import-Module ScheduledTasks -ErrorAction SilentlyContinue | Out-Null
    }

    $taskName = Read-Host "Task name [default: $DefaultTaskName]"
    if ([string]::IsNullOrWhiteSpace($taskName)) {
        $taskName = $DefaultTaskName
    }

    $defaultDesc = "Sync local folder to Backblaze B2 via rclone using $ScriptFullPath"
    $taskDescription = Read-Host "Task description [default: $defaultDesc]"
    if ([string]::IsNullOrWhiteSpace($taskDescription)) {
        $taskDescription = $defaultDesc
    }

    Write-Host ""
    Write-Host "How often should the backup run?" -ForegroundColor Yellow
    Write-Host "  1) Daily at a specific time"
    Write-Host "  2) Weekly on a specific day and time"
    Write-Host "  3) At user logon"
    $scheduleChoice = Read-Host "Enter 1, 2, or 3 [default: 1]"
    if ([string]::IsNullOrWhiteSpace($scheduleChoice)) { $scheduleChoice = "1" }

    $trigger = $null

    switch ($scheduleChoice) {
        "2" {
            # Weekly
            $dayDefault = "Sunday"
            $dow = Read-Host "Day of week (e.g. Monday, Tue, Saturday) [default: $dayDefault]"
            if ([string]::IsNullOrWhiteSpace($dow)) { $dow = $dayDefault }

            $timeDefault = "02:00"
            $timeString = Read-Host "Time of day (24-hour HH:mm) [default: $timeDefault]"
            if ([string]::IsNullOrWhiteSpace($timeString)) { $timeString = $timeDefault }

            try {
                $parsedTime = [DateTime]::ParseExact($timeString, "HH:mm", $null)
            }
            catch {
                Write-Host "Invalid time format. Falling back to $timeDefault." -ForegroundColor Yellow
                $parsedTime = [DateTime]::ParseExact($timeDefault, "HH:mm", $null)
            }

            $today = Get-Date
            $at = Get-Date -Year $today.Year -Month $today.Month -Day $today.Day -Hour $parsedTime.Hour -Minute $parsedTime.Minute -Second 0

            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dow -At $at
        }
        "3" {
            # At logon
            $trigger = New-ScheduledTaskTrigger -AtLogOn
        }
        default {
            # Daily
            $timeDefault = "02:00"
            $timeString = Read-Host "Time of day (24-hour HH:mm) [default: $timeDefault]"
            if ([string]::IsNullOrWhiteSpace($timeString)) { $timeString = $timeDefault }

            try {
                $parsedTime = [DateTime]::ParseExact($timeString, "HH:mm", $null)
            }
            catch {
                Write-Host "Invalid time format. Falling back to $timeDefault." -ForegroundColor Yellow
                $parsedTime = [DateTime]::ParseExact($timeDefault, "HH:mm", $null)
            }

            $today = Get-Date
            $at = Get-Date -Year $today.Year -Month $today.Month -Day $today.Day -Hour $parsedTime.Hour -Minute $parsedTime.Minute -Second 0

            $trigger = New-ScheduledTaskTrigger -Daily -At $at
        }
    }

    $psExec   = "powershell.exe"
    $psArgs   = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptFullPath`" -NonInteractive"
    $workDir  = Split-Path $ScriptFullPath -Parent

    $action = New-ScheduledTaskAction -Execute $psExec -Argument $psArgs -WorkingDirectory $workDir

    Write-Host ""
    Write-Host "Select the account the task should run as." -ForegroundColor Yellow
    Write-Host "It should typically be the same user that configured rclone (so it can find rclone.conf)."
    $cred = Get-Credential -Message "Enter credentials for the account that should run the backup task."

    $principal = New-ScheduledTaskPrincipal -UserId $cred.UserName -LogonType Password -RunLevel Highest

    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Description $taskDescription

    # If task already exists, remove it to avoid conflict
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Task '$taskName' already exists and will be replaced." -ForegroundColor Yellow
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Log "Unregistered existing scheduled task '$taskName'."
        }
        catch {
            Write-Log "ERROR: Failed to unregister existing task '$taskName'. $_"
            Write-Host "ERROR: Could not remove existing task '$taskName'." -ForegroundColor Red
            return
        }
    }

    try {
        Register-ScheduledTask -TaskName $taskName -InputObject $task -User $cred.UserName -Password $cred.GetNetworkCredential().Password -ErrorAction Stop
        Write-Host "Scheduled Task '$taskName' created/updated successfully." -ForegroundColor Green
        Write-Log "Scheduled Task '$taskName' created/updated successfully."
    }
    catch {
        Write-Host "ERROR: Failed to register scheduled task '$taskName'." -ForegroundColor Red
        Write-Log "ERROR: Failed to register scheduled task '$taskName'. $_"
    }
}

function Run-InteractiveSetup {
    Write-Host ""
    Write-Host "=== Backup Configuration & Scheduling Wizard ===" -ForegroundColor Cyan
    Write-Host "This will create/update your .env configuration and (optionally) a Scheduled Task."
    Write-Host ""

    # -------- Backup configuration --------

    # LOCAL_PATH
    do {
        $localPath = Read-Host "Enter the full local folder path to back up (LOCAL_PATH)"
        if ([string]::IsNullOrWhiteSpace($localPath)) {
            Write-Host "Local path cannot be empty." -ForegroundColor Yellow
            continue
        }

        if (-not (Test-Path $localPath)) {
            $create = Read-Host "Path '$localPath' does not exist. Create it? (Y/N, default Y)"
            if ([string]::IsNullOrWhiteSpace($create) -or $create -match '^[Yy]') {
                try {
                    New-Item -ItemType Directory -Path $localPath -Force | Out-Null
                    Write-Host "Created directory '$localPath'." -ForegroundColor Green
                }
                catch {
                    Write-Host "Failed to create directory. Please try a different path." -ForegroundColor Red
                    continue
                }
            }
        }

        if (Test-Path $localPath) {
            break
        }
    } while ($true)

    # REMOTE_PATH
    Write-Host ""
    Write-Host "The remote path is the rclone remote + path, e.g.: b2:my-remote-bucket/server1" -ForegroundColor Yellow
    do {
        $remotePath = Read-Host "Enter rclone remote path (REMOTE_PATH, e.g. b2:my-remote-bucket/folder)"
        if ([string]::IsNullOrWhiteSpace($remotePath)) {
            Write-Host "Remote path cannot be empty." -ForegroundColor Yellow
        }
        else {
            break
        }
    } while ($true)

    # LOG_FILE
    Write-Host ""
    $logDefault = "C:\Logs\B2Backup.log"
    $logFile = Read-Host "Enter log file path (LOG_FILE) [default: $logDefault]"
    if ([string]::IsNullOrWhiteSpace($logFile)) {
        $logFile = $logDefault
    }
    $global:LogFile = $logFile  # So subsequent logging goes to this file

    # RETENTION_DAYS
    $retentionDefault = 30
    $retentionInput = Read-Host "How many days of logs to keep (RETENTION_DAYS) [default: $retentionDefault]"
    if ([string]::IsNullOrWhiteSpace($retentionInput)) {
        $retentionInput = $retentionDefault
    }
    try {
        $retentionDays = [int]$retentionInput
    }
    catch {
        Write-Host "Invalid number. Using default $retentionDefault days." -ForegroundColor Yellow
        $retentionDays = $retentionDefault
    }

    # RCLONE_INSTALL_DIR
    $rcloneInstallDefault = "C:\Program Files\rclone"
    $rcloneInstallDir = Read-Host "Where should rclone be installed if missing? (RCLONE_INSTALL_DIR) [default: $rcloneInstallDefault]"
    if ([string]::IsNullOrWhiteSpace($rcloneInstallDir)) {
        $rcloneInstallDir = $rcloneInstallDefault
    }

    # RCLONE_DOWNLOAD_URL
    $rcloneUrlDefault = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"
    $rcloneDownloadUrl = Read-Host "rclone download URL (RCLONE_DOWNLOAD_URL) [default: $rcloneUrlDefault]"
    if ([string]::IsNullOrWhiteSpace($rcloneDownloadUrl)) {
        $rcloneDownloadUrl = $rcloneUrlDefault
    }

    # -------- rclone performance parameters --------

    Write-Host ""
    Write-Host "rclone performance parameters (press Enter to accept defaults)." -ForegroundColor Yellow

    $transfersDefault = 8
    $transfersInput = Read-Host "Concurrent file transfers (RCLONE_TRANSFERS) [default: $transfersDefault]"
    if ([string]::IsNullOrWhiteSpace($transfersInput)) { $transfersInput = $transfersDefault }
    try {
        $rcloneTransfers = [int]$transfersInput
    }
    catch {
        Write-Host "Invalid number. Using default $transfersDefault." -ForegroundColor Yellow
        $rcloneTransfers = $transfersDefault
    }

    $checkersDefault = 16
    $checkersInput = Read-Host "Concurrent checks (RCLONE_CHECKERS) [default: $checkersDefault]"
    if ([string]::IsNullOrWhiteSpace($checkersInput)) { $checkersInput = $checkersDefault }
    try {
        $rcloneCheckers = [int]$checkersInput
    }
    catch {
        Write-Host "Invalid number. Using default $checkersDefault." -ForegroundColor Yellow
        $rcloneCheckers = $checkersDefault
    }

    $fastListAnswer = Read-Host "Use --fast-list? (RCLONE_FAST_LIST) (Y/N, default Y)"
    if ([string]::IsNullOrWhiteSpace($fastListAnswer) -or $fastListAnswer -match '^[Yy]') {
        $rcloneFastList = "true"
    }
    else {
        $rcloneFastList = "false"
    }

    $logLevelDefault = "INFO"
    $logLevelInput = Read-Host "rclone log level (RCLONE_LOG_LEVEL: DEBUG, INFO, NOTICE, ERROR) [default: $logLevelDefault]"
    if ([string]::IsNullOrWhiteSpace($logLevelInput)) {
        $logLevelInput = $logLevelDefault
    }
    $rcloneLogLevel = $logLevelInput.ToUpper()

    $extraArgs = Read-Host "Any extra rclone arguments (RCLONE_EXTRA_ARGS), e.g. --bwlimit 5M (optional)"

    # -------- Build and write .env --------

    $envVars = [ordered]@{
        "LOCAL_PATH"         = $localPath
        "REMOTE_PATH"        = $remotePath
        "LOG_FILE"           = $logFile
        "RETENTION_DAYS"     = $retentionDays
        "RCLONE_INSTALL_DIR" = $rcloneInstallDir
        "RCLONE_DOWNLOAD_URL"= $rcloneDownloadUrl
        "RCLONE_TRANSFERS"   = $rcloneTransfers
        "RCLONE_CHECKERS"    = $rcloneCheckers
        "RCLONE_FAST_LIST"   = $rcloneFastList
        "RCLONE_LOG_LEVEL"   = $rcloneLogLevel
        "RCLONE_EXTRA_ARGS"  = $extraArgs
    }

    Write-DotEnv -Path $EnvFilePath -EnvVars $envVars

    # -------- Optional: Scheduled Task configuration --------

    Write-Host ""
    $createTaskAnswer = Read-Host "Create or update a Windows Scheduled Task with this configuration? (Y/N, default Y)"
    if ([string]::IsNullOrWhiteSpace($createTaskAnswer) -or $createTaskAnswer -match '^[Yy]') {
        Setup-ScheduledTask -ScriptFullPath $ScriptPath -DefaultTaskName "B2Backup-$($env:COMPUTERNAME)"
    }
    else {
        Write-Host "Skipping scheduled task creation." -ForegroundColor Yellow
        Write-Log "User chose not to create/update scheduled task."
    }

    Write-Host ""
    Write-Host "Interactive setup completed." -ForegroundColor Green
    Write-Log "Interactive setup completed."
}

function Run-Backup {
    # Load .env
    $envVars = Load-DotEnv -Path $EnvFilePath

    # Required config from .env
    $LocalPath      = $envVars["LOCAL_PATH"]
    $RemotePath     = $envVars["REMOTE_PATH"]
    $global:LogFile = $envVars["LOG_FILE"]

    # Optional config with defaults
    $RetentionDays    = 30
    if ($envVars["RETENTION_DAYS"]) {
        try { $RetentionDays = [int]$envVars["RETENTION_DAYS"] } catch { $RetentionDays = 30 }
    }

    $RcloneInstallDir = $envVars["RCLONE_INSTALL_DIR"]
    if (-not $RcloneInstallDir) { $RcloneInstallDir = "C:\Program Files\rclone" }

    $RcloneDownloadUrl = $envVars["RCLONE_DOWNLOAD_URL"]
    if (-not $RcloneDownloadUrl) { $RcloneDownloadUrl = "https://downloads.rclone.org/rclone-current-windows-amd64.zip" }

    # rclone tuning from .env
    $RcloneTransfers = 8
    if ($envVars["RCLONE_TRANSFERS"]) {
        try { $RcloneTransfers = [int]$envVars["RCLONE_TRANSFERS"] } catch { $RcloneTransfers = 8 }
    }

    $RcloneCheckers = 16
    if ($envVars["RCLONE_CHECKERS"]) {
        try { $RcloneCheckers = [int]$envVars["RCLONE_CHECKERS"] } catch { $RcloneCheckers = 16 }
    }

    $RcloneFastList = $true
    if ($envVars["RCLONE_FAST_LIST"]) {
        $val = $envVars["RCLONE_FAST_LIST"].ToString().ToLower()
        if ($val -eq "false" -or $val -eq "0" -or $val -eq "no") {
            $RcloneFastList = $false
        }
    }

    $RcloneLogLevel = $envVars["RCLONE_LOG_LEVEL"]
    if (-not $RcloneLogLevel) { $RcloneLogLevel = "INFO" }

    $RcloneExtraArgsRaw = $envVars["RCLONE_EXTRA_ARGS"]
    $RcloneExtraArgs = @()
    if ($RcloneExtraArgsRaw) {
        # Simple whitespace-split; for more complex quoting, edit RCLONE_EXTRA_ARGS manually in .env
        $RcloneExtraArgs = $RcloneExtraArgsRaw -split '\s+'
    }

    Write-Log "==== Backup Started ===="
    Write-Log "Using LOCAL_PATH='$LocalPath', REMOTE_PATH='$RemotePath', LOG_FILE='$LogFile'."

    # Basic validation
    if (-not $LocalPath -or -not $RemotePath) {
        Write-Log "ERROR: LOCAL_PATH and REMOTE_PATH must be set in .env."
        Write-Host "ERROR: LOCAL_PATH and REMOTE_PATH must be set in .env." -ForegroundColor Red
        Write-Log "==== Backup Failed ===="
        exit 1
    }

    # Ensure prerequisites
    Ensure-Rclone -InstallDir $RcloneInstallDir -DownloadUrl $RcloneDownloadUrl

    # Refresh PATH for this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Validate local path
    if (-not (Test-Path $LocalPath)) {
        Write-Log "ERROR: Local path '$LocalPath' does not exist."
        Write-Host "ERROR: Local path '$LocalPath' does not exist." -ForegroundColor Red
        Write-Log "==== Backup Failed ===="
        exit 1
    }

    # Optional: test remote
    $remoteName = ($RemotePath.Split(":")[0]) + ":"
    Test-RcloneRemote -Remote $remoteName

    # Build rclone sync args
    $rcloneArgs = @(
        "sync",
        $LocalPath,
        $RemotePath,
        "--transfers=$RcloneTransfers",
        "--checkers=$RcloneCheckers",
        "--log-level=$RcloneLogLevel"
    )

    if ($RcloneFastList) {
        $rcloneArgs += "--fast-list"
    }

    if ($RcloneExtraArgs.Count -gt 0) {
        $rcloneArgs += $RcloneExtraArgs
    }

    Write-Log "Executing: rclone $($rcloneArgs -join ' ')"

    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "rclone"
        $processInfo.Arguments = $rcloneArgs -join " "
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError  = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $null   = $process.Start()
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if ($stdOut) { Write-Log $stdOut.Trim() }
        if ($stdErr) { Write-Log "STDERR: $($stdErr.Trim())" }

        if ($process.ExitCode -ne 0) {
            Write-Log "ERROR: rclone sync failed with exit code $($process.ExitCode)."
            Write-Host "Backup FAILED. Check log at '$LogFile'." -ForegroundColor Red
            Write-Log "==== Backup Failed ===="
            exit $process.ExitCode
        }
    }
    catch {
        Write-Log "ERROR: Exception while running rclone. $_"
        Write-Host "Backup FAILED due to an exception. Check log at '$LogFile'." -ForegroundColor Red
        Write-Log "==== Backup Failed ===="
        exit 1
    }

    Write-Log "Backup completed successfully."
    Write-Host "Backup completed successfully." -ForegroundColor Green

    Cleanup-Logs -LogPath $LogFile -RetentionDays $RetentionDays

    Write-Log "==== Backup Completed ===="
}

# -------------------------
# MAIN CONTROL FLOW
# -------------------------

Ensure-Admin

if ($NonInteractive) {
    # This is the mode intended for Task Scheduler: no prompts, just run the backup.
    Run-Backup
}
else {
    # Interactive: either do initial setup or allow user to choose between setup and running.
    if ($Setup -or -not (Test-Path $EnvFilePath)) {
        # First-time or explicit setup
        Run-InteractiveSetup

        # Optional immediate run
        $runNow = Read-Host "Run a backup immediately with this configuration? (Y/N, default Y)"
        if ([string]::IsNullOrWhiteSpace($runNow) -or $runNow -match '^[Yy]') {
            Run-Backup
        }
        else {
            Write-Host "You can run the backup later with: `.\$(Split-Path $ScriptPath -Leaf)` or via the Scheduled Task." -ForegroundColor Yellow
        }
    }
    else {
        # .env exists: offer a simple menu
        Write-Host ""
        Write-Host "Found existing configuration '.env' at '$EnvFilePath'." -ForegroundColor Cyan
        Write-Host "What would you like to do?"
        Write-Host "  1) Run backup now using existing configuration"
        Write-Host "  2) Re-run interactive setup (edit .env and scheduled task)"
        $choice = Read-Host "Enter 1 or 2 [default: 1]"

        if ($choice -eq "2") {
            Run-InteractiveSetup

            $runNow = Read-Host "Run a backup immediately with this new configuration? (Y/N, default Y)"
            if ([string]::IsNullOrWhiteSpace($runNow) -or $runNow -match '^[Yy]') {
                Run-Backup
            }
        }
        else {
            Run-Backup
        }
    }
}
