# windows-b2-rclone-backup
Automated Windows backup script that installs **rclone** system-wide (if needed), reads configuration from a `.env` file, and syncs a local folder to a **Backblaze B2** bucket.

Designed for:
- Windows VMs / servers
- Non-interactive / scheduled backups
- Config stored in a simple `.env` file

---

## 🚀 Features

- ✅ Installs **rclone** automatically for all users (`C:\Program Files\rclone`)
- ✅ Adds `rclone` to the **system PATH**
- ✅ Reads all config from a `.env` file
- ✅ Uses `rclone sync` to mirror a local folder to a B2 bucket
- ✅ Simple logging to a file with optional log rotation
- ✅ Works great with **Task Scheduler** for automated backups

---

## 📁 Repository Structure

```text
windows-b2-rclone-backup/
├─ Backup-ToB2.ps1        # Main backup script
├─ .env.example           # Example environment file (no secrets)
├─ README.md              # This guide
└─ .gitignore             # Ignore .env, logs, etc.
