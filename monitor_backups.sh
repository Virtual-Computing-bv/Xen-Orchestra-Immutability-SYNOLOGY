#!/bin/bash

# Directory where backups are stored (customize if necessary)
BACKUP_DIR="/volume1/XCP06"
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
skip_unnecessary_directories() {
  DIR="$1"
  [[ "$DIR" == *"#recycle"* || "$DIR" == *@eaDir* || "$DIR" == *.snapshots* ]]
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
    REL_PATH="${FILE#$DIR/}"           # Relative path to maintain structure
    TARGET_FILE="$CACHE_DIR/$REL_PATH" # Writable cache file path
    TARGET_DIR="$(dirname "$TARGET_FILE")"

    mkdir -p "$TARGET_DIR"       # Ensure writable cache directory exists
    mv "$FILE" "$TARGET_FILE"    # Move cache file to writable location
    ln -s "$TARGET_FILE" "$FILE" # Create symbolic link at original location

    echo "$(date) - Moved $FILE to $TARGET_FILE and created symbolic link" >>"$LOG_FILE"
  done
}

# Function to move files to a temporary folder, create a subvolume, and make the subvolume immutable
move_files_to_subvolume() {
  DIR="$1"
  TEMP_DIR="${DIR}_temp_$(date +%s)"

  replace_cache_files_with_symlinks "$DIR"

  # Create temp directory to store files temporarily
  sudo mkdir -p "$TEMP_DIR"
  echo "$(date) - Created temp directory $TEMP_DIR to store files temporarily" >>"$LOG_FILE"

  # Move all files from the original directory to the temp directory, including hidden files
  sudo mv "$DIR"/{*,.[^.]*} "$TEMP_DIR" 2>/dev/null || true
  echo "$(date) - Moved files from $DIR to temp directory $TEMP_DIR" >>"$LOG_FILE"

  # Check if $DIR is a subvolume and delete it if necessary
  if is_subvolume "$DIR"; then
    echo "$(date) - $DIR is a subvolume; deleting the subvolume before recreating" >>"$LOG_FILE"
    sudo btrfs property set "$DIR" ro false
    sudo btrfs subvolume delete "$DIR"
    if [ $? -eq 0 ]; then
      echo "$(date) - Deleted existing subvolume $DIR" >>"$LOG_FILE"
    else
      echo "$(date) - Failed to delete existing subvolume $DIR" >>"$LOG_FILE"
      return 1
    fi
  else
    # Remove the original directory to create the subvolume
    sudo rmdir "$DIR"
    if [ $? -eq 0 ]; then
      echo "$(date) - Removed original directory $DIR" >>"$LOG_FILE"
    else
      echo "$(date) - Failed to remove original directory $DIR" >>"$LOG_FILE"
      return 1
    fi
  fi

  # Create the subvolume
  sudo btrfs subvolume create "$DIR"
  if [ $? -eq 0 ]; then
    echo "$(date) - Created subvolume $DIR" >>"$LOG_FILE"
  else
    echo "$(date) - Failed to create subvolume $DIR" >>"$LOG_FILE"
    return 1
  fi

  # Move files back into the original directory (now a subvolume)
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
    echo "$(date) - Skipping special directory $DIR" >>"$LOG_FILE"
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

# Loop to monitor new directories
while true; do
  CURRENT_TIME=$(date +%s)

  # Find all .vhd files and determine their top-level backup folder
  find "$BACKUP_DIR" -type f -name "*.vhd" | while read -r VHD_FILE; do
    # Determine the top-level folder (e.g., /volume1/XCP06/folder1)
    TOP_LEVEL_BACKUP=$(echo "$VHD_FILE" | sed -E "s|^$BACKUP_DIR/([^/]+).*|\1|")
    TOP_LEVEL_BACKUP="$BACKUP_DIR/$TOP_LEVEL_BACKUP"
    # Exclude special directories like #recycle
    if [[ "$TOP_LEVEL_BACKUP" == *"#recycle"* ]]; then
      echo "$(date) - Skipping special directory $TOP_LEVEL_BACKUP" >>"$LOG_FILE"
      continue
    fi

    # Check if the top-level backup folder has already been processed
    BACKUP_STATE=$(get_backup_state "$TOP_LEVEL_BACKUP")

    if [ "$BACKUP_STATE" == "null" ]; then
      echo "$(date) - New backup detected in $TOP_LEVEL_BACKUP" >>"$LOG_FILE"
      replace_cache_files_with_symlinks "$TOP_LEVEL_BACKUP" # Handle cache files
      save_backup_state "$TOP_LEVEL_BACKUP" "$CURRENT_TIME"

      # Convert all subdirectories within the top-level folder to subvolumes
      find "$TOP_LEVEL_BACKUP" -type d -depth | while read -r SUBDIR; do
        if skip_unnecessary_directories "$SUBDIR"; then
          echo "$(date) - Skipping unnecessary subdirectory $SUBDIR" >>"$LOG_FILE"
          continue
        fi

        echo "$(date) - Processing subdirectory $SUBDIR" >>"$LOG_FILE"
        move_files_to_subvolume "$SUBDIR"
      done

      # Make the top-level directory immutable AFTER processing subdirectories
      echo "$(date) - Making top-level directory $TOP_LEVEL_BACKUP immutable" >>"$LOG_FILE"
      sudo btrfs property set "$TOP_LEVEL_BACKUP" ro true
      if [ $? -eq 0 ]; then
        echo "$(date) - Successfully made $TOP_LEVEL_BACKUP immutable" >>"$LOG_FILE"
      else
        echo "$(date) - Failed to make $TOP_LEVEL_BACKUP immutable" >>"$LOG_FILE"
      fi

    else
      BACKUP_STATE_INT=$((BACKUP_STATE))
      if [ $(($CURRENT_TIME - $BACKUP_STATE_INT)) -ge $IMMU_DURATION ]; then
        lift_immutability "$TOP_LEVEL_BACKUP"
        jq --arg dir "$TOP_LEVEL_BACKUP" 'del(.[$dir])' "$BACKUP_STATE_FILE" >tmp.json && mv tmp.json "$BACKUP_STATE_FILE"
        echo "$(date) - Lifted immutability for $TOP_LEVEL_BACKUP" >>"$LOG_FILE"
      else
        echo "$(date) - $TOP_LEVEL_BACKUP still within immutability period" >>"$LOG_FILE"
      fi
    fi
  done

  sleep 60
done

