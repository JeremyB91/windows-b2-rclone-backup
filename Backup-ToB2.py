import os
import subprocess
import sys

# Utility to install packages
def install_package(package):
    print(f"📦 Installing required package: {package}")
    subprocess.check_call([sys.executable, "-m", "pip", "install", package])

# Try to import b2sdk, install if not found
try:
    import b2sdk.v2 as b2
except ImportError:
    install_package("b2sdk")
    import b2sdk.v2 as b2

from getpass import getpass
from pathlib import Path

# Prompt user for credentials and configuration
def get_user_input():
    print("🔐 Please enter your Backblaze B2 credentials and backup details:\n")
    key_id = input("👉 Application Key ID: ").strip()
    app_key = getpass("🔑 Application Key (input hidden): ").strip()
    bucket_name = input("🪣 Bucket Name: ").strip()
    directory = input("📁 Full path to the local directory to back up: ").strip()

    if not os.path.isdir(directory):
        print(f"❌ Error: The directory '{directory}' does not exist.")
        sys.exit(1)

    return key_id, app_key, bucket_name, Path(directory)

# Backup files to B2 bucket
def backup_to_b2(key_id, app_key, bucket_name, backup_dir):
    info = b2.InMemoryAccountInfo()
    b2_api = b2.B2Api(info)
    print("🔗 Connecting to Backblaze B2...")
    b2_api.authorize_account("production", key_id, app_key)

    print(f"📡 Locating bucket '{bucket_name}'...")
    try:
        bucket = b2_api.get_bucket_by_name(bucket_name)
    except b2.exception.NonExistentBucket:
        print(f"❌ Error: Bucket '{bucket_name}' does not exist.")
        sys.exit(1)

    print(f"⬆️ Uploading files from: {backup_dir}")
    for file_path in backup_dir.rglob("*"):
        if file_path.is_file():
            relative_path = file_path.relative_to(backup_dir).as_posix()
            print(f"📤 Uploading {relative_path}...")
            with open(file_path, "rb") as file:
                bucket.upload_bytes(file.read(), relative_path)

    print("✅ Backup completed successfully!")

# Main
if __name__ == "__main__":
    try:
        key_id, app_key, bucket_name, backup_dir = get_user_input()
        backup_to_b2(key_id, app_key, bucket_name, backup_dir)
    except KeyboardInterrupt:
        print("\n⛔ Operation cancelled by user.")
