#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./deploy_harness.sh <image> <host_ip>)"
  exit 1
fi

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <image.img> <host_ip>"
  exit 1
fi

IMAGE=$1
HOST_IP=$2
MNT_DIR="/tmp/rpi_mnt"
TFTP_DIR="/srv/tftp"
NFS_DIR="/srv/nfs/rpi5_test"

mkdir -p "$MNT_DIR/boot"
mkdir -p "$MNT_DIR/root"
mkdir -p "$NFS_DIR"

echo "Mapping image partitions..."
LOOP_DEV=$(losetup --show -f -P "$IMAGE")
kpartx -av "$LOOP_DEV"

# Determine partitions (assuming p1 is boot, p2 is root)
LOOP_BASE=$(basename "$LOOP_DEV")
BOOT_PART="/dev/mapper/${LOOP_BASE}p1"
ROOT_PART="/dev/mapper/${LOOP_BASE}p2"

echo "Waiting for partition devices..."
sleep 2

echo "Mounting partitions..."
mount "$BOOT_PART" "$MNT_DIR/boot"
mount "$ROOT_PART" "$MNT_DIR/root"

echo "Copying boot files to TFTP..."
rm -rf "$TFTP_DIR"/*
cp -r "$MNT_DIR/boot"/* "$TFTP_DIR/"

echo "Copying root filesystem to NFS..."
rsync -a --delete "$MNT_DIR/root/" "$NFS_DIR/"

echo "Patching cmdline.txt..."
CMDLINE_FILE="$TFTP_DIR/cmdline.txt"
if [ -f "$CMDLINE_FILE" ]; then
  # Replace root=... with NFS root and ip=dhcp
  sed -i 's/root=[^ ]*/root=\/dev\/nfs nfsroot='"$HOST_IP"':\/srv\/nfs\/rpi5_test,vers=3 rw ip=dhcp/' "$CMDLINE_FILE"
  # Optional: ensure rootwait is present
  if ! grep -q "rootwait" "$CMDLINE_FILE"; then
    sed -i '1 s/$/ rootwait/' "$CMDLINE_FILE"
  fi
  # Clean up trailing newlines
  tr -d '\n' < "$CMDLINE_FILE" > "${CMDLINE_FILE}.tmp"
  mv "${CMDLINE_FILE}.tmp" "$CMDLINE_FILE"
else
  echo "Warning: cmdline.txt not found in boot partition!"
fi

echo "Patching fstab..."
FSTAB_FILE="$NFS_DIR/etc/fstab"
if [ -f "$FSTAB_FILE" ]; then
  # Comment out the /boot and / mounts
  sed -i 's/^.*\/boot.*$/#\0/' "$FSTAB_FILE"
  sed -i 's/^.*\/ .*ext4.*$/#\0/' "$FSTAB_FILE"
else
  echo "Warning: fstab not found in root partition!"
fi

echo "Unmounting and cleaning up..."
umount "$MNT_DIR/boot"
umount "$MNT_DIR/root"
kpartx -d "$LOOP_DEV"
losetup -d "$LOOP_DEV"

echo "Deployment complete."
echo "You can now network boot the Raspberry Pi 5."
