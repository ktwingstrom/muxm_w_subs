#!/usr/bin/env bash
# =============================================================================
#  muxm config.sh - Interactive configuration wizard
#  Creates a .muxmrc file with your preferred settings
# =============================================================================

set -euo pipefail

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
  BOLD='\033[1m'
  DIM='\033[2m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD='' DIM='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

say()  { printf "%b\n" "$*"; }
note() { printf "%b%b%b\n" "$CYAN" "$*" "$RESET"; }
warn() { printf "%b%b%b\n" "$YELLOW" "$*" "$RESET" >&2; }
header() { printf "\n%b=== %s ===%b\n\n" "$BOLD" "$*" "$RESET"; }

# ---------- Hardware Detection ----------
detect_nvenc() {
  local encoders
  encoders=$(ffmpeg -encoders 2>&1) || true
  echo "$encoders" | grep -q "hevc_nvenc"
}

detect_vaapi() {
  local encoders
  encoders=$(ffmpeg -encoders 2>&1) || true
  echo "$encoders" | grep -q "hevc_vaapi"
}

detect_hardware() {
  note "Detecting hardware capabilities..."

  HAS_NVENC=0
  HAS_VAAPI=0

  if detect_nvenc; then
    HAS_NVENC=1
    say "  [+] NVIDIA NVENC: ${GREEN}Available${RESET}"
  else
    say "  [-] NVIDIA NVENC: Not available"
  fi

  if detect_vaapi; then
    HAS_VAAPI=1
    say "  [+] VAAPI (AMD/Intel): ${GREEN}Available${RESET}"
  else
    say "  [-] VAAPI (AMD/Intel): Not available"
  fi

  if (( !HAS_NVENC && !HAS_VAAPI )); then
    say "  [i] CPU encoding (libx265) will be used"
  fi
  echo
}

# ---------- Interactive Prompts ----------
ask_choice() {
  local prompt="$1" default="$2"
  shift 2
  local options=("$@")
  local i=1

  say "$prompt" >&2
  for opt in "${options[@]}"; do
    if [[ "$opt" == "$default" ]]; then
      printf "  %b%d)%b %s %b(default)%b\n" "$GREEN" "$i" "$RESET" "$opt" "$DIM" "$RESET" >&2
    else
      printf "  %d) %s\n" "$i" "$opt" >&2
    fi
    ((i++))
  done

  printf "Choice [1-%d, default=%s]: " "${#options[@]}" "$default" >&2
  local choice
  read -r choice

  if [[ -z "$choice" ]]; then
    echo "$default"
  elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
    echo "${options[$((choice-1))]}"
  else
    echo "$default"
  fi
}

ask_yesno() {
  local prompt="$1" default="$2"
  local hint="[Y/n]"
  [[ "$default" == "n" ]] && hint="[y/N]"

  printf "%s %s: " "$prompt" "$hint" >&2
  local ans
  read -r ans

  if [[ -z "$ans" ]]; then
    echo "$default"
  elif [[ "$ans" =~ ^[Yy] ]]; then
    echo "y"
  else
    echo "n"
  fi
}

ask_value() {
  local prompt="$1" default="$2"
  printf "%s [%s]: " "$prompt" "$default" >&2
  local val
  read -r val
  echo "${val:-$default}"
}

# ---------- Main Configuration Flow ----------
main() {
  say "${BOLD}muxm Configuration Wizard${RESET}"
  say "This will create a .muxmrc config file for muxm."
  echo

  # Check for existing config
  local config_path=""
  if [[ -f "./.muxmrc" ]]; then
    warn "Found existing ./.muxmrc"
    local overwrite
    overwrite=$(ask_yesno "Overwrite it?" "n")
    if [[ "$overwrite" != "y" ]]; then
      say "Aborted. Existing config preserved."
      exit 0
    fi
    config_path="./.muxmrc"
  else
    config_path="./.muxmrc"
  fi

  # Detect hardware
  header "Hardware Detection"
  detect_hardware

  # ---------- Encoding Settings ----------
  header "Video Encoding"

  say "H.264/H.265 sources are always copied (passthrough)."
  say "These settings apply when transcoding is needed (VP9, AV1, etc.):"
  echo

  # Hardware encoder selection
  USE_NVENC=0
  if (( HAS_NVENC )); then
    local use_hw
    use_hw=$(ask_yesno "Use NVIDIA NVENC for transcoding?" "y")
    [[ "$use_hw" == "y" ]] && USE_NVENC=1
  fi

  # Quality preset
  local quality_choice
  if (( USE_NVENC )); then
    say ""
    quality_choice=$(ask_choice "NVENC quality preset:" "p4 (balanced)" \
      "p1 (fastest)" \
      "p2" \
      "p3" \
      "p4 (balanced)" \
      "p5" \
      "p6" \
      "p7 (best quality)")
    NVENC_PRESET="${quality_choice%% *}"

    say ""
    NVENC_CQ=$(ask_value "NVENC constant quality (0-51, lower=better)" "23")
  else
    say ""
    quality_choice=$(ask_choice "CPU (x265) preset:" "slow" \
      "ultrafast" \
      "superfast" \
      "veryfast" \
      "faster" \
      "fast" \
      "medium" \
      "slow" \
      "slower" \
      "veryslow")
    PRESET_VALUE="$quality_choice"

    say ""
    CRF_VALUE=$(ask_value "CRF value (0-51, lower=better)" "18")
  fi

  # ---------- Audio Settings ----------
  header "Audio Settings"

  say "muxm outputs AAC audio. Surround tracks get a stereo fallback."
  echo

  local stereo_fb
  stereo_fb=$(ask_yesno "Add stereo fallback for surround audio?" "y")
  ADD_STEREO_IF_MULTICH=0
  [[ "$stereo_fb" == "y" ]] && ADD_STEREO_IF_MULTICH=1

  say ""
  local bitrate_choice
  bitrate_choice=$(ask_choice "Audio quality:" "Standard" \
    "Low (256k 5.1, 128k stereo)" \
    "Standard (384k 5.1, 192k stereo)" \
    "High (512k 5.1, 256k stereo)")

  case "$bitrate_choice" in
    Low*)
      AAC_SURROUND_BITRATE_5_1="256k"
      AAC_SURROUND_BITRATE_7_1="320k"
      STEREO_BITRATE="128k"
      ;;
    High*)
      AAC_SURROUND_BITRATE_5_1="512k"
      AAC_SURROUND_BITRATE_7_1="640k"
      STEREO_BITRATE="256k"
      ;;
    *)
      AAC_SURROUND_BITRATE_5_1="384k"
      AAC_SURROUND_BITRATE_7_1="448k"
      STEREO_BITRATE="192k"
      ;;
  esac

  # ---------- Subtitle Settings ----------
  header "Subtitle Settings"

  say "muxm extracts English text subtitles as SRT sidecar files."
  echo

  local skip_subs
  skip_subs=$(ask_yesno "Extract subtitles?" "y")
  SKIP_SUBS=1
  [[ "$skip_subs" == "y" ]] && SKIP_SUBS=0

  # ---------- Output Settings ----------
  header "Output Settings"

  OUTPUT_EXT=$(ask_choice "Output container:" "mp4" "mp4" "m4v" "mov")

  say ""
  local do_checksum
  do_checksum=$(ask_yesno "Generate SHA-256 checksum for output files?" "n")
  CHECKSUM=0
  [[ "$do_checksum" == "y" ]] && CHECKSUM=1

  # ---------- Pipeline Settings (muxm-pipeline) ----------
  header "Pipeline Settings (batch processing)"

  say "These settings apply when using muxm-pipeline for batch jobs."
  echo

  # Detect CPU cores for sensible default
  local cpu_cores
  cpu_cores=$(nproc 2>/dev/null || echo "4")
  local default_workers=$((cpu_cores > 8 ? 8 : cpu_cores))

  MAX_WORKERS=$(ask_value "Parallel workers" "$default_workers")

  say ""
  CACHE_DIR=$(ask_value "Local cache directory" "/var/cache/muxm")

  say ""
  CACHE_MAX_GB=$(ask_value "Max cache size (GB)" "500")

  say ""
  local del_orig
  del_orig=$(ask_yesno "Delete originals after successful conversion? (dangerous!)" "n")
  DELETE_ORIGINAL=0
  [[ "$del_orig" == "y" ]] && DELETE_ORIGINAL=1

  # ---------- Write Config ----------
  header "Writing Configuration"

  # Build the config file
  cat > "$config_path" <<EOCONFIG
# =============================================================================
#  muxm configuration - generated $(date)
# =============================================================================
# Place this file at:
#   ~/.muxmrc        (user-level, applies to all projects)
#   ./.muxmrc        (project-level, highest precedence)
#   /etc/.muxmrc     (system-wide, lowest precedence)
# =============================================================================

# ------- Video Encoding -------
# H.264/H.265 sources are copied directly (passthrough).
# These settings apply only when transcoding is needed.

USE_NVENC=${USE_NVENC}
EOCONFIG

  if (( USE_NVENC )); then
    cat >> "$config_path" <<EOCONFIG
NVENC_PRESET=${NVENC_PRESET}
NVENC_CQ=${NVENC_CQ}
EOCONFIG
  else
    cat >> "$config_path" <<EOCONFIG
PRESET_VALUE=${PRESET_VALUE}
CRF_VALUE=${CRF_VALUE}
EOCONFIG
  fi

  cat >> "$config_path" <<EOCONFIG

# ------- Audio -------
# AAC output only. Surround + optional stereo fallback.

AAC_SURROUND_BITRATE_5_1=${AAC_SURROUND_BITRATE_5_1}
AAC_SURROUND_BITRATE_7_1=${AAC_SURROUND_BITRATE_7_1}
STEREO_BITRATE=${STEREO_BITRATE}
ADD_STEREO_IF_MULTICH=${ADD_STEREO_IF_MULTICH}

# ------- Subtitles -------
# Extract English text subtitles as external SRT sidecar.

SKIP_SUBS=${SKIP_SUBS}

# ------- Output -------

OUTPUT_EXT=${OUTPUT_EXT}
CHECKSUM=${CHECKSUM}

# ------- Pipeline (muxm-pipeline) -------
# Settings for batch processing with muxm-pipeline.

MAX_WORKERS=${MAX_WORKERS}
CACHE_DIR=${CACHE_DIR}
CACHE_MAX_GB=${CACHE_MAX_GB}
DELETE_ORIGINAL=${DELETE_ORIGINAL}
EOCONFIG

  say "${GREEN}Configuration saved to: $config_path${RESET}"
  echo
  say "You can now run muxm without flags:"
  say "  ${DIM}./muxm input.mkv output.mp4${RESET}"
  echo
  say "Or use muxm-pipeline for batch processing:"
  say "  ${DIM}./muxm-pipeline /path/to/videos${RESET}"
}

main "$@"
