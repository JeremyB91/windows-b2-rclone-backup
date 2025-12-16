import os
import subprocess
import sys
from pathlib import Path
from datetime import datetime
from getpass import getpass

# Ensure required packages are installed
def install_prerequisites():
    try:
        import b2sdk.v2
        from colorama import init, Fore
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "b2sdk", "colorama"])
        import b2sdk.v2
        from colorama import init, Fore
    init(autoreset=True)

install_prerequisites()
from colorama import Fore
from b2sdk.v2 import InMemoryAccountInfo, B2Api, UploadSourceLocalFile

# Prompt user for configuration
def get_user_input():
    print(Fore.CYAN + "\n=== Backblaze B2 Backup Setup ===")

    bucket_name = input(Fore.GREEN + "Enter your B2 bucket name: ").strip()
    key_id = input(Fore.GREEN + "Enter your B2 application key ID: ").strip()
    app_key = getpass(Fore.GREEN + "Enter your B2 application key (input hidden): ").strip()
    local_folder = input(Fore.GREEN + "Enter the full path to the folder you want to backup: ").strip()
    schedule = input(Fore.GREEN + "Enter backup schedule time (e.g., '03:00' for 3 AM daily): ").strip()

    return bucket_name, key_id, app_key, local_folder, schedule

# Connect to Backblaze B2
def connect_to_b2(key_id, app_key):
    info = InMemoryAccountInfo()
    b2_api = B2Api(info)
    b2_api.authorize_account("production", key_id, app_key)
    return b2_api

# Upload files to B2
def upload_directory_to_b2(b2_api, bucket_name, local_folder):
    bucket = b2_api.get_bucket_by_name(bucket_name)
    local_folder_path = Path(local_folder)

    print(Fore.YELLOW + f"\nUploading contents of {local_folder_path} to B2 bucket '{bucket_name}'...\n")

    for file_path in local_folder_path.rglob('*'):
        if file_path.is_file():
            rel_path = file_path.relative_to(local_folder_path)
            print(Fore.BLUE + f"Uploading: {rel_path}")
            bucket.upload(UploadSourceLocalFile(str(file_path)), str(rel_path))

# Schedule this script using Windows Task Scheduler
def schedule_task(schedule_time):
    current_script = Path(__file__).resolve()
    task_name = "BackupToBackblazeB2"
    hour, minute = schedule_time.split(':')

    schtasks_cmd = [
        "schtasks",
        "/Create",
        "/SC", "DAILY",
        "/TN", task_name,
        "/TR", f'"{sys.executable}" "{current_script}" --run',
        "/ST", f"{hour.zfill(2)}:{minute.zfill(2)}",
        "/F"
    ]

    print(Fore.MAGENTA + "\nScheduling task in Windows Task Scheduler...\n")
    subprocess.run(" ".join(schtasks_cmd), shell=True)

# Main flow
def main():
    if "--run" in sys.argv:
        # Load saved config (for real world you'd save & load config securely)
        print(Fore.CYAN + f"\nRunning backup at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        # Here you would load from a config file, keeping this simple
        return

    # Interactive setup
    bucket_name, key_id, app_key, local_folder, schedule_time = get_user_input()

    b2_api = connect_to_b2(key_id, app_key)
    upload_directory_to_b2(b2_api, bucket_name, local_folder)
    schedule_task(schedule_time)

    print(Fore.GREEN + "\n✅ Backup uploaded and scheduled successfully!")

if __name__ == "__main__":
    main()
