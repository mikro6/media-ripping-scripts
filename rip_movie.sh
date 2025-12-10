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
# Auto-encode config
########################################

# Threshold in GB — if final file exceeds this, encode
MAX_SIZE_GB=3

# Enable/disable auto-encoding
ENABLE_AUTO_ENCODE=1

# Path to HandBrakeCLI
HANDBRAKE_CLI="/usr/bin/HandBrakeCLI"

# Custom HandBrake quality settings (overrides preset)
ENCODER="nvenc_h264"
QUALITY=22

# Audio copy behavior
AENCODERS="copy:ac3,copy:dts,copy:eac3,copy:truehd,copy:dtshd,av_aac"
AUDIO_COPY_MASK="ac3,dts,eac3,truehd,dtshd"
AUDIO_FALLBACK="av_aac"

# Subtitle behavior
KEEP_ALL_SUBTITLES=1

# Additional features
INCLUDE_MARKERS=1   # 1 = enable --markers

MAX_SIZE_BYTES=$((MAX_SIZE_GB * 1024 * 1024 * 1024))
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

########################################
# Auto-encode step
########################################
if [[ "$ENABLE_AUTO_ENCODE" -eq 1 ]]; then
  if [[ ! -x "$HANDBRAKE_CLI" ]]; then
    echo "[-] Auto-encode enabled but HandBrakeCLI not found/executable at '$HANDBRAKE_CLI'. Skipping encode." >&2
  else
    SIZE_BYTES=$(stat -c%s "$FINAL_PATH")
    FILE_SIZE_GB_HUMAN=$(awk "BEGIN {printf \"%.2f\", $SIZE_BYTES / (1024*1024*1024)}")
    echo "[*] Final file size: ${FILE_SIZE_GB_HUMAN} GB (threshold: ${MAX_SIZE_GB} GB)"

    if (( SIZE_BYTES > MAX_SIZE_BYTES )); then
      echo "[*] File is larger than ${MAX_SIZE_GB}GB. Starting encode with HandBrakeCLI..."

      # These MUST be set before we reference them anywhere (for set -u)
      ENCODED_PATH="${FINAL_PATH%.mkv}.encoded.mkv"
      SOURCE_BACKUP="${FINAL_PATH%.mkv}.source.mkv"

      # Run HandBrakeCLI without killing the script on failure
      if ! "$HANDBRAKE_CLI" \
            -i "$FINAL_PATH" \
            -o "$ENCODED_PATH" \
            --encoder "$ENCODER" \
            --quality "$QUALITY" \
            --aencoder "$AENCODERS" \
            --audio-copy-mask "$AUDIO_COPY_MASK" \
            --audio-fallback "$AUDIO_FALLBACK" \
            --all-subtitles \
            $( [[ "$INCLUDE_MARKERS" -eq 1 ]] && echo "--markers" ); then
        echo "[-] Encoding failed; leaving original file in place." >&2
      else
        if [[ -f "$ENCODED_PATH" ]]; then
          echo "[*] Encode complete: $ENCODED_PATH"
          echo "[*] Renaming original to: $SOURCE_BACKUP"
          mv -v "$FINAL_PATH" "$SOURCE_BACKUP"
          echo "[*] Moving encoded file into final name: $FINAL_PATH"
          mv -v "$ENCODED_PATH" "$FINAL_PATH"
        else
          echo "[-] Encoding reported success but encoded file not found. Keeping original." >&2
        fi
      fi
    else
      echo "[*] File is <= ${MAX_SIZE_GB}GB. Skipping auto-encode."
    fi
  fi
fi
########################################

echo "[*] Leaving any extra titles in $TEMP_DIR (trailers, bonus content, etc.)"
echo "[+] Done."
