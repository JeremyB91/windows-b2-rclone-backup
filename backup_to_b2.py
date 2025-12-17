import os
import site
import subprocess
import sys
from pathlib import Path
from getpass import getpass
from datetime import datetime
from time import perf_counter
import logging

# -------------------------------------------------
# Dependency bootstrap
# -------------------------------------------------
def install_prerequisites():
    try:
        import b2sdk.v2
        from colorama import init
        import dotenv
        import requests
    except ImportError:
        subprocess.check_call([
            sys.executable, "-m", "pip", "install",
            "--user", "b2sdk", "colorama", "python-dotenv", "requests"
        ])
        site.main()
        user_site = site.getusersitepackages()
        if user_site not in sys.path:
            sys.path.append(user_site)
        import b2sdk.v2
        from colorama import init
        import dotenv
        import requests
    init(autoreset=True)

install_prerequisites()

from colorama import Fore
from b2sdk.v2 import InMemoryAccountInfo, B2Api, UploadSourceLocalFile
from dotenv import load_dotenv, set_key
import requests

# -------------------------------------------------
# Paths & logging
# -------------------------------------------------
ENV_PATH = Path(".env")
EXCLUDE_PATH = Path("exclude_patterns.txt")

LOG_DIR = Path("logs")
LOG_DIR.mkdir(exist_ok=True)

RUN_TS = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
LOG_FILE = LOG_DIR / f"backup_{RUN_TS}.log"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger("b2_backup")

# -------------------------------------------------
# Stats tracking
# -------------------------------------------------
class BackupStats:
    def __init__(self):
        self.start_time = perf_counter()
        self.files_uploaded = 0
        self.files_failed = 0
        self.files_skipped = 0
        self.errors = []

    def duration(self):
        return round(perf_counter() - self.start_time, 2)

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

    webhook = input(
        Fore.GREEN +
        "🔔 Discord webhook URL (optional, press Enter to skip): "
    ).strip()

    if exclude:
        with open(EXCLUDE_PATH, "w", encoding="utf-8") as f:
            f.write("\n".join(e.strip().lower() for e in exclude.split(",") if e.strip()))
        print(Fore.YELLOW + f"📝 Exclusion patterns saved to {EXCLUDE_PATH}")
    elif EXCLUDE_PATH.exists():
        EXCLUDE_PATH.unlink()

    with open(ENV_PATH, "w", encoding="utf-8"):
        pass

    set_key(ENV_PATH, "B2_BUCKET", bucket_name)
    set_key(ENV_PATH, "B2_KEY_ID", key_id)
    set_key(ENV_PATH, "B2_APP_KEY", app_key)
    set_key(ENV_PATH, "BACKUP_PATH", local_folder)
    set_key(ENV_PATH, "VERSIONING", versioning)

    if webhook:
        set_key(ENV_PATH, "DISCORD_WEBHOOK_URL", webhook)

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
        "discord_webhook": os.getenv("DISCORD_WEBHOOK_URL"),
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

def upload_directory_to_b2(api, bucket_name, local_folder, stats: BackupStats):
    bucket = api.get_bucket_by_name(bucket_name)
    root = Path(local_folder)

    logger.info(f"Starting upload from '{root}' to bucket '{bucket_name}'")

    for file in root.rglob("*"):
        if not file.is_file():
            continue

        if should_exclude(file):
            stats.files_skipped += 1
            logger.info(f"Skipped (excluded): {file}")
            continue

        remote = str(file.relative_to(root)).replace("\\", "/")

        try:
            bucket.upload(UploadSourceLocalFile(str(file)), remote)
            stats.files_uploaded += 1
            logger.info(f"Uploaded: {remote}")
        except Exception as e:
            stats.files_failed += 1
            stats.errors.append(f"{remote}: {e}")
            logger.error(f"FAILED {remote}: {e}")

# -------------------------------------------------
# Discord reporting
# -------------------------------------------------
def send_discord_summary(webhook_url, stats: BackupStats, log_path: Path):
    if not webhook_url:
        return

    summary = (
        f"🗄️ **B2 Backup Complete**\n"
        f"📦 Uploaded: {stats.files_uploaded}\n"
        f"⏭️ Skipped: {stats.files_skipped}\n"
        f"❌ Failed: {stats.files_failed}\n"
        f"⏱️ Duration: {stats.duration()} seconds"
    )

    data = {"content": summary}
    files = None

    if log_path.exists() and log_path.stat().st_size < 7_500_000:
        files = {"file": log_path.open("rb")}

    try:
        requests.post(webhook_url, data=data, files=files, timeout=10)
    except Exception as e:
        logger.error(f"Discord webhook failed: {e}")

# -------------------------------------------------
# Main
# -------------------------------------------------
def main():
    cfg = load_config()
    stats = BackupStats()

    api = connect_to_b2(cfg["key_id"], cfg["app_key"])
    upload_directory_to_b2(api, cfg["bucket"], cfg["backup_path"], stats)

    logger.info("Backup completed")
    logger.info(
        f"Uploaded={stats.files_uploaded}, "
        f"Skipped={stats.files_skipped}, "
        f"Failed={stats.files_failed}, "
        f"Duration={stats.duration()}s"
    )

    send_discord_summary(cfg.get("discord_webhook"), stats, LOG_FILE)

    print(Fore.GREEN + "\n✅ Backup complete.")

if __name__ == "__main__":
    main()
