# 🐍 Backup to Backblaze B2 (Python Script)

A **simple, interactive Python backup script** that uploads a local folder to a **Backblaze B2 bucket** using the official `b2sdk`. The script handles first‑run configuration, credential storage via `.env`, optional file‑type exclusions, and automatic dependency installation.

This README reflects the **current behavior of the script exactly** — no scheduling, no Task Scheduler integration, and no rclone usage.

---

## 📦 What This Script Does

`backup_to_b2.py`:

* Prompts for Backblaze B2 credentials and backup settings on first run
* Stores configuration in a local `.env` file
* Uploads **all files** from a specified folder to a B2 bucket
* Preserves folder structure inside the bucket
* Optionally excludes files by extension (e.g. `.log`, `.tmp`)
* Relies on **Backblaze B2 bucket versioning** for retention/history
* Automatically installs required Python packages if missing

---

## 🚀 Features

* ✅ **Interactive setup wizard** (first run only)
* 🔐 **Secure credential entry** (application key hidden at prompt)
* 🗂️ **Optional file extension exclusions**
* ☁️ **Native Backblaze B2 uploads via `b2sdk`**
* 📁 **Recursive directory upload** with structure preserved
* 🧰 **Automatic dependency installation** (`b2sdk`, `colorama`, `python-dotenv`)

---

## ❌ What This Script Does *Not* Do

To avoid confusion, this script **does not**:

* Create Windows Scheduled Tasks
* Run on a schedule automatically
* Perform incremental or delta comparisons
* Delete remote files
* Use rclone
* Encrypt files locally

Scheduling should be handled externally (Task Scheduler, cron, etc.) if desired.

---

## 🧰 Requirements

* **Windows, macOS, or Linux**
* **Python 3.8+**
* A **Backblaze B2 account** with:

  * A bucket
  * Application Key ID
  * Application Key

> 💡 Use a **limited‑scope application key** whenever possible.

---

## ⚙️ Getting Started

### 1️⃣ Download the Script

Place `backup_to_b2.py` in an empty directory where you want the config files to live.

### 2️⃣ Run the Script

```bash
python backup_to_b2.py
```

On first run, you’ll be prompted for:

* 🪣 **B2 Bucket Name**
* 🔑 **B2 Application Key ID**
* 🔒 **B2 Application Key** (hidden input)
* 📁 **Full path to the folder to back up**
* 🗂️ Whether B2 should manage file versions (yes/no)
* 🚫 Optional file extensions to exclude (comma‑separated)

---

## 📝 Configuration Files

### `.env`

Automatically created after setup and reused on future runs.

Example:

```env
B2_BUCKET=my-backup-bucket
B2_KEY_ID=abc123
B2_APP_KEY=xxxxxxxxxxxxxxxx
BACKUP_PATH=C:\ImportantFiles
VERSIONING=yes
```

> ⚠️ **Never commit `.env` to source control**

---

### `exclude_patterns.txt` (optional)

Created only if exclusions are specified.

Example:

```text
.log
.tmp
.bak
```

* One extension per line
* Case‑insensitive
* Applied during upload traversal

---

## 🔁 Running Subsequent Backups

After initial setup, simply run:

```bash
python backup_to_b2.py
```

The script will:

1. Load `.env`
2. Authenticate to Backblaze B2
3. Upload all files recursively
4. Skip excluded file types

---

## ☁️ File Versioning & Retention

If enabled during setup:

* **Backblaze B2 handles versioning**, not the script
* Older versions are retained according to **bucket lifecycle rules**
* The script always uploads files as‑is (no local diffing)

---

## 🔐 Security Notes

* Application keys are stored **locally only** in `.env`
* The script does not transmit credentials anywhere except Backblaze
* Protect the directory containing `.env`
* Use OS‑level disk encryption on shared systems

---

## 🔧 Reconfiguring the Script

To re‑run the setup wizard:

```bash
del .env
# or
rm .env

python backup_to_b2.py
```

You may also edit `.env` or `exclude_patterns.txt` manually.

---

## 📂 Directory Layout

```text
.
├── backup_to_b2.py          # Main script
├── .env                    # Auto-generated configuration
├── exclude_patterns.txt    # Optional exclusions
└── README.md               # Documentation
```

---

## 🙌 Notes

This script is intentionally **simple and transparent**:

* No background services
* No hidden scheduling
* No destructive operations

It is designed to be easy to audit, modify, and integrate into your own automation workflows.

---

## 📜 License

MIT License — free to use, modify, and distribute.
