# B2Backup.py

Backup a local Windows folder to a Backblaze B2 bucket using Python — with interactive setup, `.env` configuration, file exclusion, and automated scheduling via Task Scheduler.

---

## Overview

`b2_backup.py` is a Python script that:

* Uploads a local folder to a Backblaze B2 bucket using the official `b2sdk`.
* Runs in **interactive mode** to collect all configuration values and optionally schedule a **Windows Task Scheduler job**.
* Stores user inputs in a `.env` file and uses it for all subsequent automated runs.
* Supports **exclusion patterns**, **B2-native versioning**, and **configurable scheduling**.
* Automatically installs all Python dependencies and handles B2 authentication.

---

## Features

* **Interactive Configuration Wizard**
  * Prompts for:
    * Folder to back up
    * B2 bucket name
    * B2 application key and key ID
    * Schedule time (e.g. `03:00`)
    * File extensions to exclude (e.g. `.tmp,.log`)
    * Whether to let B2 manage file versioning

* **Environment File Support**
  * Saves all settings in a `.env` file
  * Can be re-run to update the config
  * Also loads `exclude_patterns.txt` for ignored file types

* **B2 Native File Versioning**
  * Uses B2’s built-in file versioning and lifecycle rules
  * Uploads without deleting older versions (unless configured in the bucket)

* **Optional Scheduled Task Creation**
  * Automates daily backups using `schtasks`
  * Uses your chosen backup time
  * Task is created only once and uses the `.env` file thereafter

---

## Requirements

* Windows 10/11
* Python 3.8+ with `pip`
* Administrator privileges (for Task Scheduler setup)
* Backblaze B2 account and application key

---

## Script Parameters

No parameters are required — everything is handled via prompts on first run.

To reconfigure, just delete the `.env` file and rerun:

```bash
python b2_backup.py
```

---

## Getting Started

1. Open **Command Prompt or PowerShell as Administrator**
2. Navigate to the script folder
3. Run the setup wizard:

```bash
python b2_backup.py
```

4. Follow the interactive prompts:
   * Select a folder to back up
   * Enter your B2 credentials
   * Choose your daily backup time
   * Add any file types to exclude
   * Choose whether to enable B2-managed versioning

At the end of setup:
* `.env` and `exclude_patterns.txt` are saved
* A Windows Scheduled Task will be created to run this daily

---

## Running Backups

### Manual one-off backup

If `.env` exists, just run:

```bash
python b2_backup.py
```

It will:
* Authenticate to B2
* Read the `.env` and exclusion file
* Upload all eligible files to the bucket

### Automated backup (Task Scheduler)

The setup process schedules the script like this:

```text
schtasks /Create /SC DAILY /TN BackupToBackblazeB2 /TR "python b2_backup.py" /ST 03:00 /F
```

This will trigger the backup daily using the saved configuration.

---

## Environment File (`.env`)

The script stores and reads configuration from a `.env` file in the same directory.

| Key              | Description                                  |
|------------------|----------------------------------------------|
| `B2_BUCKET`      | Backblaze B2 bucket name                     |
| `B2_KEY_ID`      | B2 application key ID                        |
| `B2_APP_KEY`     | B2 application key                           |
| `BACKUP_PATH`    | Full path to local backup folder             |
| `BACKUP_SCHEDULE`| Daily backup time (e.g. `03:00`)             |
| `VERSIONING`     | Whether to allow B2 to version files (`yes`/`no`) |

---

## File Exclusion

If you choose to exclude files during setup, a file called `exclude_patterns.txt` will be created.

Each line should contain one extension (with the dot), e.g.:

```
.tmp
.log
.mp4
```

These files will be skipped during every backup run.

---

## Logging

By default, logs are printed to the console. In future versions, logging to file will be supported.

---

## Security Considerations

* The `.env` file stores your B2 credentials in plaintext — secure it appropriately.
* Scheduled Tasks will run under your Windows user account.
* Use Windows NTFS permissions to restrict access to this script and its configuration files.

---

## Troubleshooting

* **“Permission Denied” or “Access Denied”**
  * Ensure you run the script with Administrator privileges when scheduling

* **“No module named b2sdk”**
  * The script installs all dependencies automatically — ensure you’re using Python 3 and have `pip` installed

* **“.env file not found”**
  * Run the script again to reconfigure

* **Backup not running via Task Scheduler**
  * Open Task Scheduler > Find `BackupToBackblazeB2` > Review history
  * Ensure `Start In` directory is set to the folder containing `b2_backup.py`

---

## Roadmap

* [ ] Support file compression before upload
* [ ] Optionally encrypt files before sending to B2
* [ ] Add email alerts on success/failure
* [ ] Add logging to file

---

## License

MIT License — free to use, improve, and distribute.

---

## Author

Built with ❤️ by Python Copilot (v2)
