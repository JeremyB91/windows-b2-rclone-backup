# windows-b2-rclone-backup

Automated Windows backup script that installs rclone system-wide (if needed), reads configuration from a `.env` file, and syncs a local folder to a Backblaze B2 bucket.

Designed for:

* Windows VMs / servers
* Non-interactive / scheduled backups
* Config stored in a simple `.env` file

---

## 🚀 Features

* Installs **rclone** automatically for all users (`C:\Program Files\rclone`)
* Adds rclone to the **system PATH**
* Reads all configuration from a `.env` file
* Uses `rclone sync` to mirror a local folder to a B2 bucket
* Simple logging to a file with optional log rotation
* Works well with **Task Scheduler** for automated backups

---

## 📁 Repository Structure

```
windows-b2-rclone-backup/
├─ Backup-ToB2.ps1        # Main backup script
├─ .env.example           # Example environment file (no secrets)
├─ README.md              # This guide
└─ .gitignore             # Ignore .env, logs, etc.
```

---

## ⚙️ Requirements

* Windows (Server or Desktop)
* PowerShell
* Administrator rights (for system-wide install & PATH)
* A Backblaze B2 account & bucket
* An rclone remote configured for B2

> **Security Note:** Never commit your `.env` file with real secrets to a public repository. Only commit `.env.example`.

---

## 🔧 Setup

### 1. Clone the repository

```
git clone https://github.com/<your-username>/windows-b2-rclone-backup.git
cd windows-b2-rclone-backup
```

### 2. Create your `.env` file

Copy the example:

```
Copy-Item .env.example .env
```

Then edit `.env` with your real values:

```
LOCAL_PATH=C:\DataToBackup
REMOTE_PATH=b2remote:my-bucket/DataBackup
LOG_FILE=C:\Logs\B2Backup.log
RETENTION_DAYS=30
RCLONE_INSTALL_DIR=C:\Program Files\rclone
RCLONE_DOWNLOAD_URL=https://downloads.rclone.org/rclone-current-windows-amd64.zip
```

Make sure all paths are valid for your system.

### 3. Configure rclone

```
rclone config
```

Create a remote (e.g., `b2remote`) pointing to your Backblaze B2 credentials. Use that remote name in `REMOTE_PATH`.

---

## ▶️ Running the Backup Script

> Run PowerShell **as Administrator** the first time.

```
powershell.exe -ExecutionPolicy Bypass -File .\Backup-ToB2.ps1
```

On first run, the script will:

* Load `.env`
* Verify administrative privileges
* Install rclone if not present
* Add rclone to PATH
* Validate local/remote paths
* Run the sync operation
* Log output to `LOG_FILE`

---

## ⏰ Scheduling Automatic Backups (Task Scheduler)

1. Open **Task Scheduler**
2. Select **Create Task**
3. General:

   * Name: `Backblaze B2 Backup`
   * Run whether user is logged on or not
   * Run with highest privileges
4. Triggers → New → choose your schedule
5. Actions → New:

   * Program/script:

     ```
     powershell.exe
     ```
   * Arguments:

     ```
     -ExecutionPolicy Bypass -File "C:\path\to\windows-b2-rclone-backup\Backup-ToB2.ps1"
     ```
6. Save

Your backup now runs automatically.

---

## 🔐 Security Best Practices

* Never commit `.env` containing real secrets.
* Restrict access to logs and the VM.
* Consider encrypted rclone remotes if storing sensitive data.

---

## 🧪 Testing Changes

You can safely test by adding `--dry-run` to the rclone arguments inside the script:

```
rclone sync ... --dry-run
```

---

## 🐛 Issues & Contributions

Feel free to open issues or submit pull requests with improvements.

Happy backing up! 💾☁️
