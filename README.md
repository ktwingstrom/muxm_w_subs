# MuxMaster (Simplified Fork)

**A fast video remuxing tool** focused on passthrough and minimal transcoding for large media libraries.

This is a simplified fork of [MuxMaster](https://github.com/theBluWiz/muxmaster) optimized for:
- **Video passthrough** for H.264/H.265 (no re-encoding)
- **NVENC hardware encoding** for other codecs
- **AAC audio** with stereo fallback
- **English text subtitles** embedded as mov_text
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
- **Subtitle Extraction** – English text subtitles (SRT, ASS) embedded as mov_text
- **Parallel Processing** – `muxm-batch` processes directories with multiple workers
- **Auto Thread Detection** – Optimizes CPU usage automatically
- **HDR Preservation** – Maintains HDR10/HLG metadata on passthrough
- **Dry-Run Mode** – Test workflows without writing files

---

## Installation <a id="installation"></a>

### Dependencies

```bash
# Ubuntu/Debian
sudo apt install ffmpeg gpac

# For NVENC support, ensure nvidia drivers are installed
# ffmpeg must be compiled with --enable-nvenc
```

### Install Script

```bash
# Clone the repository
git clone https://github.com/your-repo/muxmaster-fork.git
cd muxmaster-fork

# Make scripts executable
chmod +x muxm muxm-batch

# Optionally add to PATH
sudo ln -s "$(pwd)/muxm" /usr/local/bin/muxm
sudo ln -s "$(pwd)/muxm-batch" /usr/local/bin/muxm-batch
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

Process entire directories with parallel workers:

```bash
# Process all videos in a directory (6 workers)
muxm-batch /media/movies

# Output to different location
muxm-batch /media/source /media/converted

# Custom worker count
muxm-batch -w 4 /media/movies

# Only process MKV files
muxm-batch -e mkv /media/movies

# Dry run to preview
muxm-batch --dry-run /media/movies

# Retry failed files
muxm-batch --retry ./muxm-batch-logs/failed.txt
```

### Batch Flags

| Flag | Description |
|------|-------------|
| `-w, --workers N` | Parallel workers (default: 6) |
| `-r, --recursive` | Process subdirectories (default: on) |
| `-R, --no-recursive` | Only process top directory |
| `-s, --skip-existing` | Skip if output exists (default: on) |
| `-f, --force` | Overwrite existing outputs |
| `-e, --extensions LIST` | File extensions (default: mkv,mp4,avi,...) |
| `-l, --log-dir DIR` | Log directory |
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
