#!/usr/bin/env bash
set -euo pipefail

########################################
# Config
########################################
# Logical drive index for MakeMKV (disc:0, disc:1, etc.)
# If not passed as $1, we’ll prompt.
DISC_ID="${1:-}"

# Where MakeMKV first dumps files (local fast disk/SSD)
TEMP_DIR="/mnt/ripping/incoming"

# Where final movie MKV should live
OUTPUT_DIR="/mnt/ripping/movies"

# Optional: path to the metadata helper
METADATA_HELPER="/opt/ripper/disc_metadata.py"   # adjust this path

MIN_LENGTH_SECONDS=1800   # 30 minutes - helps skip extras

########################################

mkdir -p "$TEMP_DIR" "$OUTPUT_DIR"

# Decide which physical device we're using based on DISC_ID
if [[ -z "$DISC_ID" ]]; then
  echo "Which drive do you want to use?"
  echo "  0) Internal DVD       (/dev/sr0)"
  echo "  1) USB-C DVD/Blu-ray  (/dev/sr1)"
  read -rp "Select [0/1]: " DISC_ID
fi

case "$DISC_ID" in
  0)
    DISC_ID=0
    DRIVE_DEV="/dev/sr0"
    ;;
  1)
    DISC_ID=1
    DRIVE_DEV="/dev/sr1"
    ;;
  *)
    echo "Invalid selection '$DISC_ID', defaulting to 0 (/dev/sr0)"
    DISC_ID=0
    DRIVE_DEV="/dev/sr0"
    ;;
esac

echo "[*] Using MakeMKV drive index: disc:${DISC_ID} (device: ${DRIVE_DEV})"

echo "[*] Getting disc title from MakeMKV..."
DISC_TITLE=$(makemkvcon -r info "disc:${DISC_ID}" 2>/dev/null \
  | awk -F'"' '/CINFO:2/ {print $4; exit}' || echo "unknown_disc")

if [[ -z "$DISC_TITLE" ]]; then
  DISC_TITLE="unknown_disc"
fi

echo "Detected disc title: $DISC_TITLE"

READ_ONLY=$(lsblk -no RO "$DRIVE_DEV" 2>/dev/null || echo "1")
if [[ "$READ_ONLY" != "1" ]]; then
  echo "Warning: $DRIVE_DEV does not appear as read-only; double-check the device."
fi

echo "[*] Ripping main-length titles with MakeMKV (DVD/Blu-ray)..."
makemkvcon -r --minlength="$MIN_LENGTH_SECONDS" mkv "disc:${DISC_ID}" all "$TEMP_DIR"

echo "[*] Finding largest ripped title (assuming main feature)..."
MAIN_FILE=$(ls -S "$TEMP_DIR"/*.mkv | head -n1 || true)

if [[ -z "${MAIN_FILE:-}" || ! -f "$MAIN_FILE" ]]; then
  echo "[-] No MKV files found in $TEMP_DIR; something went wrong." >&2
  exit 1
fi

FILE_SIZE_GB=$(awk "BEGIN {printf \"%.2f\", $(stat -c%s "$MAIN_FILE") / (1024*1024*1024)}")
echo "Main candidate: $MAIN_FILE (${FILE_SIZE_GB} GB)"

echo
echo "Enter movie title (blank to use '$DISC_TITLE'):"
read -r USER_TITLE
if [[ -z "$USER_TITLE" ]]; then
  USER_TITLE="$DISC_TITLE"
fi

echo "Enter release year (optional, e.g. 2012):"
read -r USER_YEAR

FINAL_BASENAME=""

if [[ -x "$METADATA_HELPER" ]]; then
  if [[ -n "$USER_YEAR" ]]; then
    FINAL_BASENAME=$("$METADATA_HELPER" "$USER_TITLE" "$USER_YEAR")
  else
    FINAL_BASENAME=$("$METADATA_HELPER" "$USER_TITLE")
  fi
else
  # Simple local slug if Python helper not present
  SLUG_TITLE=$(echo "$USER_TITLE" | tr -cd '[:alnum:]._ -')
  SLUG_TITLE="${SLUG_TITLE// /_}"
  if [[ -n "$USER_YEAR" ]]; then
    FINAL_BASENAME="${SLUG_TITLE} (${USER_YEAR})"
  else
    FINAL_BASENAME="$SLUG_TITLE"
  fi
fi

FINAL_NAME="${FINAL_BASENAME}.mkv"
FINAL_PATH="${OUTPUT_DIR}/${FINAL_NAME}"

echo "[*] Moving main feature to: $FINAL_PATH"
mv -v "$MAIN_FILE" "$FINAL_PATH"

echo "[*] Leaving any extra titles in $TEMP_DIR (trailers, bonus content, etc.)"
echo "[+] Done."
