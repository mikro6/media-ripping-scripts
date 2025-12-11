#!/usr/bin/env bash
set -euo pipefail

MOVIE_SRC="/media/incoming"
MOVIE_DEST="/media/Movies"

cd "$MOVIE_SRC" || {
  echo "Source directory $MOVIE_SRC does not exist."
  exit 1
}

shopt -s nullglob

echo "Processing incoming movies from $MOVIE_SRC..."
echo

for file in *.{mkv,mp4,avi,m4v,mpg,ts}; do
    [[ -f "$file" ]] || continue

    # --- Upload completeness check (size stable over 2 seconds) ---
    size1=$(stat -c%s "$file")
    sleep 2
    size2=$(stat -c%s "$file")

    if [[ "$size1" != "$size2" ]]; then
        echo "Skipping '$file' — still being uploaded (size changing)."
        echo
        continue
    fi

    echo "Found file: $file"

    # Strip extension
    base="${file%.*}"
    ext="${file##*.}"

    title="$base"
    year=""

    # If it ends with " (YYYY)" pull out the year
    if [[ "$base" =~ ^(.*)\ \(([0-9]{4})\)$ ]]; then
        title="${BASH_REMATCH[1]}"
        year="${BASH_REMATCH[2]}"
    fi

    # Replace underscores/hyphens with spaces, tidy up spaces
    title_clean="$(echo "$title" | tr '_-' '  ')"
    title_clean="$(echo "$title_clean" | sed -E 's/ +/ /g; s/^ +//; s/ +$//')"

    # Build folder name
    if [[ -n "$year" ]]; then
        folder="${title_clean} (${year})"
    else
        folder="${title_clean}"
    fi

    dest_dir="${MOVIE_DEST}/${folder}"
    dest_file="${dest_dir}/${file}"

    echo "  Parsed title: '$title_clean'"
    [[ -n "$year" ]] && echo "  Parsed year:  '$year'"
    echo "  Destination dir : $dest_dir"
    echo "  Destination file: $dest_file"

    # Create destination folder if needed
    if [[ ! -d "$dest_dir" ]]; then
        echo "  Creating directory: $dest_dir"
        mkdir -p "$dest_dir"
    fi

    # --- Duplicate handling ---
    if [[ -e "$dest_file" ]]; then
        echo "  Duplicate detected: '$dest_file' already exists."

        if [[ -t 0 ]]; then
            # Interactive: prompt user
            echo "  What do you want to do?"
            echo "    [o] Overwrite existing with incoming"
            echo "    [k] Keep existing, discard incoming"
            echo "    [b] Keep both (rename incoming)"
            echo "    [s] Skip for now"
            read -r -p "  Choice [o/k/b/s]: " choice

            case "$choice" in
                o|O)
                    echo "  Overwriting existing file with incoming."
                    mv -f -- "$file" "$dest_file"
                    ;;

                k|K)
                    echo "  Keeping existing, removing incoming copy."
                    rm -f -- "$file"
                    ;;

                b|B)
                    ts="$(date +%Y%m%d-%H%M%S)"
                    new_name="${base}_alt_${ts}.${ext}"
                    echo "  Keeping both. Incoming will be renamed to: $new_name"
                    mv -- "$file" "$dest_dir/$new_name"
                    ;;

                s|S|*)
                    echo "  Skipping this file for now. Leaving incoming as-is."
                    # Do nothing, leave file in /media/incoming
                    ;;
            esac
        else
            # Non-interactive (cron / systemd): safe default → skip
            echo "  Non-interactive environment detected. Skipping duplicate."
        fi

        echo
        continue
    fi

    # Move the main video file (no duplicate)
    echo "  Moving video: '$file' → '$dest_dir/'"
    mv -- "$file" "$dest_dir/"

    # Move any sidecar files with same base name
    for sidecar in "${base}".*; do
        [[ "$sidecar" == "$file" ]] && continue
        [[ -e "$sidecar"     ]] || continue

        echo "  Moving sidecar: '$sidecar' → '$dest_dir/'"
        mv -- "$sidecar" "$dest_dir/"
    done

    echo
done

echo "Done processing incoming movies."