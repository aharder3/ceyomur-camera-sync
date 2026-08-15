#!/bin/bash
set -u

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$BASE_DIR/.env"
LOCK_FILE="/tmp/ceyomur_auto_upload.lock"
INDEX_FILE="/tmp/ceyomur_index.html"

if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "ERROR: .env file not found: $ENV_FILE"
  exit 1
fi

CAMERA_MAC="${CAMERA_MAC:-}"
CAMERA_SSID="${CAMERA_SSID:-}"
CAMERA_PASS="${CAMERA_PASS:-12345678}"
CAMERA_IP="${CAMERA_IP:-192.168.8.120}"
CAMERA_PATH="${CAMERA_PATH:-/DCIM/100HUNTI}"

LOCAL_DIR="${LOCAL_DIR:-$HOME/ceyomur-downloads}"
LOG_DIR="${LOG_DIR:-$HOME/ceyomur-logs}"

RCLONE_DEST="${RCLONE_DEST:-}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-2700}"

WIFI_MAX_ATTEMPTS="${WIFI_MAX_ATTEMPTS:-18}"
WIFI_WAIT_SECONDS="${WIFI_WAIT_SECONDS:-10}"

mkdir -p "$LOCAL_DIR" "$LOG_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Ceyomur sync is already running. Exiting second instance."
  exit 1
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

telegram_notify() {
  local message="$1"

  if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    log "Telegram not configured. Message would be: $message"
    return 0
  fi

  curl -sS --max-time 15 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${message}" >/dev/null || {
      log "WARNING: Telegram notification failed"
      return 1
    }
}

disconnect_camera_wifi() {
  log "Disconnecting camera Wi-Fi..."
  sudo nmcli connection down "$CAMERA_SSID" >/dev/null 2>&1 || true

  if [ -n "${HOME_WIFI_NAME:-}" ]; then
    log "Re-enabling home Wi-Fi: $HOME_WIFI_NAME"
    sudo nmcli connection modify "$HOME_WIFI_NAME" connection.autoconnect yes >/dev/null 2>&1 || true
    sudo nmcli connection up "$HOME_WIFI_NAME" >/dev/null 2>&1 || true
  fi
}

prepare_wlan_for_camera() {
  if [ -n "${HOME_WIFI_NAME:-}" ]; then
    log "Temporarily disabling home Wi-Fi: $HOME_WIFI_NAME"
    sudo nmcli connection modify "$HOME_WIFI_NAME" connection.autoconnect no >/dev/null 2>&1 || true
    sudo nmcli connection down "$HOME_WIFI_NAME" >/dev/null 2>&1 || true
  fi

  sudo nmcli connection down "$CAMERA_SSID" >/dev/null 2>&1 || true
  sleep 2
}

cleanup_and_exit() {
  disconnect_camera_wifi
  log "Script stopped."
  exit 130
}

trap cleanup_and_exit INT TERM
trap disconnect_camera_wifi EXIT

camera_reachable() {
  ping -c 1 -W 2 "$CAMERA_IP" >/dev/null 2>&1
}

camera_wifi_visible() {
  sudo nmcli dev wifi rescan ifname wlan0 >/dev/null 2>&1 || true
  sleep 2
  nmcli -t -f SSID dev wifi list ifname wlan0 | grep -Fxq "$CAMERA_SSID"
}

connect_camera_wifi_with_retry() {
  log "Checking camera Wi-Fi..."

  if camera_reachable; then
    log "Camera is already reachable."
    return 0
  fi

  if nmcli -t -f DEVICE,CONNECTION dev status | grep -Fxq "wlan0:$CAMERA_SSID"; then
    log "wlan0 is already connected to $CAMERA_SSID."
    ip -4 addr show wlan0 | grep -q "192.168.8." && {
      log "wlan0 already has a camera-network IP."
      sleep 5
      if camera_reachable; then
        log "Camera is reachable."
        return 0
      fi
    }
  fi

  for attempt in $(seq 1 "$WIFI_MAX_ATTEMPTS"); do
    log "Wi-Fi connection attempt $attempt/$WIFI_MAX_ATTEMPTS"

    sudo nmcli dev wifi rescan ifname wlan0 >/dev/null 2>&1 || true
    sleep 4

    if nmcli -t -f SSID dev wifi list ifname wlan0 | grep -Fxq "$CAMERA_SSID"; then
      log "Camera Wi-Fi visible. Connecting..."

      prepare_wlan_for_camera

      if sudo nmcli dev wifi connect "$CAMERA_SSID" password "$CAMERA_PASS" ifname wlan0; then
        log "nmcli reports: connected."
      else
        log "nmcli connect returned an error. Checking status anyway..."
      fi

      log "Waiting for DHCP/IP..."
      sleep 10

      log "wlan0 status:"
      nmcli -f DEVICE,STATE,CONNECTION dev status | grep -E "DEVICE|wlan0" || true
      ip -4 addr show wlan0 || true
      ip route | grep -E "192.168.8|default" || true

      if camera_reachable; then
        log "Camera Wi-Fi connected and camera reachable."
        return 0
      fi

      if ip -4 addr show wlan0 | grep -q "192.168.8."; then
        log "wlan0 is in the camera network, but camera does not respond yet. Waiting longer..."
        sleep 10

        if camera_reachable; then
          log "Camera is now reachable."
          return 0
        fi
      fi

      log "Camera not reachable yet. Retrying..."
    else
      log "Camera Wi-Fi not visible yet."
    fi

    sleep "$WIFI_WAIT_SECONDS"
  done

  return 1
}

wake_camera_if_needed() {
  log "Checking whether camera is already awake..."

  if camera_reachable; then
    log "Camera is already awake and reachable. Skipping BLE wake."
    return 0
  fi

  if camera_wifi_visible; then
    log "Camera Wi-Fi is already visible. Skipping BLE wake."
    return 0
  fi

  log "Camera Wi-Fi not visible. Starting BLE wake..."
  "$BASE_DIR/scripts/bluetooth_wake.sh" "$CAMERA_MAC" || {
    log "WARNING: BLE wake timeout/error. Trying Wi-Fi connection anyway."
  }

  return 0
}

fail_run() {
  local reason="$1"

  log "ERROR: $reason"

  telegram_notify "❌ Ceyomur upload failed

Reason: $reason
Time: $(date '+%Y-%m-%d %H:%M:%S')"

  disconnect_camera_wifi
  return 1
}

check_required_config() {
  [ -n "$CAMERA_MAC" ] || { fail_run "CAMERA_MAC missing in .env"; return 1; }
  [ -n "$CAMERA_SSID" ] || { fail_run "CAMERA_SSID missing in .env"; return 1; }
  [ -n "$RCLONE_DEST" ] || { fail_run "RCLONE_DEST missing in .env"; return 1; }
  return 0
}

run_once() {
  log "=================================================="
  log "Starting Ceyomur upload run"

  local downloaded_count=0
  local found_count=0
  local total_local=0
  local downloaded_files=""
  local rc=0

  check_required_config || return 1

  log "1/7 Wake/status check..."
  wake_camera_if_needed

  log "2/7 Connect camera Wi-Fi or use existing connection..."
  connect_camera_wifi_with_retry || {
    fail_run "Camera Wi-Fi not found/connected after retries"
    return 1
  }

  log "3/7 Check camera at $CAMERA_IP..."
  camera_reachable || {
    fail_run "Camera not reachable at $CAMERA_IP"
    return 1
  }

  log "4/7 Fetch file list from $CAMERA_PATH..."
  curl -s --max-time 20 "http://$CAMERA_IP$CAMERA_PATH/" > "$INDEX_FILE" || {
    fail_run "Could not fetch camera file list"
    return 1
  }

  FILES=$(grep -oP 'href="\K/[^"?]+\.(JPG|JPEG|MP4|MOV|AVI|jpg|jpeg|mp4|mov|avi)' "$INDEX_FILE" | sort -u || true)

  if [ -z "$FILES" ]; then
    found_count=0
    log "No photos/videos found."
  else
    found_count=$(echo "$FILES" | grep -c . || true)
    log "Found files: $found_count"

    log "5/7 Download new files locally..."

    while read -r file; do
      [ -z "$file" ] && continue

      filename="$(basename "$file")"

      if [ -f "$LOCAL_DIR/$filename" ]; then
        log "Already local: $filename"
      else
        log "Downloading: $filename"

        if wget -q -nc -P "$LOCAL_DIR" "http://$CAMERA_IP$file"; then
          downloaded_count=$((downloaded_count + 1))
          downloaded_files="${downloaded_files}${filename}
"
        else
          log "WARNING: Download failed: $filename"
        fi
      fi
    done <<< "$FILES"
  fi

  total_local=$(find "$LOCAL_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" \) | wc -l)

  log "6/7 Upload with rclone: $RCLONE_DEST"

  rclone copy "$LOCAL_DIR" "$RCLONE_DEST" \
    --progress \
    --transfers 4 \
    --checkers 8 \
    --log-file "$LOG_DIR/rclone-upload.log" \
    --log-level INFO

  rc=$?

  log "7/7 Disconnect camera Wi-Fi..."
  disconnect_camera_wifi

  if [ $rc -eq 0 ]; then
    log "Upload successful."

    if [ "$downloaded_count" -gt 0 ]; then
      telegram_notify "✅ Ceyomur upload successful

New photos/videos: $downloaded_count
Found on camera: $found_count
Local total: $total_local
Target: $RCLONE_DEST
Time: $(date '+%Y-%m-%d %H:%M:%S')

New files:
$downloaded_files"
    else
      telegram_notify "✅ Ceyomur upload successful

New photos/videos: 0
Found on camera: $found_count
Local total: $total_local
Target: $RCLONE_DEST
Time: $(date '+%Y-%m-%d %H:%M:%S')"
    fi

    log "Run finished. Next run in $((INTERVAL_SECONDS / 60)) minutes."
    return 0
  else
    telegram_notify "❌ Ceyomur rclone upload failed

rclone error code: $rc
New local files: $downloaded_count
Found on camera: $found_count
Target: $RCLONE_DEST
Time: $(date '+%Y-%m-%d %H:%M:%S')

Log:
$LOG_DIR/rclone-upload.log"

    log "ERROR: rclone upload returned code $rc"
    log "Next retry in $((INTERVAL_SECONDS / 60)) minutes."
    return $rc
  fi
}

while true; do
  run_once 2>&1 | tee -a "$LOG_DIR/ceyomur-auto-upload.log"
  sleep "$INTERVAL_SECONDS"
done
