# 📄 Immutable Backups Script for Synology NAS with Xen Orchestra

## Overview

This script facilitates **immutable backups** on a **Synology NAS** using **Btrfs** subvolumes. It complements **Xen Orchestra (XO)** backup functionality by achieving immutability through Btrfs subvolume properties instead of the `chattr` method, which is unsupported on Synology's Btrfs implementation.

## 📝 Why This Script?

- **Xen Orchestra** uses `chattr +i` to make backup files immutable.
- **Synology NAS** with Btrfs does **not support `chattr`**.
- This script utilizes **Btrfs subvolumes** and the **Btrfs `ro` (read-only) property** to implement immutability.
- It ensures that backup directories containing `.vhd` files are converted to **Btrfs subvolumes** and made immutable for a specified duration (default: **14 days**).
- The script now effectively **excludes directories like `@eaDir`, `#recycle`, and `.snapshots`** to avoid unnecessary processing.

## ⚙️ How It Works

1. **Monitors Backup Directory**:
   - Continuously scans a specified backup directory for new backup folders created by Xen Orchestra.

2. **Detects New Backups**:
   - When a new backup containing `.vhd` files is detected, the script:
     - Excludes unnecessary directories (e.g., `@eaDir`, `#recycle`, `.snapshots`).
     - Replaces `cache.json.gz` files with symbolic links to a writable cache directory.
     - Moves the backup files to a temporary location.
     - Creates a **Btrfs subvolume** with the original directory name.
     - Restores the files to the new subvolume.
     - Makes the subvolume **immutable** using `btrfs property set ro true`.

3. **Retention Period**:
   - Keeps backups immutable for a configurable duration (default: **14 days**).
   - After this period, the script lifts the immutability and removes the backup state entry, allowing new backups.

## 🛠️ Customization

- **Backup Directory**:
  Set the path to your Xen Orchestra backup location:
  ```bash
  BACKUP_DIR="/volume1/XCP06/xo-vm-backups"
  ```

- **Writable Cache Directory**:
  Define where `cache.json.gz` files are moved for write access:
  ```bash
  CACHE_DIR="/volume1/XCP06_writable_cache"
  ```

- **Immutability Duration**:
  Set the immutability duration in seconds (default: 14 days):
  ```bash
  IMMU_DURATION=1209600  # 14 days in seconds
  ```

## 🔗 Integration with Xen Orchestra

1. **Xen Orchestra Backup Configuration**:
   - Configure your Xen Orchestra backup jobs to target the Synology NAS.
   - Ensure the backup destination is on a **Btrfs volume**.

2. **Deploy the Script on Synology**:
   - Copy the script to your Synology NAS (e.g., `/volume1/scripts/monitor_backups.sh`):
     ```bash
     chmod +x /volume1/scripts/monitor_backups.sh
     ```
   - Run the script manually or automate it:
     ```bash
     sudo /volume1/scripts/monitor_backups.sh
     ```

3. **Automate Script Execution**:
   - Use Synology's **Task Scheduler** to run the script at boot or regular intervals.

## 📦 Script Components

- **`save_backup_state`**: Saves the state (timestamp) of processed backups.
- **`get_backup_state`**: Reads the state of a backup from `backup_state.json`.
- **`is_subvolume`**: Checks if a directory is a Btrfs subvolume.
- **`skip_unnecessary_directories`**: Excludes `@eaDir`, `#recycle`, and `.snapshots` directories.
- **`replace_cache_files_with_symlinks`**: Moves `cache.json.gz` files to a writable cache and replaces them with symbolic links.
- **`move_files_to_subvolume`**: Moves files to a temporary location, creates a subvolume, restores files, and makes the subvolume immutable.
- **`make_immutable`**: Sets a Btrfs subvolume to read-only (immutable).
- **`lift_immutability`**: Reverts a Btrfs subvolume to read-write.

## 🚨 Considerations

- **Root Access**: The script requires `sudo` privileges to execute Btrfs commands.
- **Retention Policy**: Ensure backup retention settings align with the immutability period to avoid conflicts.
- **Exclusions**: The script skips processing of the following directories:
  - `@eaDir`
  - `#recycle`
  - `.snapshots`

## 📝 Example Log Output

Log entries are saved to `/volume1/scripts/monitor_backups.log`:

```
Mon Apr 22 10:00:00 UTC 2024 - Starting monitor_backups.sh
Mon Apr 22 10:01:10 UTC 2024 - New backup detected in /volume1/XCP06/backup1
Mon Apr 22 10:01:12 UTC 2024 - Replaced cache.json.gz with symbolic link
Mon Apr 22 10:01:20 UTC 2024 - Created subvolume /volume1/XCP06/backup1
Mon Apr 22 10:01:25 UTC 2024 - Making subvolume /volume1/XCP06/backup1 immutable
Mon May 06 10:01:30 UTC 2024 - Lifted immutability for /volume1/XCP06/backup1
```

## ✅ Conclusion

This script ensures reliable immutable backups on **Synology NAS** using **Btrfs** subvolumes, overcoming the limitations of `chattr` in Xen Orchestra. Integrate it with your backup workflow to safeguard your data effectively.

---

## 📢 Feedback and Contributions

If you encounter issues or have suggestions for improvements, please provide feedback or contribute to the project!

