#!/usr/bin/env bash
set -euo pipefail

########################################
# Defaults
########################################

MOVIE_DIR="/media"          # default; can be overridden with --dir
METADATA_HELPER="/opt/ripper/disc_metadata.py"

DRY_RUN=false

########################################
# Parse arguments
#   -n | --dry-run       : don't actually rename, just show what would happen
#   -d | --dir <path>    : override movie directory
########################################

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -n, --dry-run          Show what would be renamed, but don't change anything
  -d, --dir <path>       Movie directory to scan (default: $MOVIE_DIR)

Example:
  $(basename "$0") --dry-run
  $(basename "$0") --dir /mnt/media/movies
  $(basename "$0") -n -d /srv/jellyfin/movies
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -d|--dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: --dir requires a path argument" >&2
        usage
        exit 1
      fi
      MOVIE_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

########################################
# Sanity checks
########################################

if [[ ! -x "$METADATA_HELPER" ]]; then
  echo "Metadata helper not found or not executable: $METADATA_HELPER" >&2
  exit 1
fi

if [[ ! -d "$MOVIE_DIR" ]]; then
  echo "Movie directory does not exist: $MOVIE_DIR" >&2
  exit 1
fi

shopt -s nullglob

echo "[*] Scanning $MOVIE_DIR for .mkv files..."
MOVIES=( "$MOVIE_DIR"/*.mkv )

if [[ ${#MOVIES[@]} -eq 0 ]]; then
  echo "No .mkv files found in $MOVIE_DIR"
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "[*] DRY RUN mode enabled - no files will be renamed."
fi

########################################
# Main loop
########################################

for FULLPATH in "${MOVIES[@]}"; do
  BASENAME="$(basename "$FULLPATH")"
  NAME_NO_EXT="${BASENAME%.mkv}"

  echo
  echo "--------------------------------------------"
  echo "Current file: $BASENAME"

  # ✅ Skip files that already look canonical:
  #    Anything like: "Something (2002)"
  #    Works for "The_New_Guy (2002)" OR "The New Guy (2002)"
  if [[ "$NAME_NO_EXT" =~ ^.+\ \([0-9]{4}\)$ ]]; then
    echo "Already in canonical pattern 'Title (YYYY)'; skipping."
    continue
  fi

  # Try to guess title/year from existing name:
  # e.g. "The_New_Guy (2002)" -> title="The New Guy", year="2002"
  GUESSED_TITLE="$NAME_NO_EXT"
  GUESSED_YEAR=""

  if [[ "$NAME_NO_EXT" =~ ^(.*)\ \(([0-9]{4})\)$ ]]; then
    GUESSED_TITLE="${BASH_REMATCH[1]}"
    GUESSED_YEAR="${BASH_REMATCH[2]}"
  fi

  # Replace underscores with spaces in guessed title
  GUESSED_TITLE="${GUESSED_TITLE//_/ }"

  echo "Guessed title: ${GUESSED_TITLE}"
  [[ -n "$GUESSED_YEAR" ]] && echo "Guessed year:  ${GUESSED_YEAR}"

  echo
  read -r -p "Enter movie title [${GUESSED_TITLE}]: " USER_TITLE
  if [[ -z "$USER_TITLE" ]]; then
    USER_TITLE="$GUESSED_TITLE"
  fi

  read -r -p "Enter release year [${GUESSED_YEAR}]: " USER_YEAR
  if [[ -z "$USER_YEAR" ]]; then
    USER_YEAR="$GUESSED_YEAR"
  fi

  if [[ -z "$USER_TITLE" ]]; then
    echo "No title provided; skipping."
    continue
  fi

  echo "[*] Querying OMDb via helper..."
  if [[ -n "$USER_YEAR" ]]; then
    NEW_BASE=$("$METADATA_HELPER" "$USER_TITLE" "$USER_YEAR")
  else
    NEW_BASE=$("$METADATA_HELPER" "$USER_TITLE")
  fi

  NEW_NAME="${NEW_BASE}.mkv"
  NEW_PATH="${MOVIE_DIR}/${NEW_NAME}"

  echo "Proposed new name:"
  echo "  $BASENAME"
  echo "    -> $NEW_NAME"

  if [[ "$FULLPATH" == "$NEW_PATH" ]]; then
    echo "Names are identical; skipping rename."
    continue
  fi

  read -r -p "Rename this file? [y/N]: " CONFIRM
  case "$CONFIRM" in
    y|Y|yes|YES)
      if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would rename:"
        echo "  '$FULLPATH'"
        echo "    -> '$NEW_PATH'"
      else
        echo "Renaming..."
        mv -v -- "$FULLPATH" "$NEW_PATH"
      fi
      ;;
    *)
      echo "Skipping."
      ;;
  esac
    esac

done

echo
echo "[+] Done processing existing movies in $MOVIE_DIR."
