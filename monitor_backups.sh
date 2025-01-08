#!/bin/bash

# Directory where backups are stored (customize if necessary)
BACKUP_DIR="/volume1/XCP06/xo-vm-backups"
CACHE_DIR="/volume1/XCP06_writable_cache" # Writable directory for cache.json.gz
IMMU_DURATION=1209600                     # 14 days in seconds
BACKUP_STATE_FILE="/volume1/scripts/backup_state.json"

# Log file for debugging
LOG_FILE="/volume1/scripts/monitor_backups.log"
echo "$(date) - Starting monitor_backups.sh" >>"$LOG_FILE"

# Check if the backup_state.json file exists, if not create it
if [ ! -f "$BACKUP_STATE_FILE" ]; then
  echo "{}" >"$BACKUP_STATE_FILE"
fi

# Function to save backup state
save_backup_state() {
  BACKUP_DIR="$1"
  BACKUP_TIMESTAMP="$2"
  jq --arg dir "$BACKUP_DIR" --arg timestamp "$BACKUP_TIMESTAMP" \
    '. + {($dir): $timestamp}' "$BACKUP_STATE_FILE" >tmp.json && mv tmp.json "$BACKUP_STATE_FILE"
  echo "$(date) - Saved state for $BACKUP_DIR with timestamp $BACKUP_TIMESTAMP" >>"$LOG_FILE"
}

# Function to skip unnecessary directories
declare -A SKIPPED_LOGGED_DIRS=()

skip_unnecessary_directories() {
  DIR="$1"
  if [[ "$DIR" == *"#recycle"* || "$DIR" == *"@eaDir"* || "$DIR" == *.snapshots* ]]; then
    # Log only once per run
    if [ -z "${SKIPPED_LOGGED_DIRS[$DIR]}" ]; then
      echo "$(date) - Skipping special directory $DIR" >>"$LOG_FILE"
      SKIPPED_LOGGED_DIRS[$DIR]=1
    fi
    return 0
  fi
  return 1
}

# Function to read backup state
get_backup_state() {
  BACKUP_DIR="$1"
  jq -r --arg dir "$BACKUP_DIR" '.[$dir]' "$BACKUP_STATE_FILE"
}

# Function to check if a directory is a Btrfs subvolume
is_subvolume() {
  DIR="$1"
  sudo btrfs subvolume show "$DIR" &>/dev/null
  if [ $? -eq 0 ]; then
    return 0 # Directory is a subvolume
  else
    return 1 # Directory is not a subvolume
  fi
}

# Function to replace cache files with symbolic links
replace_cache_files_with_symlinks() {
  DIR="$1"

  # Find all cache.json.gz files and move them to the writable cache directory
  find "$DIR" -type f -name "cache.json.gz" | while read -r FILE; do
    # Generate a unique relative path for the writable cache directory
    REL_PATH="${FILE#$BACKUP_DIR/}"                # Relative path from the backup root
    SAFE_REL_PATH=$(echo "$REL_PATH" | tr '/' '_') # Replace slashes with underscores for a safe filename
    TARGET_FILE="$CACHE_DIR/$SAFE_REL_PATH"        # Writable cache file path

    # Create the target directory in the writable cache if it doesn't exist
    TARGET_DIR="$(dirname "$TARGET_FILE")"
    mkdir -p "$TARGET_DIR"

    # Move the cache file to the writable cache directory
    mv "$FILE" "$TARGET_FILE"

    # Create a symbolic link pointing to the new location
    ln -s "$TARGET_FILE" "$FILE"

    echo "$(date) - Moved $FILE to $TARGET_FILE and created symbolic link" >>"$LOG_FILE"
  done
}

# Function to move files to a temporary folder, create a subvolume, and make the subvolume immutable
move_files_to_subvolume() {
  DIR="$1"
  TEMP_DIR="${DIR}_temp_$(date +%s)"

  # Replace cache files with symlinks
  replace_cache_files_with_symlinks "$DIR"

  # Check if $DIR is a subvolume
  if is_subvolume "$DIR"; then
    echo "$(date) - $DIR is already a subvolume" >>"$LOG_FILE"

    # Lift immutability to allow modifications
    sudo btrfs property set "$DIR" ro false
    if [ $? -ne 0 ]; then
      echo "$(date) - Failed to lift immutability for $DIR; cannot proceed" >>"$LOG_FILE"
      return 1
    fi
    echo "$(date) - Lifted immutability for $DIR" >>"$LOG_FILE"

    # Move files to TEMP_DIR
    sudo mkdir -p "$TEMP_DIR"
    sudo mv "$DIR"/{*,.[^.]*} "$TEMP_DIR" 2>/dev/null || true
    echo "$(date) - Moved files from $DIR to temp directory $TEMP_DIR" >>"$LOG_FILE"

    # Delete the subvolume
    sudo btrfs subvolume delete "$DIR"
    if [ $? -ne 0 ]; then
      echo "$(date) - Failed to delete subvolume $DIR" >>"$LOG_FILE"
      return 1
    fi
    echo "$(date) - Deleted existing subvolume $DIR" >>"$LOG_FILE"
  else
    # If not a subvolume, create TEMP_DIR and move files
    sudo mkdir -p "$TEMP_DIR"
    sudo mv "$DIR"/{*,.[^.]*} "$TEMP_DIR" 2>/dev/null || true
    echo "$(date) - Moved files from $DIR to temp directory $TEMP_DIR" >>"$LOG_FILE"

    # Remove the original directory
    sudo rmdir "$DIR"
    if [ $? -ne 0 ]; then
      echo "$(date) - Failed to remove original directory $DIR" >>"$LOG_FILE"
      return 1
    fi
    echo "$(date) - Removed original directory $DIR" >>"$LOG_FILE"
  fi

  # Create the subvolume
  sudo btrfs subvolume create "$DIR"
  if [ $? -ne 0 ]; then
    echo "$(date) - Failed to create subvolume $DIR" >>"$LOG_FILE"
    return 1
  fi
  echo "$(date) - Created subvolume $DIR" >>"$LOG_FILE"

  # Move files back to the original directory
  sudo mv "$TEMP_DIR"/* "$DIR/"
  sudo mv "$TEMP_DIR"/.* "$DIR/" 2>/dev/null || true
  sudo rmdir "$TEMP_DIR" # Remove the temp directory
  echo "$(date) - Moved files back into subvolume $DIR and removed temp directory $TEMP_DIR" >>"$LOG_FILE"

  # Make the subvolume immutable
  make_immutable "$DIR"
}


# Function to make a directory or subvolume immutable
make_immutable() {
  DIR="$1"

  # Skip special directories
  if skip_unnecessary_directories "$DIR"; then
    return
  fi

  # Ensure the path is a directory
  if [ ! -d "$DIR" ]; then
    echo "$(date) - Skipping immutability for $DIR as it is not a directory" >>"$LOG_FILE"
    return
  fi

  # Check if the directory is a subvolume
  if is_subvolume "$DIR"; then
    echo "$(date) - Making subvolume $DIR immutable" >>"$LOG_FILE"
    sudo btrfs property set "$DIR" ro true
    if [ $? -eq 0 ]; then
      echo "$(date) - Successfully made subvolume $DIR immutable" >>"$LOG_FILE"
    else
      echo "$(date) - Failed to make subvolume $DIR immutable" >>"$LOG_FILE"
    fi
  else
    echo "$(date) - $DIR is not a subvolume; cannot set immutability" >>"$LOG_FILE"
  fi
}

# Function to lift immutability on a subvolume
lift_immutability() {
  DIR="$1"
  if is_subvolume "$DIR"; then
    echo "$(date) - Lifting immutability for subvolume $DIR" >>"$LOG_FILE"
    sudo btrfs property set "$DIR" ro false
  else
    echo "$(date) - $DIR is not a subvolume; nothing to do" >>"$LOG_FILE"
  fi
}

# Function to check if the backup directory is inactive (ignores cache.json.gz)
is_directory_inactive() {
  DIR="$1"
  INACTIVITY_PERIOD=600 # 10 minutes

  # Find the newest modification time of any file excluding cache.json.gz
  LAST_MODIFIED_TIME=$(find "$DIR" -type f ! -name "cache.json.gz" -printf "%T@\n" | sort -n | tail -1)
  CURRENT_TIME=$(date +%s)

  if [ -z "$LAST_MODIFIED_TIME" ]; then
    echo "$(date) - No relevant files found in $DIR" >>"$LOG_FILE"
    return 1 # No relevant files found; cannot determine if backup is complete
  fi

  # Convert LAST_MODIFIED_TIME to an integer (strip decimal part)
  LAST_MODIFIED_TIME=${LAST_MODIFIED_TIME%.*}

  # Calculate the time difference using Bash arithmetic
  TIME_DIFF=$((CURRENT_TIME - LAST_MODIFIED_TIME))

  if [ "$TIME_DIFF" -ge "$INACTIVITY_PERIOD" ]; then
    return 0 # Directory is inactive (no changes for the specified inactivity period)
  else
    echo "$(date) - Directory $DIR is still active (last modified $TIME_DIFF seconds ago)" >>"$LOG_FILE"
    return 1 # Directory is still active
  fi
}

# Loop to monitor new directories
declare -A PROCESSED_DIRS=()
while true; do
  CURRENT_TIME=$(date +%s)
  NEW_BACKUP_FOUND=false

  echo "$(date) - Starting new iteration of backup monitoring loop" >>"$LOG_FILE"

  # Find all unique top-level backup directories containing .vhd files
  find "$BACKUP_DIR" -type f -name "*.vhd" |
    sed -E "s|^$BACKUP_DIR/([^/]+).*|\1|" |
    sort -u | while read -r DIR_NAME; do

    TOP_LEVEL_BACKUP="$BACKUP_DIR/$DIR_NAME"

    # Skip if directory has already been processed in this run
    if [ -n "${PROCESSED_DIRS[$TOP_LEVEL_BACKUP]}" ]; then
      continue
    fi

    # Exclude special directories like #recycle
    if skip_unnecessary_directories "$TOP_LEVEL_BACKUP"; then
      continue
    fi

    # Check if the directory was processed recently
    LAST_PROCESSED_TIME=$(get_backup_state "$TOP_LEVEL_BACKUP")
    if [ "$LAST_PROCESSED_TIME" != "null" ] && [ -n "$LAST_PROCESSED_TIME" ]; then
      TIME_DIFF=$((CURRENT_TIME - LAST_PROCESSED_TIME))
      if [ "$TIME_DIFF" -lt "$IMMU_DURATION" ]; then
        continue
      fi
    fi

    # Check if the backup is complete by checking for inactivity
    if is_directory_inactive "$TOP_LEVEL_BACKUP"; then
      echo "$(date) - Backup in $TOP_LEVEL_BACKUP appears complete; proceeding with subvolume creation" >>"$LOG_FILE"

      # Perform the steps to create a subvolume and make it immutable
      if move_files_to_subvolume "$TOP_LEVEL_BACKUP"; then
        save_backup_state "$TOP_LEVEL_BACKUP" "$CURRENT_TIME"
        PROCESSED_DIRS[$TOP_LEVEL_BACKUP]=1
        NEW_BACKUP_FOUND=true
      else
        echo "$(date) - Failed to process $TOP_LEVEL_BACKUP" >>"$LOG_FILE"
      fi
    else
      echo "$(date) - Backup in $TOP_LEVEL_BACKUP is still ongoing; skipping immutability" >>"$LOG_FILE"
    fi
  done

  # Clear the tracked processed directories for the next run
  PROCESSED_DIRS=()
  SKIPPED_LOGGED_DIRS=()

  # Sleep longer if no new backups are found
  if [ "$NEW_BACKUP_FOUND" = false ]; then
    sleep 600 # Sleep for 10 minutes if no new backups are found
  else
    sleep 60 # Default sleep interval if new backups are found
  fi
done
