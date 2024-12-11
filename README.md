# 📄 Immutable Backups Script for Synology NAS with Xen Orchestra

## Overview

This script is designed to facilitate **immutable backups** on a **Synology NAS** using **Btrfs** subvolumes. It complements the backup functionality of **Xen Orchestra (XO)**, enabling immutable storage on Synology devices where the standard `chattr` method (used by Xen Orchestra) does not work due to limitations with Btrfs on Synology.

## 📝 Why This Script?

- **Xen Orchestra** uses the `chattr +i` command to make backup files immutable.
- **Synology NAS** uses the **Btrfs** filesystem, which **does not support `chattr`**.
- This script uses **Btrfs subvolumes** and the **Btrfs property `ro`** (read-only) to achieve immutability.
- The script also ensures that backup directories containing `.vhd` files are converted to **Btrfs subvolumes** and made immutable for a specified duration (default is **14 days**).

## ⚙️ How It Works

1. **Monitor Backup Directory**:  
   The script continuously monitors a specified backup directory for new backup folders created by Xen Orchestra.

2. **Detect New Backups**:  
   When a new backup containing `.vhd` files is detected, the script:
   - Moves the backup files to a temporary directory.
   - Creates a **Btrfs subvolume** with the same name as the original directory.
   - Moves the files back into the newly created subvolume.
   - Makes the subvolume **immutable** using the `btrfs property set ro true` command.

3. **Retention Period**:  
   The script maintains immutability for a specified duration (default is **14 days**). After this period, the script:
   - Lifts the immutability by setting the subvolume back to **read-write**.
   - Cleans up the backup state to allow for new backups.

4. **Excluding Metadata Files**:  
   The script excludes specific metadata files (e.g., `cache.json.gz`) from immutability to ensure Xen Orchestra's operations aren't disrupted.

## 🛠️ Customization

- **Backup Directory**:  
  Modify the `BACKUP_DIR` variable to point to your Xen Orchestra backup location on the Synology NAS:
  ```bash
  BACKUP_DIR="/volume1/XCP06"
  ```

- **Immutability Duration**:  
  Set the duration for immutability in seconds (default is 14 days):
  ```bash
  IMMU_DURATION=1209600  # 14 days in seconds
  ```

## 🔗 Integration with Xen Orchestra

1. **Configure Xen Orchestra Backup**:
   - Set up your backup jobs in Xen Orchestra to use the Synology NAS as the target location.
   - Ensure backups are stored in a Btrfs volume on the Synology NAS.

2. **Run the Script on Synology**:
   - Copy the script to your Synology NAS (e.g., `/volume1/scripts/monitor_backups.sh`).
   - Make the script executable:
     ```bash
     chmod +x /volume1/scripts/monitor_backups.sh
     ```
   - Execute the script:
     ```bash
     sudo /volume1/scripts/monitor_backups.sh
     ```

3. **Automate Script Execution**:
   - Set up a **Scheduled Task** in the Synology Task Scheduler to run the script on boot or at regular intervals.

## 📦 Script Components

- **`save_backup_state`**: Saves the state (timestamp) of processed backups.
- **`get_backup_state`**: Reads the state of a backup from `backup_state.json`.
- **`is_subvolume`**: Checks if a directory is a Btrfs subvolume.
- **`move_files_to_subvolume`**: Moves files to a temporary location, creates a subvolume, and restores the files.
- **`make_immutable`**: Sets a Btrfs subvolume to read-only (immutable).
- **`lift_immutability`**: Reverts a Btrfs subvolume to read-write.

## 🚨 Considerations

- **Root Access**: The script requires `sudo` privileges to execute Btrfs commands.
- **Retention Policy**: Ensure your backup retention aligns with the immutability period to avoid conflicts.
- **Incremental Backups**: To protect incremental backups, ensure:
  - Full backup interval is **smaller than `n` days**.
  - Retention is **greater than `2n - 1` days**.

## 📝 Example Log Output

The script logs its actions to `/volume1/scripts/monitor_backups.log`. Sample log entries:

```
Mon Apr 22 10:00:00 UTC 2024 - Starting monitor_backups.sh
Mon Apr 22 10:01:10 UTC 2024 - .vhd file found in /volume1/XCP06/backup1
Mon Apr 22 10:01:12 UTC 2024 - Created temp directory /volume1/XCP06/backup1.temp to store files temporarily
Mon Apr 22 10:01:20 UTC 2024 - Created subvolume /volume1/XCP06/backup1
Mon Apr 22 10:01:25 UTC 2024 - Making subvolume /volume1/XCP06/backup1 immutable (excluding cache.json.gz)
Mon May 06 10:01:30 UTC 2024 - Lifted immutability for /volume1/XCP06/backup1
```

## ✅ Conclusion

This script ensures that immutable backups are successfully implemented on **Synology NAS** using **Btrfs** subvolumes, working around the `chattr` limitation in Xen Orchestra. By integrating this script with your backup workflows, you can achieve reliable, immutable backups that protect your data integrity.

---

## 📢 Feedback and Contributions

If you encounter issues or have suggestions for improvements, please feel free to contribute or provide feedback!
