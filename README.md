# 🐍 Backup to Backblaze B2 (Python Edition)

Backup your local Windows folders to a **Backblaze B2 bucket** with an **interactive Python wizard**, automatic `.env` configuration, and optional **Scheduled Task setup**.

---

## 📦 Overview

`backup_to_b2.py` is a fully interactive Python script that:

* Prompts the user for configuration on the first run.
* Uploads all files from a specified local folder to a B2 bucket using `b2sdk`.
* Writes a `.env` file to store configuration for future runs.
* Lets **Backblaze B2 handle file versioning and retention**.
* Optionally creates a **Windows Scheduled Task** to automate daily backups.
* Supports file exclusion (e.g., `.log`, `.tmp`).
* Automatically installs required Python dependencies on first run.

---

## 🚀 Features

* ✅ **Interactive setup wizard**
  * Prompts for:
    * Local backup folder
    * B2 bucket name
    * Application key and key ID
    * Backup schedule (e.g., daily at 03:00)
    * Optional file extension exclusions
    * Optional use of B2's versioning

* 🛠️ **Configuration file (`.env`)**
  * Automatically generated and reused
  * Easy to update via re-running the script

* 🗓️ **Windows Task Scheduler integration**
  * Automatically creates a scheduled task to run the script daily

* ☁️ **Backblaze B2 versioning supported**
  * New file versions are uploaded; old versions retained per bucket lifecycle

* ❌ **Exclusion support**
  * You can specify file types to exclude during setup

---

## 🧰 Requirements

* Windows (with Python 3.8+ installed)
* A Backblaze B2 account and:
  * B2 Bucket
  * Application Key ID
  * Application Key

> 🔒 All credentials are saved in a local `.env` file — never committed to source control!

---

## ⚙️ Getting Started

### 1. Clone or download this repository

```bash
git clone https://github.com/yourname/yourrepo.git
cd yourrepo
```

### 2. Run the script

```bash
python backup_to_b2.py
```

On first run, you will be prompted for:

* Folder to back up
* Bucket name
* Application Key ID and secret
* Daily backup time (e.g., `03:00`)
* Optionally: file types to exclude (e.g., `.log,.tmp`)

Your configuration will be saved to `.env`.

---

## 📝 Environment file (`.env`)

Example:

```env
B2_BUCKET=my-backup-bucket
B2_KEY_ID=your-key-id
B2_APP_KEY=your-app-key
BACKUP_PATH=C:\My\ImportantFiles
BACKUP_SCHEDULE=03:00
VERSIONING=yes
```

> File exclusion patterns are saved to `exclude_patterns.txt` (if configured).

---

## 🧠 How It Works

1. If `.env` is missing, runs setup wizard
2. Authenticates with B2 via `b2sdk`
3. Uploads all files from the specified folder to the bucket
4. Skips any file extensions found in `exclude_patterns.txt`
5. Creates a Windows Scheduled Task to run itself daily (at the configured time)

---

## 💻 Task Scheduler Example

The script creates a task similar to:

```text
Task Name: BackupToBackblazeB2
Trigger: Daily at 03:00
Action: python.exe C:\Path\To\backup_to_b2.py
```

> You can adjust the schedule by editing the Scheduled Task directly in Windows.

---

## ❓ FAQ

**Can I run this manually after setup?**

> Absolutely — just run `python backup_to_b2.py`.

**How do I change the folder or bucket?**

> Delete or edit `.env`, then re-run the script.

**Does it keep old versions?**

> Yes! Backblaze B2 handles versioning and retention based on your bucket settings.

---

## 🔐 Security Tips

* Never share or commit your `.env` file!
* Use limited-scope keys when creating your B2 Application Key.
* Use Windows encryption or file protection if you're storing credentials on shared machines.

---

## 🔄 Updating Configuration

To reconfigure:

```bash
del .env
python backup_to_b2.py
```

Or simply edit the file manually.

---

## 📂 Repository Layout

```text
.
├── backup_to_b2.py           # Main script
├── .env                      # Configuration file (auto-generated)
├── exclude_patterns.txt      # Optional file extension filters
└── README.md                 # You're reading it!
```

---

## 🙌 Credits & Contributions

Developed by 🤖 Python Copilot. Suggestions & PRs are welcome!

---

## 📜 License

MIT — free to use, fork, adapt.
