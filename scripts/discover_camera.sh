#!/bin/bash
set -u

echo "Ceyomur Camera Discovery"
echo "========================"
echo

echo "1/3 Bluetooth LE scan"
echo "Scanning for 15 seconds..."
echo

# Start a short BLE scan. Some bluetoothctl versions keep scan state globally,
# so stop scanning afterwards as well.
timeout 15s bluetoothctl scan on >/dev/null 2>&1 || true
bluetoothctl scan off >/dev/null 2>&1 || true

echo "Possible camera BLE devices:"
bluetoothctl devices | grep -Ei "HTC|CEYOMUR|Ceyomur|CY|Cam|Camera" || true

echo
echo "All known Bluetooth devices:"
bluetoothctl devices || true

echo
echo "2/3 Wi-Fi scan"
echo "Scanning wlan0 for camera access points..."
echo

sudo nmcli dev wifi rescan ifname wlan0 >/dev/null 2>&1 || true
sleep 3

echo "Possible camera Wi-Fi networks:"
nmcli -f SSID,BSSID,CHAN,SIGNAL dev wifi list ifname wlan0 | grep -Ei "CEYOMUR|HTC|CAM|Camera" || true

echo
echo "All visible Wi-Fi networks:"
nmcli -f SSID,BSSID,CHAN,SIGNAL dev wifi list ifname wlan0 || true

echo
echo "3/3 Suggested .env values"
echo

wifi_ssid="$(nmcli -t -f SSID dev wifi list ifname wlan0 2>/dev/null | grep -E '^CEYOMUR-' | head -n 1 || true)"
ble_line="$(bluetoothctl devices 2>/dev/null | grep -Ei 'HTC|CEYOMUR|Ceyomur|CY|Cam|Camera' | head -n 1 || true)"
ble_mac="$(echo "$ble_line" | awk '{print $2}')"

if [ -n "$ble_mac" ]; then
  echo "Suggested CAMERA_MAC:"
  echo "CAMERA_MAC=\"$ble_mac\""
else
  echo "No obvious BLE camera MAC found."
  echo "Tip: look for a device name such as HTC-xxxx, CEYOMUR, CY, Camera, or similar."
fi

echo

if [ -n "$wifi_ssid" ]; then
  echo "Suggested CAMERA_SSID:"
  echo "CAMERA_SSID=\"$wifi_ssid\""
else
  echo "No CEYOMUR-style Wi-Fi SSID found."
  echo "Tip: wake the camera first, then run this script again."
fi

echo
echo "Common defaults for tested Ceyomur-style cameras:"
echo 'CAMERA_PASS="12345678"'
echo 'CAMERA_IP="192.168.8.120"'
echo 'CAMERA_PATH="/DCIM/100HUNTI"'

echo
echo "Next step:"
echo "Copy the values into .env, then run:"
echo "./scripts/ceyomur_auto_upload.sh"
