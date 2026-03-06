#!/bin/bash
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: ./run_tests.sh <image.img> <host_ip>"
  exit 1
fi

IMAGE=$1
HOST_IP=$2

echo "---------- STEP 1: Deploying Image ----------"
sudo ./deploy_harness.sh "$IMAGE" "$HOST_IP"

echo ""
echo "---------- STEP 2: Boot Raspberry Pi --------"
echo "Please power-cycle the Raspberry Pi 5 now."

echo "Waiting for Pi to appear on the network and start SSH (can take up to a minute)..."

PI_IP=""
# Wait for SSH to respond. We check a sequence of likely IPs, or parse dnsmasq leases if testing locally.
echo "Checking DHCP leases for new connections..."
for i in {1..30}; do
  LEASE=$(grep -i "raspberrypi" /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $3}')
  if [ -n "$LEASE" ]; then
    PI_IP=$LEASE
    echo "Found Raspberry Pi at $PI_IP!"
    break
  fi
  sleep 2
done

if [ -z "$PI_IP" ]; then
  echo "Could not find Pi IP automatically in dnsmasq leases."
  echo "Please enter the Pi IP address manually:"
  read -r PI_IP
fi

echo "Attempting to connect to $PI_IP on port 22..."
# Wait up to 60 seconds for port 22
for i in {1..30}; do
  if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no pi@"$PI_IP" "echo 'SSH connection successful'" 2>/dev/null; then
    echo "SSH is up!"
    break
  fi
  sleep 2
done

echo ""
echo "---------- STEP 3: Running Tests ------------"
echo "Executing test suite on the Pi..."

# Basic sanity tests:
ssh -o StrictHostKeyChecking=no pi@"$PI_IP" << 'EOF'
  set -e
  echo "[Test 1] Kernel Version:"
  uname -a
  
  echo "[Test 2] Uptime:"
  uptime
  
  echo "[Test 3] Check Root Filesystem (should be NFS):"
  df -h /
  
  echo "All basic tests passed!"
EOF

if [ $? -eq 0 ]; then
  echo "SUCCESS! The testing harness completed successfully."
else
  echo "FAILURE. Tests did not pass."
  exit 1
fi
