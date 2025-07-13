#!/bin/bash

# Usage: ./index.sh <folder-path|yaml-file>
# Example: ./index.sh ./android
#          ./index.sh ./android/app.yaml

INPUT_PATH="$1"
CONTINUE_MODE=false
CONTINUE_FILE=""

# Check for --continue flag
if [ "$1" == "--continue" ]; then
  CONTINUE_MODE=true
  CONTINUE_FILE="$2"
  INPUT_PATH="$2"
fi

if [ -z "$INPUT_PATH" ]; then
  echo "Usage: $0 [--continue] <folder-path|yaml-file>" >&2
  echo "Example: $0 ./android" >&2
  echo "         $0 ./android/app.yaml" >&2
  echo "         $0 --continue ./android/app.yaml" >&2
  exit 1
fi

if [ -f "$INPUT_PATH" ] && [[ "$INPUT_PATH" =~ \.(yaml|yml)$ ]]; then
  # Single YAML file
  FILES_TO_PROCESS=("$INPUT_PATH")
elif [ -d "$INPUT_PATH" ]; then
  # Directory: find all YAML files
  mapfile -t FILES_TO_PROCESS < <(find "$INPUT_PATH" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)
else
  echo "Error: '$INPUT_PATH' is not a valid directory or YAML file" >&2
  exit 1
fi

# If --continue is set and a YAML file is given, filter FILES_TO_PROCESS
if [ "$CONTINUE_MODE" = true ] && [ -f "$CONTINUE_FILE" ]; then
  CONTINUE_BASENAME=$(basename "$CONTINUE_FILE")
  FILTERED_FILES=()
  for f in "${FILES_TO_PROCESS[@]}"; do
    if [[ $(basename "$f") > "$CONTINUE_BASENAME" || $(basename "$f") == "$CONTINUE_BASENAME" ]]; then
      FILTERED_FILES+=("$f")
    fi
  done
  FILES_TO_PROCESS=("${FILTERED_FILES[@]}")
fi

if [ ${#FILES_TO_PROCESS[@]} -eq 0 ]; then
  exit 0
fi

# For each YAML file, determine if --skip-remote-metadata should be used based on the following logic:
# - Group the alphabet a-z in pairs: (a,b)=1, (c,d)=2, ..., (y,z)=13
# - For each file, get the first letter of its name and determine its group number G
# - If today is day G or G+15 of the month, run zapstore without --skip-remote-metadata
# - On all other days, run zapstore with --skip-remote-metadata

for FILE_PATH in "${FILES_TO_PROCESS[@]}"; do
  FILENAME=$(basename "$FILE_PATH")
  echo "Processing $FILENAME"
  DAY_OF_MONTH=$(date +%d | sed 's/^0*//')
  # Get first letter, lowercase
  FIRST_LETTER=$(echo "$FILENAME" | cut -c1 | tr '[:upper:]' '[:lower:]')
  # Calculate group: (a,b)=1, (c,d)=2, ..., (y,z)=13
  case "$FIRST_LETTER" in
    a|b) GROUP=1 ;;
    c|d) GROUP=2 ;;
    e|f) GROUP=3 ;;
    g|h) GROUP=4 ;;
    i|j) GROUP=5 ;;
    k|l) GROUP=6 ;;
    m|n) GROUP=7 ;;
    o|p) GROUP=8 ;;
    q|r) GROUP=9 ;;
    s|t) GROUP=10 ;;
    u|v) GROUP=11 ;;
    w|x) GROUP=12 ;;
    y|z) GROUP=13 ;;
    *) GROUP=0 ;;
  esac
  # Decide whether to skip remote metadata
  if (( DAY_OF_MONTH == GROUP || DAY_OF_MONTH == GROUP + 15 )); then
    zapstore publish -c "$FILE_PATH" -d
  else
    zapstore publish -c "$FILE_PATH" -d --skip-remote-metadata
  fi
  STATUS=$?
  if [ $STATUS -ne 0 ]; then
    echo "❌ Error processing $FILENAME:" >&2
    echo "Exit code: $STATUS" >&2
    echo "\n🛑 ABORTING: Failed to process $FILENAME" >&2
    echo "Fix the YAML file and re-run the program." >&2
    exit 1
  fi
done 