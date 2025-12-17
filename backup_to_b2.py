import os
import site
import subprocess
import sys
from pathlib import Path
from getpass import getpass

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

# -------------------------------------------------
# Config setup
# -------------------------------------------------
def prompt_and_save_env():
    print(Fore.CYAN + "\n=== 🔧 Backup Configuration Setup ===")
    bucket_name = input(Fore.GREEN + "🪣 B2 Bucket Name: ").strip()
    key_id = input(Fore.GREEN + "🔑 B2 Application Key ID: ").strip()
    app_key = getpass(Fore.GREEN + "🔒 B2 Application Key (hidden): ").strip()
    local_folder = input(Fore.GREEN + "📁 Full path to folder to backup: ").strip()

    versioning = input(Fore.GREEN + "🗂️ Let B2 manage versions? [Y/n]: ").strip().lower()
    versioning = "yes" if versioning != "n" else "no"

    exclude = input(
        Fore.GREEN +
        "🚫 Exclude file extensions? (comma-separated, e.g. .tmp,.log) or leave blank: "
    ).strip()

    if exclude:
        with open(EXCLUDE_PATH, "w", encoding="utf-8") as f:
            f.write("\n".join(e.strip().lower() for e in exclude.split(",") if e.strip()))
        print(Fore.YELLOW + f"📝 Exclusion patterns saved to {EXCLUDE_PATH}")
    elif EXCLUDE_PATH.exists():
        EXCLUDE_PATH.unlink()

    with open(ENV_PATH, "w", encoding="utf-8") as f:
        f.write("")

    set_key(ENV_PATH, "B2_BUCKET", bucket_name)
    set_key(ENV_PATH, "B2_KEY_ID", key_id)
    set_key(ENV_PATH, "B2_APP_KEY", app_key)
    set_key(ENV_PATH, "BACKUP_PATH", local_folder)
    set_key(ENV_PATH, "VERSIONING", versioning)

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
    }

# -------------------------------------------------
# B2 logic
# -------------------------------------------------
def connect_to_b2(key_id, app_key):
    info = InMemoryAccountInfo()
    api = B2Api(info)
    api.authorize_account("production", key_id, app_key)
    return api

def should_exclude(file_path: Path) -> bool:
    if not EXCLUDE_PATH.exists():
        return False
    ext = file_path.suffix.lower()
    with open(EXCLUDE_PATH, "r", encoding="utf-8") as f:
        excluded = {line.strip() for line in f if line.strip()}
    return ext in excluded

def upload_directory_to_b2(api, bucket_name, local_folder):
    bucket = api.get_bucket_by_name(bucket_name)
    root = Path(local_folder)

    print(Fore.YELLOW + f"\n📤 Uploading files from '{root}' to B2 bucket '{bucket_name}'...\n")

    for file in root.rglob("*"):
        if file.is_file():
            if should_exclude(file):
                print(Fore.LIGHTBLACK_EX + f"⏭️ Skipped (excluded): {file.name}")
                continue

            remote = str(file.relative_to(root)).replace("\\", "/")
            print(Fore.BLUE + f"🔼 Uploading {remote}")
            bucket.upload(UploadSourceLocalFile(str(file)), remote)

# -------------------------------------------------
# Main
# -------------------------------------------------
def main():
    cfg = load_config()
    api = connect_to_b2(cfg["key_id"], cfg["app_key"])
    upload_directory_to_b2(api, cfg["bucket"], cfg["backup_path"])
    print(Fore.GREEN + "\n✅ Backup complete.")

if __name__ == "__main__":
    main()
