#!/bin/bash

# Usage: ./review.sh <folder-path>
# Example: ./review.sh ./android

FOLDER_PATH="$1"

if [ -z "$FOLDER_PATH" ]; then
  echo "Usage: $0 <folder-path>" >&2
  echo "Example: $0 ./android" >&2
  exit 1
fi

if [ ! -d "$FOLDER_PATH" ]; then
  echo "Error: Folder \"$FOLDER_PATH\" does not exist" >&2
  exit 1
fi

# Find all .yaml and .yml files in the folder
ALL_FILES=()
while IFS= read -r file; do
  ALL_FILES+=("$file")
done < <(find "$FOLDER_PATH" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)

if [ ${#ALL_FILES[@]} -eq 0 ]; then
  exit 0
fi

for FILE_PATH in "${ALL_FILES[@]}"; do
  FILENAME=$(basename "$FILE_PATH")
  echo "Processing $FILENAME"
  zapstore publish -c "$FILE_PATH" -d
  STATUS=$?
  if [ $STATUS -ne 0 ]; then
    echo "❌ Error processing $FILENAME:" >&2
    echo "Exit code: $STATUS" >&2
    echo "\n🛑 ABORTING: Failed to process $FILENAME" >&2
    echo "Fix the YAML file and re-run the program." >&2
    exit 1
  fi
done 