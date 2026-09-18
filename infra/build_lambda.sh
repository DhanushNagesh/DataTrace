#!/usr/bin/env bash
# Builds dist/ingest.zip for the python3.13 arm64 Lambda runtime.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD=build/lambda
rm -rf "$BUILD" dist/ingest.zip
mkdir -p "$BUILD" dist

# Versions come from uv.lock so the zip matches what the tests ran against
uv export --only-group lambda --no-hashes --format requirements.txt -q -o build/requirements.txt
uv pip install -q -r build/requirements.txt --target "$BUILD" \
  --python-platform aarch64-manylinux2014 --python-version 3.13 --only-binary :all:

cp -R src/datatrace "$BUILD/"
mkdir -p "$BUILD/config"
cp config/boards.toml "$BUILD/config/"
find "$BUILD" -name __pycache__ -type d -prune -exec rm -rf {} +

(cd "$BUILD" && zip -qr -X ../../dist/ingest.zip .)
ls -lh dist/ingest.zip
