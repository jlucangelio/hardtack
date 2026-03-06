#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo ./setup_host.sh)"
  exit 1
fi

INTERFACE=${1:-eth0}
TFTP_DIR="/srv/tftp"
NFS_DIR="/srv/nfs"

echo "Installing dependencies..."
apt-get update
apt-get install -y dnsmasq nfs-kernel-server kpartx rsync

echo "Creating directories..."
mkdir -p "$TFTP_DIR"
mkdir -p "$NFS_DIR"
chmod 777 "$TFTP_DIR"
chmod 777 "$NFS_DIR"

echo "Configuring dnsmasq..."
cat <<EOF > /etc/dnsmasq.d/pxe-rpi.conf
interface=$INTERFACE
# Disable DNS
port=0
# Enable DHCP, set range and lease time
dhcp-range=192.168.50.100,192.168.50.200,12h
# Enable TFTP
enable-tftp
tftp-root=$TFTP_DIR
pxe-service=0,"Raspberry Pi Boot"
EOF

echo "Restarting dnsmasq..."
systemctl restart dnsmasq
systemctl enable dnsmasq

echo "Configuring NFS exports..."
cat <<EOF > /etc/exports
$NFS_DIR *(rw,sync,no_subtree_check,no_root_squash)
EOF

echo "Exporting NFS and restarting server..."
exportfs -ra
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server

echo "Host setup complete. dnsmasq listening on $INTERFACE, TFTP at $TFTP_DIR, NFS at $NFS_DIR"
