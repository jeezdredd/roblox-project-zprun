#!/usr/bin/env python3
"""Import a Quixel Megascans surface from the owner's Fab library as a Roblox
MaterialVariant (docs/environment/megascans.md).

    python3 tools/megascans/import_surface.py <zip or folder> --slot <name>
        [--studs-per-tile N] [--base-material Asphalt|Concrete|Ground|...]
        [--override] [--replaces TFZ_<Set>] [--pattern Regular|Organic]
        [--ao-strength 0.5] [--normal-convention opengl|directx]
        [--source-url URL] [--replace] [--no-sync]

Reads the surface's JSON (name, id, physical size, categories) and its maps by file
name suffix, in the Bridge export layout or the Fab download layout, writes
<slot>_color/normal/roughness[/metalness].png at 1024 px into assets/fab/textures/,
adds pending manifest rows for them, then runs scripts/sync_configs.py and
scripts/sync_needed.py (which also write the local src/shared/fab/MegascansMaterials.luau).
Upload with `python3 scripts/upload_assets.py --only texture/surface/megascans/`, then
sync again: the TFZ_MS_<Slot> variant appears in default.project.json once every map
has an id.

Fab content (Fab Standard License) is never committed, the repository is public:
assets/fab/ and src/shared/fab/ are gitignored, the source zip is read in place (a zip
is extracted to the system temp dir and removed) and must not sit inside the
repository outside assets/fab/.
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import surface as ms  # noqa: E402


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("source", help="the Megascans zip or extracted folder")
    parser.add_argument("--slot", required=True, help="manifest slot, lower_snake (asphalt_cracked)")
    parser.add_argument("--studs-per-tile", type=float, help="override the size read from the JSON")
    parser.add_argument("--base-material", choices=ms.BASE_MATERIALS, help="guessed from the JSON when left out")
    parser.add_argument("--override", action="store_true", help="make the variant its base material's override")
    parser.add_argument("--replaces", help="an existing set (TFZ_Asphalt) that MaterialUtil.apply should resolve to this one")
    parser.add_argument("--pattern", choices=ms.PATTERNS, default="Regular", help="MaterialPattern (Organic breaks up tiling)")
    parser.add_argument("--ao-strength", type=float, default=0.5, help="how much of the AO map darkens the colour, 0..1")
    parser.add_argument("--normal-convention", choices=("opengl", "directx"), help="force the normal map's convention")
    parser.add_argument("--source-url", dest="source_url", help="the Fab listing URL for the manifest row")
    parser.add_argument("--replace", action="store_true", help="re-import a slot that already has asset ids")
    parser.add_argument("--no-sync", action="store_true", help="do not run the two sync scripts afterwards")
    parser.add_argument("--root", default=REPO, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def check_source_location(source, root):
    """The source must not sit inside the repository, except under the gitignored
    assets/fab/, so it can never be committed by accident."""
    source = os.path.realpath(source)
    root = os.path.realpath(root)
    fab = os.path.join(root, "assets", "fab")
    inside = source == root or source.startswith(root + os.sep)
    if inside and not (source == fab or source.startswith(fab + os.sep)):
        raise ms.SurfaceError(
            f"{source} is inside the repository; keep Megascans downloads outside it (or under assets/fab/, "
            "which is gitignored)"
        )


def load_manifest(root):
    with open(os.path.join(root, "assets", "manifest.json"), encoding="utf-8") as handle:
        return json.load(handle)


def save_manifest(root, manifest):
    with open(os.path.join(root, "assets", "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def known_sets(root):
    """Set names in MaterialUtil.sets, for checking --replaces."""
    path = os.path.join(root, "src", "shared", "util", "MaterialUtil.luau")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    return set(re.findall(r'name = "(TFZ_[A-Za-z0-9]+)"', text))


def run(argv):
    args = parse_args(argv)
    root = args.root
    slot = ms.check_slot(args.slot)
    check_source_location(args.source, root)
    if args.replaces:
        names = known_sets(root)
        if names is not None and args.replaces not in names:
            raise ms.SurfaceError(f"--replaces {args.replaces}: no such set in MaterialUtil.sets")

    with ms.opened_source(args.source) as folder:
        surface = ms.read_surface(folder)
        base = args.base_material or ms.guess_base_material(surface)
        if not base:
            raise ms.SurfaceError(f"{surface.name}: cannot guess the base material from the JSON; pass --base-material")
        studs = ms.studs_per_tile(surface.metadata, ms.studs_per_metre(root), args.studs_per_tile)
        out_dir = os.path.join(root, ms.FAB_TEXTURES)
        result = ms.process(surface, out_dir, slot, base, args.ao_strength, args.normal_convention)

    material = {
        "variant": ms.variant_name(slot),
        "asset": surface.name,
        "baseMaterial": base,
        "studsPerTile": studs,
        "pattern": args.pattern,
        "override": bool(args.override),
    }
    if args.replaces:
        material["replaces"] = args.replaces
    rows = ms.manifest_rows(slot, surface, list(result["files"]), material, args.ao_strength, result["normal"], args.source_url)
    manifest = load_manifest(root)
    removed = ms.apply_rows(manifest, slot, rows, args.replace)
    save_manifest(root, manifest)

    convention, how = result["normal"]
    print(f"{surface.name} ({surface.layout} layout) -> {material['variant']} on {base}, {studs} studs per tile")
    print(f"normal: {convention} ({how}){', green flipped' if convention == 'directx' else ''}")
    for suffix, path in result["files"].items():
        print(f"wrote {os.path.relpath(path, root)}")
    for key in removed:
        print(f"removed {key}")
    for note in result["notes"]:
        print(f"note: {note}")

    if not args.no_sync:
        for script in ("sync_configs.py", "sync_needed.py"):
            subprocess.run([sys.executable, os.path.join(root, "scripts", script)], cwd=root, check=True)
    print(f"next: python3 scripts/upload_assets.py --only {ms.MANIFEST_PREFIX}{slot}_ && python3 scripts/sync_configs.py")
    return 0


def main():
    try:
        return run(sys.argv[1:])
    except ms.SurfaceError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
