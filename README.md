# Ceyomur Camera Auto Sync

A user-friendly Linux/Raspberry Pi automation for Ceyomur-style wildlife cameras.

Tested camera model: **Ceyomur CY95**.

It wakes the camera over Bluetooth, connects to the camera's temporary Wi-Fi, downloads photos/videos, uploads them to cloud storage with `rclone`, sends a Telegram status message, disconnects from the camera Wi-Fi, and repeats the process automatically.

## Credits and background

This project builds on the excellent groundwork from **Mike Irving's CameraExperiments** project:

https://github.com/mikeirvingweb/CameraExperiments

Mike's project documents and implements the core idea of connecting to wildlife/security cameras, including Ceyomur cameras, activating their Wi-Fi, listing files from the camera web server and downloading recordings. This repository is a Linux/Raspberry Pi focused automation wrapper around that idea, tested with the **Ceyomur CY95**, with additional shell scripts, retry logic, `rclone` upload, Telegram notifications and a simplified setup flow.

Further background from Mike Irving:

https://www.mike-irving.co.uk/web-design-blog/?blogid=122

That write-up explains the original discovery process: the Ceyomur camera exposes its own Wi-Fi network, the mobile app activates that Wi-Fi over Bluetooth, and the camera then exposes a small web server for file access.

Additional credit goes to community reverse-engineering work around BLE-controlled trail cameras.

## What this project is for

Use this if you want a small Linux device, for example a Raspberry Pi, to automatically collect images from a Ceyomur-style camera and upload them to cloud storage.

Typical use case:

```text
Camera in the field
        ↓
Raspberry Pi nearby
        ↓
BLE wake-up
        ↓
Camera Wi-Fi connection
        ↓
Download JPG/MP4/AVI files
        ↓
rclone upload to Google Drive / OneDrive / other cloud
        ↓
Telegram notification
```

## What it does

The main script performs this cycle:

1. Checks whether the camera is already awake.
2. Wakes the camera over Bluetooth Low Energy if needed.
3. Waits for the camera Wi-Fi to appear.
4. Temporarily disconnects the normal Wi-Fi if needed.
5. Connects the Linux host to the camera Wi-Fi.
6. Downloads new photos/videos from the camera HTTP file server.
7. Uploads the local archive to a cloud target with `rclone`.
8. Sends a Telegram notification with success or failure details.
9. Disconnects from the camera Wi-Fi.
10. Reconnects the normal Wi-Fi if configured.
11. Repeats every 45 minutes by default.

## Tested setup

Tested with:

- **Ceyomur CY95** wildlife/trail camera
- Raspberry Pi running Debian/Raspberry Pi OS
- NetworkManager / `nmcli`
- BlueZ / `gatttool`
- `rclone`
- Ceyomur-style Wi-Fi/Bluetooth trail camera

Your camera may use different BLE handles, Wi-Fi SSID, password, IP address or file path. These values are configured in `.env`.

## Repository layout

```text
ceyomur-camera-sync/
├── .env.example
├── .gitignore
├── LICENSE
├── README.md
├── scripts/
│   ├── bluetooth_wake.sh
│   ├── ceyomur_auto_upload.sh
│   └── discover_camera.sh
└── systemd/
    └── ceyomur-sync.service
```

## Quick start

### 1. Install required tools

```bash
sudo apt update
sudo apt install -y rclone wget curl bluez wireless-tools network-manager
```

Check the tools:

```bash
which rclone
which wget
which curl
which gatttool
which nmcli
which bluetoothctl
```

If `gatttool` is missing on your distribution, install BlueZ compatibility tools or adapt the BLE wake script to another BLE client.

### 2. Copy the project to the Raspberry Pi

Example path:

```bash
/opt/ceyomur-camera-sync
```

Example clone command:

```bash
cd /opt
sudo git clone https://github.com/YOURNAME/ceyomur-camera-sync.git
sudo chown -R "$USER":"$USER" /opt/ceyomur-camera-sync
cd /opt/ceyomur-camera-sync
```

Make scripts executable:

```bash
chmod +x scripts/*.sh
```

### 3. Discover your camera values

Run:

```bash
./scripts/discover_camera.sh
```

This scans for likely Bluetooth and Wi-Fi camera values.

The output may suggest values such as:

```bash
CAMERA_MAC="AA:BB:CC:DD:EE:FF"
CAMERA_SSID="CEYOMUR-xxxxxxxxxxxx"
CAMERA_PASS="12345678"
CAMERA_IP="192.168.8.120"
CAMERA_PATH="/DCIM/100HUNTI"
```

Discovery is intentionally semi-automatic. The script shows likely values, but you copy the correct ones into `.env`. This avoids accidentally connecting to the wrong Bluetooth device or Wi-Fi network.

### 4. Create the `.env` file

```bash
cp .env.example .env
nano .env
chmod 600 .env
```

Example `.env`:

```bash
CAMERA_MAC="AA:BB:CC:DD:EE:FF"
CAMERA_SSID="CEYOMUR-xxxxxxxxxxxx"
CAMERA_PASS="12345678"
CAMERA_IP="192.168.8.120"
CAMERA_PATH="/DCIM/100HUNTI"

HOME_WIFI_NAME="YourHomeWifi"

LOCAL_DIR="/home/pi/ceyomur-downloads"
LOG_DIR="/home/pi/ceyomur-logs"

RCLONE_DEST="gdrive:Cameras/Ceyomur"

TELEGRAM_BOT_TOKEN="123456789:ABCDEF..."
TELEGRAM_CHAT_ID="123456789"

INTERVAL_SECONDS=2700
```

Do not commit `.env` to GitHub.

## Configure rclone

Run:

```bash
rclone config
```

Create a remote, for example:

```text
gdrive:
onedrive:
dropbox:
```

Test upload:

```bash
mkdir -p /tmp/ceyomur-rclone-test
echo "test $(date)" > /tmp/ceyomur-rclone-test/test.txt

rclone copy /tmp/ceyomur-rclone-test gdrive:Cameras/Ceyomur-Test --progress
rclone ls gdrive:Cameras/Ceyomur-Test
```

If this works, put the target into `.env`:

```bash
RCLONE_DEST="gdrive:Cameras/Ceyomur"
```

The script uses `rclone copy`, not `rclone sync`.

`copy` is safer for camera archives because it uploads new files but does not delete files from the cloud if local files are removed.

## Configure Telegram notifications

Create a Telegram bot with BotFather and copy the bot token.

Send a message to the bot, then get your chat ID:

```bash
curl "https://api.telegram.org/botYOUR_BOT_TOKEN/getUpdates"
```

Add both values to `.env`:

```bash
TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN"
TELEGRAM_CHAT_ID="YOUR_CHAT_ID"
```

Test Telegram:

```bash
set -a
source .env
set +a

curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=Ceyomur sync Telegram test ✅"
```

## Manual test

Start the script:

```bash
cd /opt/ceyomur-camera-sync
./scripts/ceyomur_auto_upload.sh
```

Stop it with:

```text
CTRL + C
```

Watch logs:

```bash
tail -f ~/ceyomur-logs/ceyomur-auto-upload.log
```

Expected log flow:

```text
Starting Ceyomur upload run
Wake/status check
Camera Wi-Fi connected and camera reachable
Fetch file list
Download new files locally
Upload with rclone
Upload successful
Run finished. Next run in 45 minutes.
```

## Run in the background with nohup

```bash
cd /opt/ceyomur-camera-sync
nohup ./scripts/ceyomur_auto_upload.sh > ~/ceyomur-logs/ceyomur-nohup.log 2>&1 &
```

Check if it is running:

```bash
pgrep -af "ceyomur_auto_upload"
```

Watch the log:

```bash
tail -f ~/ceyomur-logs/ceyomur-nohup.log
```

Stop it:

```bash
pkill -f ceyomur_auto_upload.sh
pkill -f bluetooth_wake.sh
pkill -f gatttool
sudo nmcli connection down "$CAMERA_SSID" || true
```

## Run with systemd

Copy the service:

```bash
sudo cp systemd/ceyomur-sync.service /etc/systemd/system/ceyomur-sync.service
```

Edit the service if your user or path differs:

```bash
sudo nano /etc/systemd/system/ceyomur-sync.service
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable ceyomur-sync.service
sudo systemctl start ceyomur-sync.service
```

Check status and logs:

```bash
systemctl status ceyomur-sync.service
journalctl -u ceyomur-sync.service -f
```

Stop:

```bash
sudo systemctl stop ceyomur-sync.service
```

## Camera file path

On the tested camera, files were stored here:

```text
/DCIM/100HUNTI/
```

They were not stored in:

```text
/DCIM/MOVIE/
/DCIM/PHOTO/
```

Check your own camera:

```bash
curl "http://192.168.8.120/"
curl "http://192.168.8.120/DCIM/"
curl "http://192.168.8.120/DCIM/100HUNTI/"
```

If your folder is different, update this in `.env`:

```bash
CAMERA_PATH="/your/camera/path"
```

## Wi-Fi behavior

Ceyomur-style cameras often create a temporary Wi-Fi network only after a BLE wake command.

If your Raspberry Pi also uses Wi-Fi for normal internet, set this in `.env`:

```bash
HOME_WIFI_NAME="YourHomeWifi"
```

The script then temporarily disables that Wi-Fi profile while it connects to the camera, and enables it again afterwards.

Using Ethernet for the Raspberry Pi is recommended.

## Security notes

Do not commit:

```text
.env
logs
downloaded photos/videos
Telegram tokens
personal Wi-Fi names
cloud remote secrets
```

Only commit `.env.example`.

## Troubleshooting

### Camera Wi-Fi does not appear

Run:

```bash
./scripts/discover_camera.sh
```

Then check manually:

```bash
sudo nmcli dev wifi rescan ifname wlan0
nmcli dev wifi list ifname wlan0
```

### Camera is connected but not reachable

Check:

```bash
nmcli dev status
ip -4 addr show wlan0
ip route
ping -c 3 192.168.8.120
```

You should see a `192.168.8.x` address on `wlan0`.

### rclone upload fails

Test rclone separately:

```bash
rclone lsd yourremote:
rclone copy /tmp/ceyomur-rclone-test yourremote:Cameras/Ceyomur-Test --progress
```

### Telegram does not send

Check your `.env` and test:

```bash
set -a
source .env
set +a

curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=Telegram test"
```

## License

MIT License.
