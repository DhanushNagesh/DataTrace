#!/usr/bin/env bash
# Builds a Lambda zip for the python3.13 arm64 runtime.
# Usage: infra/build_lambda.sh [ingest|db-admin]
set -euo pipefail

TARGET="${1:-ingest}"
case "$TARGET" in
  ingest)    GROUP=lambda;    EXTRA_SRC=config/boards.toml; EXTRA_DST=config; PLATFORM=aarch64-manylinux2014 ;;
  # psycopg's arm64 wheels need glibc 2.28+; the python3.13 runtime is Amazon Linux 2023 (2.34)
  db-admin)  GROUP=lambda-db; EXTRA_SRC="infra/*.sql";      EXTRA_DST=sql;    PLATFORM=aarch64-manylinux_2_28 ;;
  load)      GROUP=lambda-db; EXTRA_SRC="";                 EXTRA_DST=.;      PLATFORM=aarch64-manylinux_2_28 ;;
  *) echo "unknown target: $TARGET" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."
BUILD="build/lambda-$TARGET"
ZIP="dist/$TARGET.zip"
rm -rf "$BUILD" "$ZIP"
mkdir -p "$BUILD/$EXTRA_DST" dist

# Versions come from uv.lock so the zip matches what the tests ran against
uv export --only-group "$GROUP" --no-hashes --format requirements.txt -q -o build/requirements.txt
uv pip install -q -r build/requirements.txt --target "$BUILD" \
  --python-platform "$PLATFORM" --python-version 3.13 --only-binary :all:

cp -R src/datatrace "$BUILD/"
# shellcheck disable=SC2086
[ -n "$EXTRA_SRC" ] && cp $EXTRA_SRC "$BUILD/$EXTRA_DST/"
find "$BUILD" -name __pycache__ -type d -prune -exec rm -rf {} +

(cd "$BUILD" && zip -qr -X "../../$ZIP" .)
ls -lh "$ZIP"
