#!/usr/bin/env bash
# Run this ON the ForgeVM instance to verify the sandbox host is healthy.
#   ssh ec2-user@<public_ip> 'bash -s' < scripts/verify-kvm.sh
set -uo pipefail

echo "== CPU virtualization extensions (expect vmx or svm) =="
grep -Eo 'vmx|svm' /proc/cpuinfo | sort -u || echo "NONE FOUND — nested virtualization not active"
echo

echo "== /dev/kvm =="
if [ -e /dev/kvm ]; then ls -l /dev/kvm; else echo "MISSING"; fi
echo

echo "== Docker =="
systemctl is-active docker && docker --version
echo

echo "== ForgeVM data dir (expect fstype: xfs) =="
findmnt -no SOURCE,FSTYPE /var/lib/forgevm 2>/dev/null || echo "/var/lib/forgevm is not a mountpoint"
echo

echo "== ForgeVM service =="
systemctl is-active forgevm && systemctl status forgevm --no-pager -l | head -n 15
echo

echo "== ForgeVM API (localhost) =="
curl -fsS http://localhost:7423/api/v1/sandboxes && echo || echo "API not responding on localhost:7423"
