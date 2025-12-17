import os
import site
import subprocess
import sys
from pathlib import Path
from getpass import getpass
from datetime import datetime

# -------------------------------------------------
# Dependency bootstrap
# -------------------------------------------------
def install_prerequisites():
    try:
        import b2sdk.v2
        from colorama import init, Fore
        import dotenv
    except ImportError:
        subprocess.check_call([
            sys.executable, "-m", "pip", "install",
            "--user", "b2sdk", "colorama", "python-dotenv"
        ])
        site.main()
        user_site = site.getusersitepackages()
        if user_site not in sys.path:
            sys.path.append(user_site)
        import b2sdk.v2
        from colorama import init, Fore
        import dotenv
    init(autoreset=True)

install_prerequisites()

from colorama import Fore
from b2sdk.v2 import InMemoryAccountInfo, B2Api, UploadSourceLocalFile
from dotenv import load_dotenv, set_key

ENV_PATH = Path(".env")
EXCLUDE_PATH = Path("exclude_patterns.txt")
LOG_PATH = Path("scheduler_log.txt")

# -------------------------------------------------
# Logging
# -------------------------------------------------
def log(msg: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(f"[{timestamp}] {msg}\n")

# -------------------------------------------------
# Config setup
# -------------------------------------------------
def prompt_and_save_env():
    print(Fore.CYAN + "\n=== 🔧 Backup Configuration Setup ===")
    bucket_name = input(Fore.GREEN + "🪣 B2 Bucket Name: ").strip()
    key_id = input(Fore.GREEN + "🔑 B2 Application Key ID: ").strip()
    app_key = getpass(Fore.GREEN + "🔒 B2 Application Key (hidden): ").strip()
    local_folder = input(Fore.GREEN + "📁 Full path to folder to backup: ").strip()

    print(Fore.CYAN + "\n📅 Schedule Options:")
    print("1. Daily")
    print("2. Weekly")
    print("3. Monthly")
    print("4. One-Time")
    print("5. Do not schedule")

    schedule_choice = input(Fore.GREEN + "Select [1-5]: ").strip()
    schedule_map = {
        "1": "DAILY",
        "2": "WEEKLY",
        "3": "MONTHLY",
        "4": "ONCE",
        "5": "NONE"
    }

    schedule_type = schedule_map.get(schedule_choice, "DAILY")
    time_val = days = dates = ""

    if schedule_type != "NONE":
        time_val = input(Fore.GREEN + "⏰ Time (HH:MM): ").strip()

        if schedule_type == "WEEKLY":
            days = input(Fore.GREEN + "🗓️ Days (MON,TUE,...): ").strip().upper()
        elif schedule_type == "MONTHLY":
            dates = input(Fore.GREEN + "📅 Dates (1,15,28): ").strip()

    versioning = input(Fore.GREEN + "🗂️ Let B2 manage versions? [Y/n]: ").strip().lower()
    versioning = "yes" if versioning != "n" else "no"

    with open(ENV_PATH, "w") as f:
        f.write("")

    set_key(ENV_PATH, "B2_BUCKET", bucket_name)
    set_key(ENV_PATH, "B2_KEY_ID", key_id)
    set_key(ENV_PATH, "B2_APP_KEY", app_key)
    set_key(ENV_PATH, "BACKUP_PATH", local_folder)
    set_key(ENV_PATH, "VERSIONING", versioning)
    set_key(ENV_PATH, "SCHEDULE_TYPE", schedule_type)
    set_key(ENV_PATH, "SCHEDULE_TIME", time_val)
    set_key(ENV_PATH, "SCHEDULE_DAYS", days)
    set_key(ENV_PATH, "SCHEDULE_DATES", dates)

    print(Fore.YELLOW + "\n✅ Configuration saved to .env")

def load_config():
    if not ENV_PATH.exists():
        prompt_and_save_env()
    load_dotenv(dotenv_path=ENV_PATH)

    return {
        "bucket": os.getenv("B2_BUCKET"),
        "key_id": os.getenv("B2_KEY_ID"),
        "app_key": os.getenv("B2_APP_KEY"),
        "backup_path": os.getenv("BACKUP_PATH"),
        "schedule_type": os.getenv("SCHEDULE_TYPE"),
        "schedule_time": os.getenv("SCHEDULE_TIME"),
        "schedule_days": os.getenv("SCHEDULE_DAYS"),
        "schedule_dates": os.getenv("SCHEDULE_DATES"),
    }

# -------------------------------------------------
# B2
# -------------------------------------------------
def connect_to_b2(key_id, app_key):
    info = InMemoryAccountInfo()
    api = B2Api(info)
    api.authorize_account("production", key_id, app_key)
    return api

def upload_directory_to_b2(api, bucket_name, local_folder):
    bucket = api.get_bucket_by_name(bucket_name)
    root = Path(local_folder)

    for file in root.rglob("*"):
        if file.is_file():
            remote = str(file.relative_to(root)).replace("\\", "/")
            print(Fore.BLUE + f"🔼 Uploading {remote}")
            bucket.upload(UploadSourceLocalFile(str(file)), remote)

# -------------------------------------------------
# Scheduling (FIXED)
# -------------------------------------------------
def schedule_task(cfg):
    if cfg["schedule_type"] == "NONE":
        print(Fore.YELLOW + "⚠️ Scheduling skipped.")
        return

    task_name = "BackupToBackblazeB2"
    script = Path(__file__).resolve()
    username = os.environ.get("USERNAME")

    base_cmd = [
        "schtasks",
        "/Create",
        "/TN", task_name,
        "/TR", f'"{sys.executable}" "{script}"',
        "/RU", username,
        "/RL", "LIMITED",
        "/F"
    ]

    if cfg["schedule_type"] == "DAILY":
        base_cmd += ["/SC", "DAILY", "/ST", cfg["schedule_time"]]

    elif cfg["schedule_type"] == "WEEKLY":
        base_cmd += ["/SC", "WEEKLY", "/D", cfg["schedule_days"], "/ST", cfg["schedule_time"]]

    elif cfg["schedule_type"] == "MONTHLY":
        base_cmd += ["/SC", "MONTHLY", "/D", cfg["schedule_dates"], "/ST", cfg["schedule_time"]]

    elif cfg["schedule_type"] == "ONCE":
        today = datetime.now().strftime("%m/%d/%Y")
        base_cmd += ["/SC", "ONCE", "/ST", cfg["schedule_time"], "/SD", today]

    cmd_str = " ".join(base_cmd)
    log(f"Running: {cmd_str}")

    result = subprocess.run(cmd_str, shell=True, capture_output=True, text=True)
    log("STDOUT: " + result.stdout)
    log("STDERR: " + result.stderr)

    # VERIFY
    verify = subprocess.run(
        f'schtasks /Query /TN "{task_name}"',
        shell=True,
        capture_output=True,
        text=True
    )

    if verify.returncode == 0:
        print(Fore.GREEN + "✅ Scheduled task created and verified.")
        log("Task verified successfully.")
    else:
        print(Fore.RED + "❌ Task not found after creation.")
        log("Task verification failed.")

# -------------------------------------------------
# Main
# -------------------------------------------------
def main():
    cfg = load_config()
    api = connect_to_b2(cfg["key_id"], cfg["app_key"])
    upload_directory_to_b2(api, cfg["bucket"], cfg["backup_path"])
    schedule_task(cfg)
    print(Fore.GREEN + "\n✅ Backup complete.")

if __name__ == "__main__":
    main()
