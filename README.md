# Ripper Scripts – Summary

A lightweight set of Bash and Python tools for ripping DVDs/Blu-rays and normalizing movie filenames.

## Scripts

- **rip_movie.sh** – Rips a movie disc using MakeMKV and outputs a clean filename in the format `Title (Year).mkv`.
- **rip_series.sh** – Rips TV episodes from a disc and names them using the format `Show.S01E01.mkv`.
- **disc_metadata.py** – Normalizes titles using OMDb when `OMDB_API_KEY` is set.
- **rename_movies_omdb.sh** – Renames existing movie files using OMDb metadata. Supports `--dry-run` and `--dir <path>`.

## Requirements

- Linux  
- MakeMKV CLI  
- Python 3  
- Optional: `OMDB_API_KEY` for improved title metadata
