#!/usr/bin/env bash
# Usage: ./build.sh [--skip-validation]
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
src="$root/src"
dist="$root/dist"
py="$(command -v python3 || command -v python || true)"

version="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$src/horizon-shaders.toml" | head -n1)"
id="$(sed -n 's/^id[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$src/horizon-shaders.toml" | head -n1)"
[[ -n "$version" && -n "$id" ]] || { echo "id or version missing in horizon-shaders.toml" >&2; exit 1; }

if [[ "${1:-}" != "--skip-validation" ]]; then
  [[ -n "$py" ]] || { echo "python not found (or pass --skip-validation)" >&2; exit 1; }
  "$py" -I "$root/tools/check.py" "$src"
fi

mkdir -p "$dist"
package="$dist/$id-$version.hshader"
rm -f "$package"
[[ -n "$py" ]] || { echo "python is needed to write the zip" >&2; exit 1; }
"$py" -I - "$root" "$package" <<'EOF'
import pathlib, sys, zipfile
root, package = pathlib.Path(sys.argv[1]), sys.argv[2]
src = root / "src"
with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED) as z:
    for path in sorted(p for p in src.rglob("*") if p.is_file()):
        z.write(path, path.relative_to(src).as_posix())
    z.write(root / "assets" / "logo-256.png", "icon.png")
    z.write(root / "LICENSE", "LICENSE")
    z.write(root / "README.md", "README.md")
EOF
echo "built $package"
