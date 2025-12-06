# MuxMaster (Simplified Fork)

**A fast video remuxing tool** focused on passthrough and minimal transcoding for large media libraries.

This is a simplified fork of [MuxMaster](https://github.com/theBluWiz/muxmaster) optimized for:
- **Video passthrough** for H.264/H.265 (no re-encoding)
- **NVENC hardware encoding** for other codecs
- **AAC audio** with stereo fallback
- **English text subtitles** as external SRT sidecar files
- **Batch processing** with parallel workers

## Table of Contents
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Batch Processing](#batch)
- [Configuration](#config)
- [License](#license)

## Features <a id="features"></a>

- **Video Passthrough** – H.264 and H.265 sources are copied without re-encoding
- **NVENC Transcoding** – Other codecs (VP9, AV1, ProRes) transcoded via GPU
- **AAC Audio** – All audio output as AAC (384k surround, 192k stereo fallback)
- **Subtitle Extraction** – English text subtitles extracted to external SRT sidecar files
- **Parallel Processing** – `muxm-pipeline` processes directories with caching and parallel workers
- **Auto Thread Detection** – Optimizes CPU usage automatically
- **HDR Preservation** – Maintains HDR10/HLG metadata on passthrough
- **Dry-Run Mode** – Test workflows without writing files

---

## Installation <a id="installation"></a>

### Automated Install (Recommended)

```bash
# Clone the repository
git clone https://github.com/your-repo/muxmaster-fork.git
cd muxmaster-fork

# Run the installer
./install.sh
```

The installer will:
- Detect your OS (Ubuntu/Debian, Fedora/RHEL, Arch Linux)
- Install ffmpeg, ffprobe, and optional dependencies
- Detect your GPU and offer to install NVENC/VAAPI drivers
- Optionally install scripts to `/usr/local/bin` for system-wide access

### Manual Installation

If you prefer manual setup:

```bash
# Ubuntu/Debian
sudo apt install ffmpeg pciutils

# For NVENC support, ensure NVIDIA drivers are installed
# ffmpeg must be compiled with --enable-nvenc

# Make scripts executable
chmod +x muxm muxm-pipeline muxm-batch

# Install to PATH (optional)
sudo cp muxm muxm-pipeline muxm-batch /usr/local/bin/
```

## Usage <a id="usage"></a>

### Single File

```bash
# Basic usage (passthrough H.264/H.265)
muxm input.mkv output.mp4

# Dry run
muxm --dry-run input.mkv output.mp4

# Force CPU encoding (disable NVENC)
muxm --no-nvenc input.mkv output.mp4

# Adjust NVENC quality
muxm --nvenc-preset p6 --nvenc-cq 20 input.mkv output.mp4
```

### Key Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Simulate without writing output |
| `--nvenc` / `--no-nvenc` | Enable/disable NVENC hardware encoding |
| `--nvenc-preset p1-p7` | NVENC quality preset (default: p4) |
| `--nvenc-cq 0-51` | NVENC constant quality (default: 23) |
| `--aac-surround-5-1 RATE` | 5.1 AAC bitrate (default: 384k) |
| `--aac-surround-7-1 RATE` | 7.1 AAC bitrate (default: 448k) |
| `--stereo-bitrate RATE` | Stereo fallback bitrate (default: 192k) |
| `--threads N` | Override thread count |

## Batch Processing <a id="batch"></a>

### muxm-pipeline (Recommended)

High-performance batch processing with local caching, ideal for NFS sources:

```bash
# Process all videos in a directory
muxm-pipeline /media/movies

# Output to different location
muxm-pipeline /media/source /media/converted

# Custom worker count
muxm-pipeline -w 4 /media/movies

# With filebot renaming (movies)
muxm-pipeline --filebot --filebot-db TheMovieDB /media/movies

# With filebot renaming (TV shows)
muxm-pipeline --filebot --filebot-db TheMovieDB::TV /media/tv

# Delete originals after successful conversion (careful!)
muxm-pipeline --delete-original /media/movies

# Dry run to preview
muxm-pipeline --dry-run /media/movies
```

### Pipeline Flags

| Flag | Description |
|------|-------------|
| `-w, --workers N` | Parallel workers (default: 6) |
| `-c, --cache-dir DIR` | Local cache location (default: /var/cache/muxm) |
| `--cache-max-gb N` | Max cache size in GB (default: 1800) |
| `--prefetch N` | Files to prefetch ahead (default: 3) |
| `--format-tag` | Add codec info to filename (default: on) |
| `--no-format-tag` | Keep original filename |
| `--filebot` | Enable filebot renaming |
| `--filebot-db DB` | Filebot database (TheMovieDB, TheMovieDB::TV) |
| `--delete-original` | Delete source after success |
| `--dry-run` | List files without processing |

### muxm-batch (Legacy)

Simple parallel batch wrapper without caching:

```bash
# Process all videos in a directory (6 workers)
muxm-batch /media/movies

# Retry failed files
muxm-batch --retry ./muxm-batch-logs/failed.txt
```

| Flag | Description |
|------|-------------|
| `-w, --workers N` | Parallel workers (default: 6) |
| `-r, --recursive` | Process subdirectories (default: on) |
| `-s, --skip-existing` | Skip if output exists (default: on) |
| `-e, --extensions LIST` | File extensions (default: mkv,mp4,avi,...) |
| `--retry FILE` | Retry from failed log |
| `--dry-run` | List files without processing |

### Worker Recommendations

- **Tesla P4**: 2-3 concurrent NVENC sessions
- **Passthrough jobs**: Mostly I/O bound, can run many
- **Default 6 workers**: Balances GPU queue and parallelism

## Configuration <a id="config"></a>

Configuration files are loaded in order (later overrides earlier):

1. `/etc/.muxmrc` – System-wide
2. `~/.muxmrc` – User config
3. `./.muxmrc` – Project-local
4. CLI flags – Always highest priority

### Example .muxmrc

```bash
# NVENC settings
USE_NVENC=1
NVENC_PRESET=p4
NVENC_CQ=23

# Audio
AAC_SURROUND_BITRATE_5_1=384k
AAC_SURROUND_BITRATE_7_1=448k
STEREO_BITRATE=192k
ADD_STEREO_IF_MULTICH=1

# Threading
AUTO_THREADS=1
```

## License <a id="license"></a>

MuxMaster is freeware for personal, non-commercial use.
Any business, government, or organizational use requires a paid license.

Based on [MuxMaster](https://github.com/theBluWiz/muxmaster) by Jamey Wicklund (theBluWiz).
