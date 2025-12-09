#!/usr/bin/env python3
import os
import sys
import urllib.parse
import urllib.request
import json

API_KEY = os.environ.get("OMDB_API_KEY")

if len(sys.argv) < 2:
    print("Usage: disc_metadata.py \"Movie Title\" [year]", file=sys.stderr)
    sys.exit(1)

if not API_KEY:
    print("OMDB_API_KEY not set; returning basic slug only.")
    title = sys.argv[1]
    year = sys.argv[2] if len(sys.argv) > 2 else ""
    slug_title = "".join(c if c.isalnum() or c in " -._" else " " for c in title)
    slug_title = "_".join(slug_title.split())
    if year:
        print(f"{slug_title} ({year})")
    else:
        print(slug_title)
    sys.exit(0)

title = sys.argv[1]
year = sys.argv[2] if len(sys.argv) > 2 else ""

params = {"t": title, "apikey": API_KEY}
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
    # fall back to slug of original title
    slug_title = "".join(c if c.isalnum() or c in " -._" else " " for c in title)
    slug_title = "_".join(slug_title.split())
    if year:
        print(f"{slug_title} ({year})")
    else:
        print(slug_title)
    sys.exit(0)

clean_title = data.get("Title", title)
clean_year = data.get("Year", year)

slug_title = "".join(c if c.isalnum() or c in " -._" else " " for c in clean_title)
slug_title = "_".join(slug_title.split())

print(f"{slug_title} ({clean_year})")
