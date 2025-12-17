import os
import site
import subprocess
import sys
from pathlib import Path
from getpass import getpass

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

def prompt_and_save_env():
    print(Fore.CYAN + "\n=== 🔧 Backup Configuration Setup ===")
    bucket_name = input(Fore.GREEN + "🪣 B2 Bucket Name: ").strip()
    key_id = input(Fore.GREEN + "🔑 B2 Application Key ID: ").strip()
    app_key = getpass(Fore.GREEN + "🔒 B2 Application Key (hidden): ").strip()
    local_folder = input(Fore.GREEN + "📁 Full path to folder to backup: ").strip()

    # Schedule setup
    print(Fore.CYAN + "\n📅 Schedule Options:")
    print("1. Daily")
    print("2. Weekly (e.g. every Monday)")
    print("3. Monthly (e.g. every 15th)")
    print("4. One-Time")
    print("5. Do not schedule")
    schedule_type = input(Fore.GREEN + "Select a schedule type [1-5]: ").strip()

    schedule_map = {
        "1": "DAILY",
        "2": "WEEKLY",
        "3": "MONTHLY",
        "4": "ONCE",
        "5": "NONE"
    }
    schedule_type = schedule_map.get(schedule_type, "DAILY")
    task_details = {"type": schedule_type}

    if schedule_type != "NONE":
        time_input = input(Fore.GREEN + "⏰ Time (HH:MM, 24h format): ").strip()
        task_details["time"] = time_input

        if schedule_type == "WEEKLY":
            days = input(Fore.GREEN + "🗓️ Enter days (e.g. MON,TUE,FRI): ").strip().upper()
            task_details["days"] = days
        elif schedule_type == "MONTHLY":
            dates = input(Fore.GREEN + "📅 Enter day(s) of month (e.g. 1,15,28): ").strip()
            task_details["dates"] = dates

    versioning = input(Fore.GREEN + "🗂️ Let B2 manage versions of files? [Y/n]: ").strip().lower()
    enable_versioning = "yes" if versioning != "n" else "no"

    exclude = input(Fore.GREEN + "🚫 Exclude file extensions? (comma-separated, e.g. .tmp,.log) or leave blank: ").strip()
    if exclude:
        with open(EXCLUDE_PATH, "w") as f:
            f.write("\n".join([e.strip() for e in exclude.split(",") if e.strip()]))
        print(Fore.YELLOW + f"📝 Exclusion patterns saved to {EXCLUDE_PATH}")
    elif EXCLUDE_PATH.exists():
        EXCLUDE_PATH.unlink()

    with open(ENV_PATH, "w") as f:
        f.write("")

    set_key(ENV_PATH, "B2_BUCKET", bucket_name)
    set_key(ENV_PATH, "B2_KEY_ID", key_id)
    set_key(ENV_PATH, "B2_APP_KEY", app_key)
    set_key(ENV_PATH, "BACKUP_PATH", local_folder)
    set_key(ENV_PATH, "VERSIONING", enable_versioning)
    set_key(ENV_PATH, "SCHEDULE_TYPE", task_details["type"])
    set_key(ENV_PATH, "SCHEDULE_TIME", task_details.get("time", ""))
    set_key(ENV_PATH, "SCHEDULE_DAYS", task_details.get("days", ""))
    set_key(ENV_PATH, "SCHEDULE_DATES", task_details.get("dates", ""))

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
        "versioning": os.getenv("VERSIONING", "yes"),
        "schedule_type": os.getenv("SCHEDULE_TYPE"),
        "schedule_time": os.getenv("SCHEDULE_TIME"),
        "schedule_days": os.getenv("SCHEDULE_DAYS"),
        "schedule_dates": os.getenv("SCHEDULE_DATES"),
    }

def connect_to_b2(key_id, app_key):
    info = InMemoryAccountInfo()
    b2_api = B2Api(info)
    b2_api.authorize_account("production", key_id, app_key)
    return b2_api

def should_exclude(file_path):
    if not EXCLUDE_PATH.exists():
        return False
    ext = file_path.suffix.lower()
    with open(EXCLUDE_PATH, "r") as f:
        excluded = [line.strip().lower() for line in f if line.strip()]
    return ext in excluded

def upload_directory_to_b2(b2_api, bucket_name, local_folder):
    bucket = b2_api.get_bucket_by_name(bucket_name)
    local_folder_path = Path(local_folder)

    print(Fore.YELLOW + f"\n📤 Uploading files from '{local_folder_path}' to B2 bucket '{bucket_name}'...\n")

    for file_path in local_folder_path.rglob('*'):
        if file_path.is_file() and not should_exclude(file_path):
            rel_path = str(file_path.relative_to(local_folder_path)).replace("\\", "/")
            print(Fore.BLUE + f"🔼 Uploading: {rel_path}")
            bucket.upload(UploadSourceLocalFile(str(file_path)), rel_path)
        elif file_path.is_file():
            print(Fore.LIGHTBLACK_EX + f"⏭️ Skipped (excluded): {file_path.name}")

def schedule_task(cfg):
    if cfg["schedule_type"] == "NONE":
        print(Fore.YELLOW + "\n⚠️ Skipping task scheduling.")
        return

    current_script = Path(__file__).resolve()
    task_name = "BackupToBackblazeB2"

    cmd = [
        "schtasks",
        "/Create",
        "/TN", task_name,
        "/TR", f'"{sys.executable}" "{current_script}"',
        "/F"
    ]

    if cfg["schedule_type"] == "DAILY":
        cmd += ["/SC", "DAILY", "/ST", cfg["schedule_time"]]
    elif cfg["schedule_type"] == "WEEKLY":
        cmd += ["/SC", "WEEKLY", "/D", cfg["schedule_days"], "/ST"_]()]()
