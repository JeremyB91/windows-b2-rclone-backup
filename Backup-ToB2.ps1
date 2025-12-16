<#
.SYNOPSIS
    Sync a local folder to a Backblaze B2 bucket using rclone.
    Automatically installs rclone system-wide if not present.
    All configuration comes from a .env file.

.NOTES
    - Run this script as Administrator (required for system-wide install & PATH).
    - .env should live next to this script (or adjust $EnvFilePath).
    - Do NOT commit real secrets in a public repo. Use .env.example there,
      and keep the real .env out of git.
#>

# -------------------------
# BASIC SETUP
# -------------------------

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFilePath = Join-Path $ScriptDir ".env"

# -------------------------
# FUNCTIONS
# -------------------------

function Write-Log {
    param(
        [string]$Message
    )
    if (-not $global:LogFile) {
        # Fallback if LogFile isn't set yet
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

# -------------------------
# MAIN
# -------------------------

Ensure-Admin

# Load .env
$envVars = Load-DotEnv -Path $EnvFilePath

# Required config from .env
$LocalPath        = $envVars["LOCAL_PATH"]
$RemotePath       = $envVars["REMOTE_PATH"]
$global:LogFile   = $envVars["LOG_FILE"]

# Optional config with defaults
$RetentionDays    = [int]($envVars["RETENTION_DAYS"]  | ForEach-Object { if ($_){$_} else {30} })
$RcloneInstallDir = $envVars["RCLONE_INSTALL_DIR"]
if (-not $RcloneInstallDir) { $RcloneInstallDir = "C:\Program Files\rclone" }

$RcloneDownloadUrl = $envVars["RCLONE_DOWNLOAD_URL"]
if (-not $RcloneDownloadUrl) { $RcloneDownloadUrl = "https://downloads.rclone.org/rclone-current-windows-amd64.zip" }

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
    "--transfers=8",
    "--checkers=16",
    "--fast-list",
    "--log-level=INFO"
)

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
