#!/bin/bash
set -u

MAC="${1:-}"

if [ -z "$MAC" ]; then
  echo "Usage: $0 AA:BB:CC:DD:EE:FF"
  exit 1
fi

echo "Ceyomur App-Style BLE Wake"
echo "MAC: $MAC"
echo "Enable FFEB notifications and request SD/PD/BT data"

# This sequence mirrors the mobile app style:
# - connect
# - enable notifications on FFEB CCCD handle 0x001F
# - write GETSD, GETPD, GETBT to FFE9 handle 0x0019
#
# Handles may differ on other models. Check with:
# sudo gatttool -t public -b "$MAC" --primary
# sudo gatttool -t public -b "$MAC" --characteristics --start=0x0012 --end=0xffff

{
echo "connect"
sleep 8

# Enable FFEB notifications: CCCD handle 0x001F, value 0100
echo "char-write-req 0x001F 0100"
sleep 2

# GETSD
echo "char-write-req 0x0019 4745545344"
sleep 4

# GETPD
echo "char-write-req 0x0019 4745545044"
sleep 4

# GETBT
echo "char-write-req 0x0019 4745544254"
sleep 4

echo "disconnect"
sleep 1
echo "quit"
sleep 1
} | sudo timeout 45s gatttool -t public -b "$MAC" -I || true

echo "BLE wake finished or timeout reached."
exit 0
