import os
import subprocess
import sys
from pathlib import Path
from datetime import datetime
from getpass import getpass

# Auto install packages
def install_prerequisites():
    try:
        import b2sdk.v2
        from colorama import init, Fore
        import dotenv
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "b2sdk", "colorama", "python-dotenv"])
        import b2sdk.v2
        from colorama import init, Fore
        import dotenv
    init(autoreset=True)

install_prerequisites()
from colorama import Fore
from b2sdk.v2 import InMemoryAccountInfo, B2Api, UploadSourceLocalFile
from dotenv import load_dotenv, set_key

# Config file path
ENV_PATH = Path(".env")

def prompt_and_save_env():
    print(Fore.CYAN + "\n=== Backup Configuration ===")
    bucket_name = input(Fore.GREEN + "B2 Bucket Name: ").strip()
    key_id = input(Fore.GREEN + "B2 Application Key ID: ").strip()
    app_key = getpass(Fore.GREEN + "B2 Application Key (hidden): ").strip()
    local_folder = input(Fore.GREEN + "Full path to folder to backup: ").strip()
    schedule = input(Fore.GREEN + "Backup time (e.g. 03:00 for 3AM): ").strip()

    with open(ENV_PATH, "w") as f:
        f.write("")

    set_key(ENV_PATH, "B2_BUCKET", bucket_name)
    set_key(ENV_PATH, "B2_KEY_ID", key_id)
    set_key(ENV_PATH, "B2_APP_KEY", app_key)
    set_key(ENV_PATH, "BACKUP_PATH", local_folder)
    set_key(ENV_PATH, "BACKUP_SCHEDULE", schedule)

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
        "schedule": os.getenv("BACKUP_SCHEDULE")
    }

def connect_to_b2(key_id, app_key):
    info = InMemoryAccountInfo()
    b2_api = B2Api(info)
    b2_api.authorize_account("production", key_id, app_key)
    return b2_api

def upload_directory_to_b2(b2_api, bucket_name, local_folder):
    bucket = b2_api.get_bucket_by_name(bucket_name)
    local_folder_path = Path(local_folder)

    print(Fore.YELLOW + f"\nUploading contents of {local_folder_path} to B2 bucket '{bucket_name}'...\n")

    for file_path in local_folder_path.rglob('*'):
        if file_path.is_file():
            rel_path = file_path.relative_to(local_folder_path)
            print(Fore.BLUE + f"Uploading: {rel_path}")
            bucket.upload(UploadSourceLocalFile(str(file_path)), str(rel_path))

def schedule_task(schedule_time):
    current_script = Path(__file__).resolve()
    task_name = "BackupToBackblazeB2"
    hour, minute = schedule_time.split(':')

    schtasks_cmd = [
        "schtasks",
        "/Create",
        "/SC", "DAILY",
        "/TN", task_name,
        "/TR", f'"{sys.executable}" "{current_script}"',
        "/ST", f"{hour.zfill(2)}:{minute.zfill(2)}",
        "/F"
    ]

    print(Fore.MAGENTA + "\nScheduling daily task in Windows Task Scheduler...\n")
    subprocess.run(" ".join(schtasks_cmd), shell=True)

def main():
    config = load_config()
    b2_api = connect_to_b2(config["key_id"], config["app_key"])
    upload_directory_to_b2(b2_api, config["bucket"], config["backup_path"])
    schedule_task(config["schedule"])

    print(Fore.GREEN + "\n✅ Backup complete and task scheduled!")

if __name__ == "__main__":
    main()
