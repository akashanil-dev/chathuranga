#!/usr/bin/env bash
set -e

SNAP_DIR="${HF_HOME:-$HOME/.cache/huggingface}/hub/models--Qwen--Qwen2-VL-2B-Instruct/snapshots/895c3a49bc3fa70a340399125c650a463535e71c"
mkdir -p "$SNAP_DIR"

echo "=== SENSE: Qwen2-VL-2B Weights Downloader ==="
echo "Ensuring shard 2/2 is complete..."
curl -4 -L -C - --retry 10 --retry-delay 3 -o "$SNAP_DIR/model-00002-of-00002.safetensors" "https://huggingface.co/Qwen/Qwen2-VL-2B-Instruct/resolve/main/model-00002-of-00002.safetensors"

echo "Ensuring shard 1/2 is complete (~3.8 GB)..."
curl -4 -L -C - --retry 10 --retry-delay 3 -o "$SNAP_DIR/model-00001-of-00002.safetensors" "https://huggingface.co/Qwen/Qwen2-VL-2B-Instruct/resolve/main/model-00001-of-00002.safetensors"

echo "All weights downloaded! Starting backend server..."
"$(dirname "$0")/venv/bin/uvicorn" main:app --host 0.0.0.0 --port 8000
