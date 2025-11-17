#!/usr/bin/env bash
# media_menu.sh
# Menu-based media player for a directory (audio/video).
# Works with mpv, mplayer, vlc, ffplay (first available).

# ---------- Config ----------
MEDIA_DIR="${1:-.}"                 # default to current directory or pass directory as first arg
PIDFILE="/tmp/media_menu_player.pid"
PLAYER_CMD=""

# ---------- Helpers ----------
find_player() {
  for p in mpv mplayer vlc ffplay; do
    if command -v "$p" >/dev/null 2>&1; then
      PLAYER_CMD="$p"
      return 0
    fi
  done
  return 1
}

list_media_files() {
  # common audio/video extensions — adjust as needed
  find "$MEDIA_DIR" -maxdepth 1 -type f \( \
    -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.aac" \
    -o -iname "*.ogg" -o -iname "*.m4a" -o -iname "*.mp4" -o -iname "*.mkv" \
    -o -iname "*.webm" -o -iname "*.avi" \) -print0 | sort -z | xargs -0 -I{} basename "{}"
}

is_playing() {
  [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" >/dev/null 2>&1
}

start_player_bg() {
  local file="$1"
  case "$PLAYER_CMD" in
    mpv)
      setsid mpv --no-terminal --input-ipc-server=/tmp/mpv-socket --really-quiet -- "${file}" >/dev/null 2>&1 &
      ;;
    mplayer)
      setsid mplayer "${file}" >/dev/null 2>&1 &
      ;;
    vlc)
      setsid vlc --intf dummy --play-and-exit "${file}" >/dev/null 2>&1 &
      ;;
    ffplay)
      setsid ffplay -nodisp -autoexit "${file}" >/dev/null 2>&1 &
      ;;
    *)
      echo "No supported player."
      return 1
      ;;
  esac
  echo $! > "$PIDFILE"
  sleep 0.2
}

stop_player() {
  if [[ -f "$PIDFILE" ]]; then
    pid=$(cat "$PIDFILE")
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1
      sleep 0.2
      # try to clean up child processes too
      pkill -P "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$PIDFILE"
  else
    echo "No player is running."
  fi
}

show_now_playing() {
  if is_playing; then
    pid=$(cat "$PIDFILE")
    echo "Player running (PID $pid)."
    # Try to show command line of player (best effort)
    ps -o pid,cmd -p "$pid" 2>/dev/null
  else
    echo "Nothing is playing right now."
  fi
}

play_by_index() {
  local idx="$1"
  mapfile -t files < <(list_media_files)
  if [[ -z "${files[*]}" ]]; then
    echo "No media files found in $MEDIA_DIR"
    return 1
  fi
  if (( idx < 1 || idx > ${#files[@]} )); then
    echo "Invalid index."
    return 1
  fi
  local f="${files[idx-1]}"
  stop_player >/dev/null 2>&1
  echo "Playing: $f"
  start_player_bg "$MEDIA_DIR/$f"
}

play_all() {
  stop_player >/dev/null 2>&1
  echo "Playing all files in $MEDIA_DIR..."
  case "$PLAYER_CMD" in
    mpv) setsid mpv --no-terminal --really-quiet -- "${MEDIA_DIR}"/* >/dev/null 2>&1 & echo $! > "$PIDFILE" ;;
    mplayer) setsid mplayer "${MEDIA_DIR}"/* >/dev/null 2>&1 & echo $! > "$PIDFILE" ;;
    vlc) setsid vlc --intf dummy --play-and-exit "${MEDIA_DIR}"/* >/dev/null 2>&1 & echo $! > "$PIDFILE" ;;
    ffplay)
      # ffplay doesn't take multiple files well; play first only as fallback
      setsid ffplay -nodisp -autoexit "$(ls "$MEDIA_DIR" | head -n1)" >/dev/null 2>&1 & echo $! > "$PIDFILE"
      ;;
    *) echo "No supported player." ; return 1 ;;
  esac
}

shuffle_and_play() {
  stop_player >/dev/null 2>&1
  mapfile -t files < <(list_media_files)
  if [[ -z "${files[*]}" ]]; then
    echo "No media files found."
    return 1
  fi
  # shuffle
  mapfile -t shuffled < <(printf "%s\n" "${files[@]}" | shuf)
  echo "Playing shuffled playlist..."
  case "$PLAYER_CMD" in
    mpv) setsid mpv --no-terminal --really-quiet -- "${shuffled[@]/#/$MEDIA_DIR/}" >/dev/null 2>&1 & echo $! > "$PIDFILE" ;;
    mplayer) setsid mplayer "${shuffled[@]/#/$MEDIA_DIR/}" >/dev/null 2>&1 & echo $! > "$PIDFILE" ;;
    vlc) setsid vlc --intf dummy --play-and-exit "${shuffled[@]/#/$MEDIA_DIR/}" >/dev/null 2>&1 & echo $! > "$PIDFILE" ;;
    *) echo "No supported player." ; return 1 ;;
  esac
}

# ---------- Start ----------
if ! find_player; then
  echo "Error: No supported media player found. Install mpv, mplayer, vlc, or ffplay."
  exit 1
fi

while true; do
  echo "----------------------------------------"
  echo " Media Player Menu (dir: $MEDIA_DIR)"
  echo " Player detected: $PLAYER_CMD"
  echo " 1) List media files"
  echo " 2) Play file by number"
  echo " 3) Play all files"
  echo " 4) Shuffle and play"
  echo " 5) Stop playback"
  echo " 6) Show now playing"
  echo " 7) Refresh / Show file list with numbers"
  echo " 0) Exit"
  echo "----------------------------------------"
  read -rp "Choose an option: " choice
  case "$choice" in
    1)
      echo "Media files:"
      nl -w2 -s'. ' <(list_media_files)
      ;;
    2)
      echo "Select file number to play (use option 1 to see numbers):"
      nl -w2 -s'. ' <(list_media_files)
      read -rp "Enter number: " num
      play_by_index "$num"
      ;;
    3)
      play_all
      ;;
    4)
      shuffle_and_play
      ;;
    5)
      stop_player
      echo "Stopped."
      ;;
    6)
      show_now_playing
      ;;
    7)
      echo "Files:"
      nl -w2 -s'. ' <(list_media_files)
      ;;
    0)
      stop_player
      echo "Goodbye."
      exit 0
      ;;
    *)
      echo "Invalid option."
      ;;
  esac
done
