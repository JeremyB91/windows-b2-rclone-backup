# B2Backup.ps1

Sync a local Windows folder to a Backblaze B2 bucket using `rclone`, with an interactive setup wizard and an optional scheduled task.

---

## Overview

`B2Backup.ps1` is a PowerShell script that:

* Syncs a local folder to a Backblaze B2 bucket using `rclone sync`.
* Runs in **interactive** mode to collect settings, write a `.env` file, and optionally create a **Windows Scheduled Task**.
* Runs in **non-interactive** mode (for Task Scheduler) by loading configuration from the `.env` file.
* Ensures `rclone` is installed and available on the system `PATH`.
* Logs all activity to a configurable log file and performs simple log rotation.

---

## Features

* Interactive configuration wizard

  * Prompts for local and remote paths, logging, and rclone tuning.
  * Writes all configuration to a `.env` file next to the script.
* Optional scheduled task setup

  * Daily, weekly, or at-logon triggers.
  * Runs the script in non-interactive mode.
* Automatic rclone installation (if missing)

  * Downloads and installs `rclone` to a configurable directory.
  * Adds that directory to the system `PATH`.
* Non-interactive backup mode

  * Intended for Task Scheduler to run without prompts.
* Logging and log rotation

  * Logs to a file (default `C:\Logs\B2Backup.log`).
  * Old logs are rotated based on retention days.

---

## Requirements

* Windows (with PowerShell 5.1 or later).
* Administrator privileges (required for):

  * Installing `rclone` to `C:\Program Files`.
  * Updating the system `PATH`.
  * Creating or updating a Windows Scheduled Task.
* A Backblaze B2 account.
* A configured `rclone` remote pointing to your B2 bucket (e.g., `b2:my-remote-bucket`).

> The script can attempt to validate your rclone remote, but you are responsible for creating and testing it via `rclone config`.

---

## Script parameters

```powershell
param(
    [switch]$NonInteractive,
    [switch]$Setup
)
```

* `-Setup`

  * Forces the interactive setup wizard, even if a `.env` file already exists.
* `-NonInteractive`

  * Skips all prompts and runs a backup using the existing `.env` file.
  * This is the mode used by the Scheduled Task.

If you run the script with **no parameters**, it will:

* Run the interactive setup if no `.env` file exists.
* Otherwise, prompt you to either run a backup immediately or re-run the interactive setup.

---

## Getting started

1. Open **PowerShell as Administrator**.

2. Navigate to the directory containing `B2Backup.ps1`.

3. Run the interactive setup:

   ```powershell
   .\B2Backup.ps1 -Setup
   ```

4. Follow the prompts to:

   * Choose the local folder to back up.
   * Specify the rclone remote path (e.g. `b2:my-remote-bucket/server1`).
   * Configure logging and retention.
   * Configure rclone performance parameters.
   * Optionally create or update a Scheduled Task.

5. (Optional) At the end of setup you can choose to run a backup immediately.

Once the wizard finishes, a `.env` file will be created in the same folder as the script.

---

## Running backups

### Interactive one-off backup

If a `.env` file already exists, you can trigger a manual backup from an elevated PowerShell prompt:

```powershell
.\B2Backup.ps1
```

You will be offered a simple menu to:

1. Run backup now using existing configuration.
2. Re-run the interactive setup.

### Non-interactive backup (Task Scheduler / automation)

To run non-interactively (no prompts), use:

```powershell
.\B2Backup.ps1 -NonInteractive
```

This mode:

* Loads configuration from `.env`.
* Ensures `rclone` is installed and in `PATH`.
* Runs `rclone sync`.
* Logs output to the configured log file.

> This is the mode that the Scheduled Task created by the wizard uses.

---

## Environment file (`.env`)

The script reads configuration from a `.env` file living alongside `B2Backup.ps1`.

Example keys written by the wizard:

| Key                   | Description                                               | Example                            |
| --------------------- | --------------------------------------------------------- | ---------------------------------- |
| `LOCAL_PATH`          | Local folder to back up                                   | `C:\Data`                          |
| `REMOTE_PATH`         | rclone remote + path                                      | `b2:my-remote-bucket/server1`      |
| `LOG_FILE`            | Log file path                                             | `C:\Logs\B2Backup.log`             |
| `RETENTION_DAYS`      | Days to keep log file before rotation                     | `30`                               |
| `RCLONE_INSTALL_DIR`  | Where to install `rclone` if missing                      | `C:\Program Files\rclone`          |
| `RCLONE_DOWNLOAD_URL` | rclone zip download URL                                   | `https://downloads.rclone.org/...` |
| `RCLONE_TRANSFERS`    | Concurrent file transfers                                 | `8`                                |
| `RCLONE_CHECKERS`     | Concurrent checks                                         | `16`                               |
| `RCLONE_FAST_LIST`    | Whether to use `--fast-list` (`true` or `false`)          | `true`                             |
| `RCLONE_LOG_LEVEL`    | rclone log level (`DEBUG`, `INFO`, `NOTICE`, `ERROR`)     | `INFO`                             |
| `RCLONE_EXTRA_ARGS`   | Extra arguments appended to the rclone command (optional) | `--bwlimit 5M`                     |

The interactive wizard will build and update this file for you, but you can also edit it manually.

> The script also loads each key into the process environment so that child processes (like `rclone`) can see them.

---

## What the script does under the hood

At a high level:

1. **Requires elevation**

   * `Ensure-Admin` checks that the script is running as Administrator and exits with an error if not.

2. **Interactive setup (when applicable)**

   * Prompts for all required configuration.
   * Writes `.env` using `Write-DotEnv`.
   * Optionally calls `Setup-ScheduledTask` to create or update a Windows Scheduled Task.

3. **Scheduled task creation (optional)**

   * Uses `New-ScheduledTaskTrigger` to configure one of:

     * Daily at a specified time.
     * Weekly on a specified day and time.
     * At user logon.
   * Runs PowerShell with:

     * `-NoProfile -ExecutionPolicy Bypass -File "B2Backup.ps1" -NonInteractive`
   * Uses credentials you provide to run as the appropriate user.

4. **Backup execution**

   * Loads configuration from `.env` (`Load-DotEnv`).
   * Ensures `rclone` is installed (`Ensure-Rclone` / `Install-Rclone`).
   * Optionally validates the rclone remote (`Test-RcloneRemote`).
   * Builds `rclone sync` arguments from configuration.
   * Starts `rclone` as a background process, capturing stdout and stderr.
   * Logs success or failure.
   * Optionally rotates logs (`Cleanup-Logs`).

5. **Logging**

   * All log messages go through `Write-Log`.
   * If the log directory does not exist, it is created automatically.

---

## Logging and log rotation

* Logs are written to the file at `LOG_FILE`.
* Each run writes a header such as `==== Backup Started ====`, followed by:

  * Configuration summary (paths, log file location).
  * `rclone` output (stdout/stderr).
  * Final success/failure messages.
* `Cleanup-Logs` optionally deletes the log file if it is older than `RETENTION_DAYS`, allowing it to be recreated fresh on the next run.

> If you need more advanced log rotation, you can disable this behavior and use an external log management tool.

---

## Security considerations

* **Do not commit real secrets** (API keys, tokens, etc.) to a public repository.
* The `.env` file typically contains paths and non-secret configuration.
* `rclone` stores credentials in its own config file (usually in the user profile) and is not managed by this script.
* The Scheduled Task will store the run-as credentials within Windows. Use a dedicated service account if appropriate.

---

## Troubleshooting

* "This script must be run as Administrator"

  * Make sure you opened PowerShell with **Run as administrator**.

* "ERROR: .env file not found"

  * Run the interactive setup: `.\B2Backup.ps1 -Setup`.

* rclone remote warnings

  * The script may log that the remote is not configured correctly.
  * Run `rclone config` manually and verify that `rclone ls <your-remote>:` works.

* rclone not found or not installing

  * Check that `RCLONE_DOWNLOAD_URL` is reachable.
  * Verify that `RCLONE_INSTALL_DIR` is writeable by an Administrator.

* Backup fails immediately

  * Check that `LOCAL_PATH` exists and is accessible.
  * Check that `REMOTE_PATH` points to a valid rclone remote and path.
  * Review the log file at `LOG_FILE` for detailed error information.

---

## Example usage

### Initial setup and schedule a daily backup

```powershell
# Run as Administrator
.\B2Backup.ps1 -Setup
```

Follow the prompts, choose a local folder and remote path, and configure a daily schedule. At the end, optionally run the backup once to make sure everything works.

### Non-interactive run from Task Scheduler

Configure a Scheduled Task action similar to:

```text
Program/script: powershell.exe
Arguments: -NoProfile -ExecutionPolicy Bypass -File "C:\Path\To\B2Backup.ps1" -NonInteractive
Start in: C:\Path\To
```

The wizard can create this task for you automatically.

---

## Notes

* This script is designed for Windows environments.
* You can adapt it to your own environment or use it as a starting point for other rclone-based backup workflows.
* Contributions and improvements are welcome.
