#!/usr/bin/env python3
"""Static check of Roblox class and property names used in src/.

Downloads the official API dump once into the system temp dir, then verifies:
  1. every Instance.new("Class") refers to a real class
  2. every property assigned on a locally constructed instance exists on that class

Usage: python3 tools/validate_api.py
Exit code 1 if anything is invalid.
"""

import glob
import json
import os
import re
import subprocess
import sys
import tempfile

DUMP_URL = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json"
CACHE = os.path.join(tempfile.gettempdir(), "roblox-api-dump.json")


def load_dump():
    if not os.path.exists(CACHE) or os.path.getsize(CACHE) < 1_000_000:
        subprocess.run(["curl", "-sLf", DUMP_URL, "-o", CACHE], check=True)
    with open(CACHE) as handle:
        return json.load(handle)


def build_index(api):
    props, parents = {}, {}
    for entry in api["Classes"]:
        props[entry["Name"]] = {
            member["Name"] for member in entry["Members"] if member["MemberType"] == "Property"
        }
        parents[entry["Name"]] = entry.get("Superclass")
    return props, parents


def inherited_props(name, props, parents):
    out, cursor = set(), name
    while cursor and cursor in props:
        out |= props[cursor]
        cursor = parents.get(cursor)
    return out


def main():
    props, parents = build_index(load_dump())
    failures = []

    for path in glob.glob("src/**/*.luau", recursive=True):
        with open(path) as handle:
            source = handle.read()

        for match in re.finditer(r'Instance\.new\(\s*"([A-Za-z0-9_]+)"', source):
            if match.group(1) not in props:
                line = source[: match.start()].count("\n") + 1
                failures.append(f'{path}:{line} unknown class "{match.group(1)}"')

        for match in re.finditer(r'(?:makePart|createPart|place)\(\s*\n?\s*"([A-Za-z0-9_]+)"\s*,\s*\n?\s*"', source):
            name = match.group(1)
            looks_like_class = name[0].isupper() and ("Part" in name or name in ("Seat", "SpawnLocation"))
            if looks_like_class and name not in props:
                line = source[: match.start()].count("\n") + 1
                failures.append(f'{path}:{line} unknown class "{name}" passed as className')

        for match in re.finditer(r'local\s+(\w+)\s*=\s*Instance\.new\(\s*"([A-Za-z0-9_]+)"\s*\)', source):
            variable, class_name = match.group(1), match.group(2)
            if class_name not in props:
                continue
            valid = inherited_props(class_name, props, parents)
            region = source[match.end() : match.end() + 3000]
            for assignment in re.finditer(r"\b" + re.escape(variable) + r"\.([A-Za-z0-9_]+)\s*=", region):
                if assignment.group(1) not in valid:
                    failures.append(f"{path} {class_name}.{assignment.group(1)} does not exist")

    for failure in dict.fromkeys(failures):
        print(failure)
    if failures:
        print(f"\n{len(set(failures))} problem(s) found")
        return 1
    print("API usage OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
