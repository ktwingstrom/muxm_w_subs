# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MuxMaster (`muxm`) is a Bash video repacking/encoding utility optimized for Apple TV Direct Play. It handles HDR10, Dolby Vision, HLG, and SDR content while preserving metadata and providing smart audio track selection.

## Required Dependencies

- `ffmpeg` / `ffprobe` - Video/audio encoding and analysis
- `MP4Box` (GPAC) - MP4 muxing with proper interleaving
- `dovi_tool` >= 2.0 - Dolby Vision RPU extraction and injection

## Running the Tool

```bash
# Basic usage
./muxm input.mkv output.mp4

# Dry run (simulate without writing)
./muxm --dry-run input.mkv output.mp4

# Parallel audio encoding
./muxm -j input.mkv output.mp4

# Install to ~/.bin with config
./muxm --install

# Print effective configuration
./muxm --print-effective-config

# Write current config to file
./muxm --config [PATH]
```

## Architecture

### Single-File Design
The entire tool is a single Bash script (`muxm`) with no external script dependencies. All functions, configuration handling, and workflow logic are self-contained.

### Configuration Layering (lowest to highest precedence)
1. Script defaults (hardcoded in `muxm`)
2. `/etc/.muxmrc` - System-wide config
3. `~/.muxmrc` - User config
4. `./.muxmrc` - Project-local config
5. CLI flags - Always override everything

### Main Workflow Pipeline (15 steps)
1. **Demux** - Extract raw elementary stream (Annex-B for DV)
2. **RPU Extract** - Extract Dolby Vision RPU (if DV detected)
3. Reserved
4. **Video Encode** - x265 encode with color space preservation
5. **DV Inject** - Inject RPU or convert P7→P8.1 if needed
6. **Audio Detect** - Find and score audio tracks
7. **Audio Format** - Determine output format and containers
8-9. **Audio Prepare** - Encode primary + optional stereo fallback
10. **Primary Mux** - Combine video + primary audio via MP4Box
11. **Final Assembly** - Add stereo track if applicable
12. **DV Note** - Log DV presence status
13. **Verify** - ffprobe output validation
14. **Size Report** - Display output file size
15. **Finalize** - Atomic move to final destination (in EXIT trap)

### Key Design Patterns

**Error Handling**: Uses `set -eEuo pipefail` with custom traps for ERR, INT, TERM, and EXIT. The `die()` function handles fatal errors with exit codes.

**Audio Selection Algorithm**: Scores tracks based on codec preference, channel count, surround bonus, and language preference. Configurable via `AUDIO_SCORE_*` variables.

**DV Fallback Strategy**: Attempts direct RPU injection first, then P7→P8.1 conversion if that fails, then falls back to non-DV if `ALLOW_DV_FALLBACK=1`.

**Color Space Detection**: Auto-detects HLG (`arib-std-b67`), HDR10 (`bt2020`/`smpte2084`), or SDR and sets appropriate x265 parameters and container metadata.

## Important Variables

| Variable | Purpose |
|----------|---------|
| `CRF_VALUE` | x265 quality (default: 18) |
| `PRESET_VALUE` | x265 speed/quality trade-off (default: slower) |
| `X265_PARAMS_BASE` | Base x265 tuning string |
| `STEREO_BITRATE` | AAC stereo fallback bitrate (default: 192k) |
| `ADD_STEREO_IF_MULTICH` | Create stereo fallback when primary >2ch |
| `ALLOW_DV_FALLBACK` | Continue without DV on injection failure |
| `DV_CONVERT_TO_P81_IF_FAIL` | Attempt P7→P8.1 RPU conversion |

## Testing Changes

```bash
# Test with dry-run first
./muxm --dry-run input.mkv output.mp4

# Keep temp files on failure for debugging
./muxm -k input.mkv output.mp4

# Keep temp files always (success or failure)
./muxm -K input.mkv output.mp4

# Enable debug mode (shows all commands)
DEBUG=1 ./muxm input.mkv output.mp4
```

## Code Conventions

- Helper functions prefixed with `_` are internal (e.g., `_probe_field`, `_muxm_codec_rank`)
- User-facing output uses `say()`, `note()`, `warn()`, `die()`
- Progress marked with `mark_done()` for final summary
- All temp files go to `$WORKDIR` (auto-cleaned on success)
