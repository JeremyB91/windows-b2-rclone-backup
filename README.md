# 🐍 B2Backup.py

Sync a local Windows folder to a Backblaze B2 bucket using the `b2sdk`, with an interactive setup wizard and optional automated scheduling.

---

## 🔍 Overview

`b2_backup_setup.py` is a fully interactive Python script that:

* Uploads files from a local folder to a Backblaze B2 bucket.
* Prompts the user to configure all settings interactively during the first run.
* Saves configuration to a `.env` file for future automatic use.
* Optionally creates a **Windows Scheduled Task** for automated daily backups.
* Allows exclusions (e.g. `.tmp`, `.log`) and supports B2's built-in versioning.

---

## 🎯 Features

* **Interactive Configuration Wizard**
  * Prompts for folder to backup, B2 credentials, scheduling time, and exclusions.
  * Writes a `.env` file and `exclude_patterns.txt` to manage configuration.
  
* **Optional Scheduled Task Setup**
  * Creates a Windows Task that runs the script daily at your chosen time.
  * Uses the saved config for fully automated, non-interactive execution.

* **Versioning Support**
  * Leverages Backblaze B2's native file versioning settings.
  * Keeps the script simple while giving you full control via the B2 web console.

* **File Exclusion Support**
  * Skips uploading files matching extensions listed in `exclude_patterns.txt`.

* **Auto Dependency Installer**
  * Installs all required packages (`b2sdk`, `colorama`, `python-dotenv`) if not already present.

---

## 🧰 Requirements

* Windows (with Python 3.8+ installed).
* A Backblaze B2 account and application key.
* Administrator rights (for setting scheduled tasks).

---

## ⚙️ How to Use

### First-Time Setup

1. Open **Command Prompt** or **PowerShell** as **Administrator**.
2. Navigate to the directory containing `b2_backup_setup.py`.
3. Run the script:

   ```bash
   python b2_backup_setup.py
