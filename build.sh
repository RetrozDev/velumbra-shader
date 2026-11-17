#!/usr/bin/env bash
# Usage: ./build.sh [--skip-validation]
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
src="$root/src"
prelude="$root/tools/prelude"
dist="$root/dist"

skip_validation=0
[[ "${1:-}" == "--skip-validation" ]] && skip_validation=1

version="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$src/horizon-shaders.toml" | head -n1)"
id="$(sed -n 's/^id[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$src/horizon-shaders.toml" | head -n1)"
[[ -n "$version" && -n "$id" ]] || { echo "id or version missing in horizon-shaders.toml" >&2; exit 1; }

# Each module is what Horizon compiles: its prelude, the shared files, then the stage's files.
modules=(
  "sky:sky.wgsl"
  "terrain:material.wgsl vertex.wgsl"
  "weather:weather.wgsl"
  "post:post/atmosphere.wgsl"
  "post:post/grade.wgsl"
)

if [[ $skip_validation -eq 0 ]]; then
  command -v naga >/dev/null || { echo "naga not found: cargo install naga-cli (or pass --skip-validation)" >&2; exit 1; }
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  failed=0
  for module in "${modules[@]}"; do
    prelude_name="${module%%:*}"
    files="${module#*:}"
    out="$work/$(echo "$files" | tr -c 'A-Za-z0-9\n' '_').wgsl"
    {
      cat "$prelude/base.wgsl" "$prelude/$prelude_name.wgsl" "$src/common.wgsl"
      for f in $files; do cat "$src/$f"; done
    } > "$out"
    if result="$(naga "$out" 2>&1)"; then
      echo "ok   $files"
    else
      failed=1
      echo "FAIL $files"
      echo "$result" | sed 's/^/  /'
    fi
  done
  [[ $failed -eq 0 ]] || { echo "WGSL validation failed" >&2; exit 1; }
fi

mkdir -p "$dist"
package="$dist/$id-$version.hshader"
rm -f "$package"

if command -v zip >/dev/null; then
  (cd "$src" && zip -qr "$package" .)
  (cd "$root" && zip -q "$package" LICENSE README.md)
else
  py="$(command -v python3 || command -v python)" || { echo "need zip or python" >&2; exit 1; }
  "$py" -I - "$src" "$root" "$package" <<'EOF'
import os, sys, zipfile
src, root, package = sys.argv[1:4]
with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED) as z:
    for base, _, files in os.walk(src):
        for name in sorted(files):
            path = os.path.join(base, name)
            z.write(path, os.path.relpath(path, src).replace(os.sep, "/"))
    for name in ("LICENSE", "README.md"):
        z.write(os.path.join(root, name), name)
EOF
fi
echo "built $package"
