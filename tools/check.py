"""Checks a Horizon shader pack (API 0.1) as `horizon-shader check` does, with naga-cli.

Each stage is composed as Horizon builds it (tools/prelude, extracted from horizon-shader-api),
validated, then translated to SPIR-V, Metal and HLSL with the options at their defaults,
minimums and maximums. The manifest rules the game enforces are checked too.

Usage: python tools/check.py [pack_dir]
"""

import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent
PRELUDE = ROOT / "prelude"
MAX_TEXTURE_READS = 64
MAX_WGSL_BYTES = 256 * 1024
POST_SCALES = (1.0, 0.5, 0.25)
MAX_POST_TARGETS = 4
MAX_POST_PASSES = 8
RESERVED_TARGETS = {
    "frame", "scene_color", "scene_depth", "previous", "linear_sampler", "nearest_sampler",
    "shadow_map", "shadow_sampler", "history", "shadow_map_translucent", "shadow_color", "scene_surface",
}
OVERRIDE_TYPES = {"bool": "bool", "float": "f32", "int": "i32", "choice": "u32"}
TEXTURE_READ = re.compile(r"\btexture(?:Sample\w*|Load|Gather\w*)\s*\(")
OVERRIDE = re.compile(r"^\s*override\s+(\w+)\s*:\s*([\w<>]+)\s*(=)?", re.M)


class Pack:
    def __init__(self, root: pathlib.Path):
        self.root = root
        self.manifest = tomllib.loads((root / "horizon-shaders.toml").read_text(encoding="utf-8"))
        self.problems: list[str] = []

    def source(self, path: str) -> str:
        file = self.root / path
        if not file.is_file():
            self.problems.append(f"{path}: missing")
            return ""
        data = file.read_bytes()
        if len(data) > MAX_WGSL_BYTES:
            self.problems.append(f"{path}: over {MAX_WGSL_BYTES} bytes")
        return data.decode("utf-8")

    def stages(self) -> list[tuple[str, dict]]:
        m = self.manifest
        out = [(kind, m[kind]) for kind in ("sky", "material", "vertex", "weather") if kind in m]
        out += [("post", p) for p in m.get("post", [])]
        return out

    def textures(self) -> str:
        decls = ""
        for i, t in enumerate(self.manifest.get("textures", [])):
            decls += f"@group(3) @binding({16 + i}) var {t['id']}: texture_2d<f32>;\n"
            decls += f"@group(3) @binding({24 + i}) var {t['id']}_sampler: sampler;\n"
        return decls

    def post_targets(self) -> list[tuple[str, float]]:
        targets: list[tuple[str, float]] = []
        for p in self.manifest.get("post", []):
            if "output" in p and p["output"] not in [t[0] for t in targets]:
                targets.append((p["output"], p.get("scale", 1.0)))
        return targets

    def compose(self, kind: str, stage: dict) -> tuple[str, str]:
        """(the composed module, the pack's own part of it)."""
        prelude = (PRELUDE / f"{kind}.prelude.wgsl").read_text(encoding="utf-8") + self.textures()
        if kind == "post":
            prelude += "".join(
                f"@group(3) @binding({32 + i}) var {name}: texture_2d<f32>;\n"
                for i, (name, _) in enumerate(self.post_targets())
            )
        shared = self.manifest.get("shared", [])
        files = [s for s in shared if s != stage["file"]]
        files += [f for f in stage.get("files", []) if f != stage["file"] and f not in shared]
        files.append(stage["file"])
        if kind == "material" and "vertex" in self.manifest:
            vertex = self.manifest["vertex"]
            for extra in vertex.get("files", []) + [vertex["file"]]:
                if extra not in stage.get("files", []) and extra not in shared:
                    files.append(extra)
        own = "".join(self.source(f).rstrip("\n") + "\n" for f in files)
        entries = (PRELUDE / f"{kind}.entries.wgsl").read_text(encoding="utf-8")
        return prelude + own + entries, own


def check_manifest(pack: Pack) -> None:
    m = pack.manifest
    if m.get("api") != "0.1":
        pack.problems.append('api: this checker covers "0.1"')
    post = m.get("post", [])
    if len(post) > MAX_POST_PASSES:
        pack.problems.append(f"{len(post)} [[post]] passes; at most {MAX_POST_PASSES}")
    scales: dict[str, float] = {}
    for i, p in enumerate(post):
        scale = p.get("scale", 1.0)
        if scale not in POST_SCALES:
            pack.problems.append(f"{p['file']}: scale {scale} is not one of {POST_SCALES}")
        if i + 1 == len(post) and ("output" in p or scale != 1.0):
            pack.problems.append(f"{p['file']}: the last [[post]] pass draws the picture: no output or scale")
        name = p.get("output")
        if name is None:
            if scale != 1.0:
                pack.problems.append(f"{p['file']}: a scaled pass writes an output")
            continue
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,31}", name) or name.startswith("horizon_") or name in RESERVED_TARGETS:
            pack.problems.append(f"{p['file']}: output {name!r} is not a free WGSL name")
        if scales.setdefault(name, scale) != scale:
            pack.problems.append(f"{p['file']}: output {name!r} is written at two scales")
    if len(scales) > MAX_POST_TARGETS:
        pack.problems.append(f"{len(scales)} post outputs; at most {MAX_POST_TARGETS}")

    options = {o["id"]: o for o in m.get("options", [])}
    for o in m.get("options", []):
        if o["type"] == "choice" and o["default"] not in o["values"]:
            pack.problems.append(f"option {o['id']}: default must be one of the values")
        if o["type"] in ("float", "int") and not o["min"] <= o["default"] <= o["max"]:
            pack.problems.append(f"option {o['id']}: default out of range")
    shadow = m.get("shadow", {})
    for key in ("option", "resolution_option", "distance_option"):
        if key in shadow and shadow[key] not in options:
            pack.problems.append(f"shadow.{key}: {shadow[key]!r} is no option")
    if "reflection" in m and m["reflection"].get("option") not in options:
        pack.problems.append("reflection.option is no option")

    pages = {p["id"]: p for p in m.get("pages", [])}
    if pages:
        reached, queue, shown = set(), [m["pages"][0]["id"]], set()
        while queue:
            page = queue.pop()
            if page in reached:
                continue
            reached.add(page)
            for item in pages[page]["items"]:
                if item.startswith("page:"):
                    if item[5:] not in pages:
                        pack.problems.append(f"page {page}: no page {item[5:]!r}")
                    queue.append(item[5:])
                elif item:
                    shown.add(item)
        for o in options:
            if o not in shown:
                pack.problems.append(f"option {o} is on no page the settings reach")

    for t in m.get("textures", []):
        if not (pack.root / t["file"]).is_file():
            pack.problems.append(f"texture {t['id']}: {t['file']} missing")


def option_sets(options: list[dict]) -> dict[str, dict[str, str]]:
    def value(o: dict, which: str) -> str:
        t = o["type"]
        if t == "bool":
            return {"default": "1" if o["default"] else "0", "min": "0", "max": "1"}[which]
        if t == "choice":
            return str({"default": o["values"].index(o["default"]), "min": 0, "max": len(o["values"]) - 1}[which])
        return str(o[which if which != "default" else "default"] if which == "default" else o[which])

    return {which: {o["id"]: value(o, which) for o in options} for which in ("default", "min", "max")}


def check_stage(pack: Pack, kind: str, stage: dict, naga: str, work: pathlib.Path) -> set[str]:
    text, own = pack.compose(kind, stage)
    label = stage["file"]
    if re.search(r"@(group|binding|vertex|fragment|compute)\b", own):
        pack.problems.append(f"{label}: declares a binding or an entry point")
    for name in sorted(set(re.findall(r"\bhorizon_\w+", own))):
        pack.problems.append(f"{label}: `{name}`: names starting with horizon_ are Horizon's")
    reads = len(TEXTURE_READ.findall(text))
    if reads > MAX_TEXTURE_READS:
        pack.problems.append(f"{label}: {reads} texture reads; a stage may write {MAX_TEXTURE_READS}")

    options = {o["id"]: o for o in pack.manifest.get("options", [])}
    present = set()
    for name, ty, default in OVERRIDE.findall(own):
        present.add(name)
        if name in options and OVERRIDE_TYPES[options[name]["type"]] != ty:
            pack.problems.append(f"{label}: override {name}: {ty} should be {OVERRIDE_TYPES[options[name]['type']]}")
        if name not in options and not default:
            pack.problems.append(f"{label}: override {name} has no default and no option")

    module = work / (re.sub(r"[^A-Za-z0-9]+", "_", f"{kind}_{label}") + ".wgsl")
    module.write_text(text, encoding="utf-8", newline="\n")
    result = subprocess.run([naga, str(module)], capture_output=True, text=True)
    if result.returncode != 0:
        pack.problems.append(f"{label}: {result.stdout.strip()} {result.stderr.strip()}")
        return present
    for which, values in option_sets(pack.manifest.get("options", [])).items():
        overrides = [f"{k}={v}" for k, v in values.items() if k in present]
        for ext, extra in (("spv", []), ("metal", ["--metal-version", "2.4"]), ("hlsl", ["--shader-model", "60"])):
            out = module.with_suffix(f".{which}.{ext}")
            args = [naga, *extra]
            for override in overrides:
                args += ["--override", override]
            args += [str(module), str(out)]
            r = subprocess.run(args, capture_output=True, text=True)
            if r.returncode != 0:
                pack.problems.append(f"{label}: with the options at their {which}s, {ext} refuses it: {(r.stdout + r.stderr).strip()}")
    return present


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT.parent / "src").resolve()
    naga = shutil.which("naga")
    if not naga:
        print("naga not found: cargo install naga-cli", file=sys.stderr)
        return 2
    pack = Pack(root)
    check_manifest(pack)
    used: set[str] = set()
    with tempfile.TemporaryDirectory() as tmp:
        for kind, stage in pack.stages():
            before = len(pack.problems)
            used |= check_stage(pack, kind, stage, naga, pathlib.Path(tmp))
            print(("ok   " if len(pack.problems) == before else "FAIL ") + f"{kind:8} {stage['file']}")
    shadow = pack.manifest.get("shadow", {})
    used |= {shadow.get("resolution_option"), shadow.get("distance_option")}
    for o in pack.manifest.get("options", []):
        if o["id"] not in used:
            pack.problems.append(f"option {o['id']} is not used by any stage or in shared")
    for p in pack.problems:
        print(f"  {p}")
    return 1 if pack.problems else 0


if __name__ == "__main__":
    sys.exit(main())
