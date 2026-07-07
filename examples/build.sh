#!/usr/bin/env bash
# Build a Python-with-dependencies image and pre-build its ForgeVM rootfs.
# RUN THIS ON THE FORGEVM HOST (ssh in first):
#   ssh -i ../forgevm-ssh-key.pem ec2-user@<ip>
#   cd examples && ./build.sh
#
# Usage: ./build.sh [image-tag]   (default: forgevm-python:latest)
set -euo pipefail

IMAGE_TAG="${1:-forgevm-python:latest}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Building Docker image: $IMAGE_TAG"
sudo docker build -t "$IMAGE_TAG" "$HERE"

echo "==> Pre-building ForgeVM rootfs for: $IMAGE_TAG"
# Caches an ext4 rootfs under the ForgeVM data dir; first build is slow, then
# spawns are fast (snapshot restore).
sudo forgevm build-image "$IMAGE_TAG"

echo "==> Done. Spawn sandboxes with image=\"$IMAGE_TAG\"."
echo "    From your Mac:  IMAGE=$IMAGE_TAG FORGEVM_URL=http://<ip>:7423 python3 run.py"
