# 🐍 Backup to Backblaze B2 (Python Script)

A **simple, interactive Python backup script** for uploading a local folder to **Backblaze B2**. The script walks you through configuration on first run, stores settings in a `.env` file, and reuses them for future backups.

This version is **pure Python** (no rclone) and uses the official **`b2sdk`** library.

---

## 📦 What This Script Does

`backup_to_b2.py`:

* Prompts you for required configuration on first run
* Saves configuration securely to a local `.env` file
* Uploads **all files recursively** from a chosen folder to a B2 bucket
* Preserves directory structure in B2
* Optionally excludes file extensions (e.g. `.log`, `.tmp`)
* Lets **Backblaze B2 handle file versioning and retention**
* Automatically installs required Python dependencies if missing

This script is designed to be:

* ✔ Easy to run manually
* ✔ Safe to automate (Task Scheduler, cron, etc.)
* ✔ Simple and auditable

---

## 🧰 Requirements

* **Windows, Linux, or macOS**
* **Python 3.8+** available in PATH
* A **Backblaze B2 account** with:

  * Bucket name
  * Application Key ID
  * Application Key

> 🔒 Credentials are stored locally in `.env`. Never commit this file to GitHub.

---

## 🚀 Getting Started

### 1. Download or clone the project

```bash
git clone <your-repo-url>
cd <repo-folder>
```

Or download `backup_to_b2.py` directly.

---

### 2. Run the script

```bash
python backup_to_b2.py
```

On first run, you will be prompted for:

* 🪣 **B2 Bucket Name**
* 🔑 **Application Key ID**
* 🔒 **Application Key** (hidden input)
* 📁 **Full path to the folder you want to back up**
* 🗂️ Whether B2 should manage file versions
* 🚫 Optional file extensions to exclude (comma‑separated)

Once completed, the configuration is saved and reused automatically.

---

## 📝 Configuration Files

### `.env`

Created automatically on first run.

Example:

```env
B2_BUCKET=my-backup-bucket
B2_KEY_ID=your-key-id
B2_APP_KEY=your-app-key
BACKUP_PATH=C:\\ImportantFiles
VERSIONING=yes
```

If you want to reconfigure everything, simply delete `.env` and rerun the script.

---

### `exclude_patterns.txt`

Optional file created during setup if exclusions are defined.

Example:

```text
.log
.tmp
.bak
```

Any file matching these extensions will be skipped.

---

## ☁️ Backblaze B2 Behavior

* Files are uploaded using **relative paths**, preserving folder structure
* Existing files are overwritten as **new versions** (if versioning is enabled)
* Retention and lifecycle rules are controlled **entirely in the B2 console**

This script intentionally does **not** delete remote files.

---

## 🔄 Running Future Backups

After the first setup:

```bash
python backup_to_b2.py
```

No prompts — it just runs.

This makes the script safe for:

* Windows Task Scheduler
* cron jobs
* Manual execution
* Automation tools

---

## 🔐 Security Notes

* Never commit `.env` or `exclude_patterns.txt`
* Use **restricted‑scope B2 application keys** when possible
* Protect the machine where credentials are stored

---

## 📂 Project Layout

```text
.
├── backup_to_b2.py          # Main script
├── .env                    # Auto‑generated configuration (DO NOT COMMIT)
├── exclude_patterns.txt    # Optional exclusion list
└── README.md               # This file
```

---

## ❓ Troubleshooting

**Dependencies fail to install**

* Ensure Python is installed and `pip` works
* Try running:

  ```bash
  python -m pip install --upgrade pip
  ```

**Permission errors**

* Verify the backup path exists and is readable
* Verify the B2 key has write access to the bucket

---

## 📜 License

MIT License — free to use, modify, and distribute.

---

## 🙌 Notes

This script intentionally prioritizes:

* Simplicity
* Transparency
* Native SDK usage

No background services, no magic, no lock‑in.
