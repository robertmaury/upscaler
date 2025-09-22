#!/usr/bin/env bash
set -euo pipefail

# Default image name
IMAGE_NAME="vapoursynth"
# Tag with current date
TAG=$(date +%Y_%m_%d)

# Build and tag the image
docker build -t "${IMAGE_NAME}:latest" -t "${IMAGE_NAME}:${TAG}" .

echo "Image built and tagged as:"
echo "  ${IMAGE_NAME}:latest"
echo "  ${IMAGE_NAME}:${TAG}"