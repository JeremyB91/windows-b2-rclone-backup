# 🐍 Backup to Backblaze B2 (Python)

A **simple, self‑contained Python backup script** that uploads a local folder to a **Backblaze B2 bucket** using the official `b2sdk`.

The script is designed to be:

* Interactive on first run
* Repeatable on subsequent runs
* Transparent (no background services or schedulers)

This README is written to **match the current code exactly**.

---

## 📦 What the Script Does

`backup_to_b2.py` will:

* Prompt for Backblaze B2 credentials and settings on first run
* Store configuration in a local `.env` file
* Recursively upload all files from a specified folder
* Preserve directory structure in the B2 bucket
* Optionally exclude files by extension
* Generate timestamped log files per run
* Optionally send a **Discord webhook summary** (with log attachment if small enough)
* Automatically install required Python dependencies if missing

---

## 🚀 Features

* ✅ Interactive setup wizard (first run only)
* 🔐 Secure credential input (application key hidden)
* 🗂️ Optional file‑extension exclusions
* ☁️ Native uploads via `b2sdk`
* 📁 Recursive directory traversal
* 📝 Timestamped log files per backup run
* 🔔 Optional Discord completion summary
* 🧰 Automatic dependency installation

---

## ❌ What This Script Does *Not* Do

To avoid confusion, this script **does not**:

* Schedule itself (no cron / Task Scheduler)
* Perform incremental or delta comparisons
* Delete or prune remote files
* Encrypt files locally
* Use rclone
* Manage retention beyond B2 bucket rules

Any scheduling or automation should be handled externally.

---

## 🧰 Requirements

* **Python 3.8+**
* Windows, macOS, or Linux
* A **Backblaze B2 account** with:

  * A bucket
  * Application Key ID
  * Application Key

> 💡 Use a **restricted‑scope application key** when possible.

---

## ⚙️ Getting Started

### 1️⃣ Place the Script

Put `backup_to_b2.py` in a directory where you want configuration and logs to live.

### 2️⃣ Run the Script

```bash
python backup_to_b2.py
```

On first run, you will be prompted for:

* 🪣 **B2 Bucket Name**
* 🔑 **B2 Application Key ID**
* 🔒 **B2 Application Key** (hidden input)
* 📁 **Full path to folder to back up**
* 🗂️ Whether Backblaze should manage versions (`yes` / `no`)
* 🚫 Optional file extensions to exclude (comma‑separated)
* 🔔 Optional Discord webhook URL

The script then writes configuration files automatically.

---

## 📝 Configuration Files

### `.env`

Created automatically on first run and reused on subsequent runs.

Example:

```env
B2_BUCKET=my-backup-bucket
B2_KEY_ID=abc123
B2_APP_KEY=xxxxxxxxxxxxxxxx
BACKUP_PATH=C:\ImportantFiles
VERSIONING=yes
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

> ⚠️ **Do not commit `.env` to source control**

---

### `exclude_patterns.txt` (optional)

Created only if exclusions are specified during setup.

Example:

```text
.log
.tmp
.bak
```

* One extension per line
* Case‑insensitive
* Evaluated for every file during traversal

---

## 📁 Logs

Each run creates a timestamped log file:

```text
logs/backup_YYYY-MM-DD_HH-MM-SS.log
```

Logs include:

* Uploaded files
* Skipped (excluded) files
* Failed uploads and error details
* Summary statistics

If a Discord webhook is configured, the log file will be attached **if under ~7.5 MB**.

---

## 🔁 Running Subsequent Backups

After initial setup, simply run:

```bash
python backup_to_b2.py
```

The script will:

1. Load `.env`
2. Authenticate with Backblaze B2
3. Traverse the backup directory
4. Upload files
5. Write logs
6. Send a Discord summary (if configured)

---

## ☁️ File Versioning & Retention

If versioning is enabled during setup:

* Versioning is handled **entirely by Backblaze B2**
* The script always uploads files as‑is
* Retention is controlled by **bucket lifecycle rules**

The script itself does not manage or prune versions.

---

## 🔐 Security Notes

* Credentials are stored locally in `.env`
* Application keys are never printed to the console
* Credentials are only sent to Backblaze APIs
* Protect the directory containing `.env`
* Use disk encryption on shared systems

---

## 🔧 Reconfiguring

To rerun the setup wizard:

```bash
rm .env
python backup_to_b2.py
```

You may also edit `.env` or `exclude_patterns.txt` manually.

---

## 📂 Directory Layout

```text
.
├── backup_to_b2.py
├── .env
├── exclude_patterns.txt
├── logs/
│   └── backup_YYYY-MM-DD_HH-MM-SS.log
└── README.md
```

---

## 🙌 Design Philosophy

This script is intentionally:

* Simple
* Auditable
* Non‑destructive

It is well suited for manual runs, scheduled execution by external tools, or integration into larger automation workflows.

---

## 📜 License

MIT License — free to use, modify, and distribute.
