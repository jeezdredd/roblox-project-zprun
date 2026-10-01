#!/usr/bin/env python3
"""Every CC BY asset in the manifest is credited in the game exactly once.

Run from the repository root:  python3 tests/credits/run.py

Reads assets/manifest.json on its own (not through the generator) and the generated
src/shared/config/CreditsConfig.luau as text, so it checks what ships: every CC BY
entry (any version) that is approved or reviewing appears in exactly one credit line,
nothing else does, and every line carries a title, an author, a CC BY licence and a
source URL. Exits non-zero when any check failed.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(ROOT, "assets", "manifest.json")
CREDITS = os.path.join(ROOT, "src", "shared", "config", "CreditsConfig.luau")

failures = 0


def check(name, condition, detail=""):
    global failures
    if not condition:
        failures += 1
        print(f"  FAIL {name}" + (f" ({detail})" if detail else ""))


def credited_keys_expected(manifest):
    keys = set()
    for key, entry in manifest.items():
        licence = entry.get("license") or ""
        is_cc_by = re.search(r"CC[- ]?BY\b", licence, re.IGNORECASE) and "CC0" not in licence.upper()
        if is_cc_by and entry.get("status") in ("approved", "reviewing"):
            keys.add(key)
    return keys


def credit_blocks(text):
    """The credit lines of CreditsConfig.groups: (fields, asset keys) per line."""
    groups_part = text.split("CreditsConfig.acknowledgements", 1)[0]
    blocks = []
    pattern = re.compile(
        r'title = "((?:[^"\\]|\\.)*)",\s*author = "((?:[^"\\]|\\.)*)",\s*licence = "((?:[^"\\]|\\.)*)",'
        r'\s*url = "((?:[^"\\]|\\.)*)",\s*assets = \{(.*?)\}',
        re.S,
    )
    for match in pattern.finditer(groups_part):
        title, author, licence, url, assets = match.groups()
        keys = re.findall(r'"((?:[^"\\]|\\.)*)"', assets)
        blocks.append(({"title": title, "author": author, "licence": licence, "url": url}, keys))
    return blocks


def main():
    with open(MANIFEST, encoding="utf-8") as handle:
        manifest = json.load(handle)
    with open(CREDITS, encoding="utf-8") as handle:
        text = handle.read()

    expected = credited_keys_expected(manifest)
    blocks = credit_blocks(text)
    seen = {}
    for fields, keys in blocks:
        for key in keys:
            seen[key] = seen.get(key, 0) + 1
        check(f"line {fields['title']!r} has a title", fields["title"].strip() != "")
        check(f"line {fields['title']!r} has an author", fields["author"].strip() != "")
        check(f"line {fields['title']!r} licence is CC BY", re.fullmatch(r"CC BY \d(\.\d)?", fields["licence"]) is not None, fields["licence"])
        check(f"line {fields['title']!r} has a source URL", fields["url"].startswith("http"), fields["url"])
        check(f"line {fields['title']!r} covers at least one asset", len(keys) > 0)

    print(f"{len(expected)} CC BY entries, {len(blocks)} credit lines")
    check("there are CC BY entries to credit", len(expected) > 0)
    for key in sorted(expected):
        check(f"{key} credited exactly once", seen.get(key, 0) == 1, f"{seen.get(key, 0)} times")
    for key in sorted(seen):
        check(f"{key} is a CC BY entry", key in expected)
    check("three groups in order", re.findall(r'name = "([^"]+)"', text) == ["Models and textures", "Animations", "Audio"])
    check("acknowledgements say no attribution is required", text.count("no attribution required") >= 2)

    if failures:
        print(f"{failures} check(s) failed")
        return 1
    print("all credits tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
