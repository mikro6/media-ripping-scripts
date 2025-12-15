#!/usr/bin/env python3
import os
import sys
import urllib.parse
import urllib.request
import json

API_KEY = os.environ.get("OMDB_API_KEY")

def usage():
    print(
        'Usage:\n'
        '  disc_metadata.py "Movie Title" [year]\n'
        '  disc_metadata.py tt1234567\n'
        '  disc_metadata.py --imdb tt1234567',
        file=sys.stderr
    )
    sys.exit(1)

def slugify(text: str) -> str:
    slug = "".join(c if c.isalnum() or c in " -._" else " " for c in text)
    return "_".join(slug.split())

def is_imdb_id(s: str) -> bool:
    # Basic validation: tt + digits
    return s.startswith("tt") and s[2:].isdigit()

args = sys.argv[1:]
if len(args) < 1:
    usage()

imdb_id = ""
title = ""
year = ""

# Accept IMDb ID as:
#   disc_metadata.py tt1234567
#   disc_metadata.py --imdb tt1234567
if args[0] == "--imdb":
    if len(args) != 2:
        usage()
    imdb_id = args[1]
    if not is_imdb_id(imdb_id):
        print(f"Invalid IMDb ID: {imdb_id}", file=sys.stderr)
        sys.exit(1)
elif is_imdb_id(args[0]):
    imdb_id = args[0]
else:
    title = args[0]
    year = args[1] if len(args) > 1 else ""

# If no OMDb API key, fall back to slug-only behavior
if not API_KEY:
    print("OMDB_API_KEY not set; returning basic slug only.")
    if imdb_id:
        # Without an API key we can't resolve the IMDb ID; just echo it safely.
        print(slugify(imdb_id))
        sys.exit(0)

    slug_title = slugify(title)
    if year:
        print(f"{slug_title} ({year})")
    else:
        print(slug_title)
    sys.exit(0)

# Build query parameters: prefer IMDb ID if provided
params = {"apikey": API_KEY}
if imdb_id:
    params["i"] = imdb_id
else:
    params["t"] = title
    if year:
        params["y"] = year

url = "https://www.omdbapi.com/?" + urllib.parse.urlencode(params)

try:
    with urllib.request.urlopen(url) as resp:
        data = json.loads(resp.read().decode("utf-8"))
except Exception as e:
    print(f"Error querying OMDb: {e}", file=sys.stderr)
    sys.exit(1)

if data.get("Response") != "True":
    print(f"OMDb lookup failed: {data.get('Error', 'Unknown error')}", file=sys.stderr)

    # Fall back to slug of original input
    if imdb_id:
        print(slugify(imdb_id))
        sys.exit(0)

    slug_title = slugify(title)
    if year:
        print(f"{slug_title} ({year})")
    else:
        print(slug_title)
    sys.exit(0)

clean_title = data.get("Title", title)
clean_year = data.get("Year", year)

slug_title = slugify(clean_title)

# Ensure we always include a year if OMDb provides it; otherwise omit
if clean_year:
    print(f"{slug_title} ({clean_year})")
else:
    print(slug_title)
