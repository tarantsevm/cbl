#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist}"
VERSION="${VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || echo dev)}"
BIN_DIR="$OUT_DIR/cbl-$VERSION"
ZIP_PATH="$OUT_DIR/cbl-$VERSION-linux-amd64.zip"
TAR_PATH="$OUT_DIR/cbl-$VERSION-linux-amd64.tar.gz"

if [[ -e "$BIN_DIR" ]]; then
  echo "Refusing to reuse existing package directory: $BIN_DIR (choose a fresh version/output directory)" >&2
  exit 1
fi
mkdir -p "$BIN_DIR" "$OUT_DIR"
( cd "$ROOT_DIR" && go build -trimpath -buildvcs=false -o "$BIN_DIR/cbl" ./cmd/cbl && go build -trimpath -buildvcs=false -o "$BIN_DIR/cbl-tray" ./cmd/cbl-tray )
cp "$ROOT_DIR/install.sh" "$BIN_DIR/install.sh"
cp "$ROOT_DIR/uninstall.sh" "$BIN_DIR/uninstall.sh"
python3 - "$ROOT_DIR" "$BIN_DIR" <<'PY'
from pathlib import Path
import shutil, sys
source, target = map(Path, sys.argv[1:])
for name in ('install', 'desktop'):
    shutil.copytree(source / name, target / name, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'test_*.py', '*.test.js'))
PY
cp "$ROOT_DIR/README.md" "$BIN_DIR/README.md"
cp "$ROOT_DIR/README.ru.md" "$BIN_DIR/README.ru.md"
cp "$ROOT_DIR/LICENSE" "$BIN_DIR/LICENSE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.txt" "$BIN_DIR/THIRD_PARTY_NOTICES.txt"
cp -R "$ROOT_DIR/docs" "$BIN_DIR/docs"
cp "$ROOT_DIR/Makefile" "$BIN_DIR/Makefile"
cp "$ROOT_DIR/.gitignore" "$BIN_DIR/.gitignore"
cp "$ROOT_DIR/go.mod" "$BIN_DIR/go.mod"
cp "$ROOT_DIR/go.sum" "$BIN_DIR/go.sum"
# Fixed archive metadata avoids leaking the build user's identity or file times.
( cd "$OUT_DIR" && tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner -cf - "cbl-$VERSION" | gzip -n > "$TAR_PATH" )
python3 - <<'PY' "$OUT_DIR" "$VERSION" "$ZIP_PATH"
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import sys
out = Path(sys.argv[1])
version = sys.argv[2]
zip_path = Path(sys.argv[3])
root = out / f"cbl-{version}"
with ZipFile(zip_path, 'w', ZIP_DEFLATED) as zf:
    for path in sorted(root.rglob('*')):
        if path.is_file():
            info = ZipInfo(str(path.relative_to(out)), (1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (path.stat().st_mode & 0o777) << 16
            info.compress_type = ZIP_DEFLATED
            zf.writestr(info, path.read_bytes())
print(zip_path)
PY
printf '%s\n' "$TAR_PATH"
