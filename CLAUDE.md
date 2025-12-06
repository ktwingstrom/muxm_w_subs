# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **simplified fork** of MuxMaster focused on fast remuxing with minimal transcoding:

- **Video**: Passthrough for H.264/H.265 (no re-encode); NVENC transcoding for other codecs
- **Audio**: AAC output only (surround + stereo fallback)
- **Subtitles**: Extract one English text subtitle as external SRT sidecar, strip all image-based
- **Output**: Always MP4 container
- **Batch**: `muxm-batch` for parallel processing of large libraries

### Key Differences from Original MuxMaster

| Feature | Original | This Fork |
|---------|----------|-----------|
| Video | Always x265 encode | Passthrough H.264/H.265, NVENC for others |
| Audio | E-AC3/AC3/AAC | AAC only |
| Subtitles | None | English text → SRT sidecar |
| Dolby Vision | Full support | Removed |
| Batch processing | None | muxm-pipeline with caching + parallel workers |

## Installation

Run `./install.sh` to automatically install dependencies and optionally add scripts to PATH:

```bash
./install.sh
```

The installer handles:
- OS detection (Ubuntu/Debian, Fedora/RHEL, Arch)
- ffmpeg, ffprobe installation
- GPU driver setup (NVIDIA NVENC, AMD/Intel VAAPI)
- Optional installation to `/usr/local/bin`

### Required Dependencies

- `ffmpeg` (with NVENC support for GPU encoding)
- `ffprobe` - Video/audio analysis
- `MP4Box` (GPAC) - Optional fallback muxer

## Running the Tools

### Single File Processing (muxm)

```bash
# Basic usage (passthrough H.264/H.265, AAC audio, SRT sidecar subs)
./muxm input.mkv output.mp4

# Dry run (simulate without writing)
./muxm --dry-run input.mkv output.mp4

# Force NVENC encoding (even for H.264/H.265)
./muxm --no-nvenc input.mkv output.mp4  # Use CPU x265 instead

# Adjust NVENC quality
./muxm --nvenc-preset p6 --nvenc-cq 20 input.mkv output.mp4
```

### Batch Processing (muxm-pipeline) - Recommended

```bash
# Process entire directory with caching
./muxm-pipeline /media/movies

# Process to different output location
./muxm-pipeline /media/source /media/converted

# With filebot renaming (movies)
./muxm-pipeline --filebot --filebot-db TheMovieDB /media/movies

# With filebot renaming (TV shows)
./muxm-pipeline --filebot --filebot-db TheMovieDB::TV /media/tv

# Delete originals after success (careful!)
./muxm-pipeline --delete-original /media/movies

# Dry run to see what would be processed
./muxm-pipeline --dry-run /media/movies
```

### Batch Processing (muxm-batch) - Legacy

```bash
# Simple parallel processing without caching
./muxm-batch /media/movies

# Retry failed files
./muxm-batch --retry ./muxm-batch-logs/failed-20250101.txt
```

## Architecture

### Scripts

- `muxm` - Main processing script (single file)
- `muxm-pipeline` - Recommended batch processor with NFS caching and filebot integration
- `muxm-batch` - Legacy parallel batch wrapper (simpler, no caching)

### Configuration Layering (lowest to highest precedence)

1. Script defaults (hardcoded in `muxm`)
2. `/etc/.muxmrc` - System-wide config
3. `~/.muxmrc` - User config
4. `./.muxmrc` - Project-local config
5. CLI flags - Always override everything

### Main Workflow Pipeline (10 steps)

1. **Video Prep** - Check if passthrough (H.264/H.265) or needs encoding
2. **Video Encode** - NVENC or x265 encoding (skipped if passthrough)
3. **Audio Detect** - Find and score audio tracks
4. **Audio Format** - Determine codec/channels
5. **Audio Prepare** - Encode/copy primary + optional stereo fallback
6. **Subtitle Select** - Find best English text subtitle, extract to SRT
7. **Primary Mux** - Combine video + audio + subtitle via ffmpeg
8. **Final Assembly** - Add stereo track if applicable
9. **Verify** - ffprobe output validation
10. **Finalize** - Atomic move to final destination

### Key Design Patterns

**Video Passthrough**: H.264 and H.265 sources are copied directly without re-encoding. Other codecs (VP9, AV1, ProRes, etc.) are transcoded to H.265 using NVENC.

**NVENC Hardware Encoding**: Uses Tesla P4 GPU for fast H.265 encoding when transcoding is required. Falls back to CPU libx265 if NVENC unavailable.

**Subtitle Handling**:
- Detects text-based (SRT, ASS, SSA, WebVTT) vs image-based (PGS, DVD)
- Selects best English text subtitle (prefers non-forced)
- Outputs as external SRT sidecar file (e.g., `movie.srt` alongside `movie.mp4`)
- Strips all image-based subtitles from output

**Audio Strategy**:
- AAC source → copy directly
- Other codecs → transcode to AAC (384k 5.1, 448k 7.1, 192k stereo)
- Always adds stereo fallback if primary is multichannel

**Thread Auto-Detection**: Automatically detects CPU thread count for optimal audio encoding parallelism.

## Important Variables

| Variable | Purpose |
|----------|---------|
| `USE_NVENC` | Enable NVENC hardware encoding (default: 1) |
| `NVENC_PRESET` | NVENC quality preset p1-p7 (default: p4) |
| `NVENC_CQ` | NVENC constant quality 0-51 (default: 23) |
| `AAC_SURROUND_BITRATE_5_1` | 5.1 AAC bitrate (default: 384k) |
| `AAC_SURROUND_BITRATE_7_1` | 7.1 AAC bitrate (default: 448k) |
| `STEREO_BITRATE` | Stereo fallback bitrate (default: 192k) |
| `ADD_STEREO_IF_MULTICH` | Create stereo fallback when primary >2ch |
| `AUTO_THREADS` | Auto-detect CPU threads (default: 1) |

## Testing Changes

```bash
# Test with dry-run first
./muxm --dry-run input.mkv output.mp4

# Keep temp files on failure for debugging
./muxm -k input.mkv output.mp4

# Keep temp files always (success or failure)
./muxm -K input.mkv output.mp4

# Batch dry run
./muxm-batch --dry-run /media/movies
```

## Code Conventions

- Helper functions prefixed with `_` are internal (e.g., `_sp_subtitle_field`, `_is_passthrough_codec`)
- User-facing output uses `say()`, `note()`, `warn()`, `die()`
- Progress marked with `mark_done()` for final summary
- All temp files go to `$WORKDIR` (auto-cleaned on success)
- Null/missing metadata handled defensively throughout
