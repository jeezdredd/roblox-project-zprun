#!/usr/bin/env python3
"""Regenerate assets/NEEDED.md: the shopping list of empty asset slots.

An empty slot is any manifest entry whose assetId is 0 or missing. Rejected
uploads count as empty too: the id exists but must not be used.

Usage:
    python3 scripts/sync_needed.py
    python3 scripts/sync_needed.py --check   # non-zero exit if the file is stale
"""

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "assets", "manifest.json")
OUTPUT = os.path.join(ROOT, "assets", "NEEDED.md")

# Per-slot guidance: where the slot is consumed, what to search for, priority.
GUIDE = {
    "animation/player/run": ("AnimationController: run cycle", "Mixamo: Running (in place, rifle carry)", "blocker"),
    "animation/player/strafe_left": ("AnimationController: lateral dodge", "Mixamo: Left Strafe (in place)", "blocker"),
    "animation/player/strafe_right": ("AnimationController: lateral dodge", "Mixamo: Right Strafe (in place)", "blocker"),
    "audio/ui/hit_marker": ("HitMarkers: the hit tick on a confirmed hit", "Kenney Interface Sounds (CC0) tick; freesound CC0 'hitmarker'; a recording. Never synthesized", "polish"),
    "audio/ui/kill_marker": ("HitMarkers: the kill marker on a confirmed kill", "Kenney Impact Sounds (CC0) soft impact; freesound CC0 'kill confirm'; a recording. Never synthesized", "polish"),
    "animation/player/sit_idle": ("AnimationController: seated idle in the helicopter cabin (SIT_CLIP)", "Mixamo: Sitting Idle (in place); Quaternius UAL (CC0) sit", "polish"),
    "animation/player/stumble": ("AnimationController: obstacle clip", "Mixamo: Stumble Backwards", "polish"),
    "animation/player/death": ("DeathService / DeathController: supine death pose", "Mixamo: Falling Back Death", "blocker"),
    "animation/zombie/idle_a": ("ZombieAnimator: idle variation", "Mixamo: Zombie Idle", "blocker"),
    "animation/zombie/idle_b": ("ZombieAnimator: idle variation", "Mixamo: Zombie Neck Bite (idle part)", "polish"),
    "animation/zombie/idle_c": ("ZombieAnimator: rise from ground", "Mixamo: Zombie Stand Up", "polish"),
    "animation/zombie/walk_shuffle": ("ZombieAnimator: walker gait", "Mixamo: Zombie Walk (in place)", "blocker"),
    "animation/zombie/run_ragged": ("ZombieAnimator: runner gait", "Mixamo: Zombie Running (in place)", "blocker"),
    "animation/zombie/attack_lunge": ("ZombieAI: touch attack", "Mixamo: Zombie Attack", "blocker"),
    "animation/zombie/feeding": ("DeathService: corpse feeding loop", "Mixamo: Zombie Feeding", "blocker"),
    "animation/weapon/fire": ("Viewmodel: clip layer over spring recoil", "Universal Viewmodel Template: fire", "polish"),
    "animation/weapon/reload": ("Viewmodel: replaces procedural reload", "Universal Viewmodel Template: reload", "polish"),
    "animation/weapon/equip": ("Viewmodel: replaces procedural raise", "Universal Viewmodel Template: raise/equip", "polish"),
    "animation/weapon/inspect": ("Viewmodel: F key inspect", "Universal Viewmodel Template: inspect", "polish"),
    "animation/weapon/sprint": ("Viewmodel: sprint carry pose", "Universal Viewmodel Template: sprint/run", "polish"),
    "audio/range/gong": ("Shooting range: gong hit feedback", "Freesound CC0: metal gong hit / steel target ping", "blocker"),
    "audio/weapons/shell_03": ("Weapon shell casing variation 3", "Kenney CC0 impact sounds: small metal drop", "polish"),
    "audio/weapons/mid_pistol": ("WeaponSfx.playDistantShot: GunshotRemote mid layer, 40..350 studs", "FFSL Prepared: Walther PPQ mid-distance row, cut with tools/audio_build/build_shots_v6.py", "polish"),
    "audio/weapons/mid_smg": ("WeaponSfx.playDistantShot: GunshotRemote mid layer, 40..350 studs", "FFSL Prepared: Carl Gustav M45 mid-distance row, cut with tools/audio_build/build_shots_v6.py", "polish"),
    "audio/weapons/mid_shotgun": ("WeaponSfx.playDistantShot: GunshotRemote mid layer, 40..350 studs", "FFSL Prepared: Benelli Nova mid-distance row, cut with tools/audio_build/build_shots_v6.py", "polish"),
    "audio/weapons/mid_rifle": ("WeaponSfx.playDistantShot: GunshotRemote mid layer, 40..350 studs", "FFSL Prepared: AK-47 C_31P.wav, cut with tools/audio_build/build_shots_v6.py", "polish"),
    "audio/weapons/far_pistol": ("WeaponSfx.playDistantShot: GunshotRemote far layer, 250..1400 studs", "freesound CC0 'distant gunshot'; BigSoundBank 'gunshot far'", "polish"),
    "audio/weapons/far_smg": ("WeaponSfx.playDistantShot: GunshotRemote far layer, 250..1400 studs", "freesound CC0 'distant gunshot'; BigSoundBank 'gunshot far'", "polish"),
    "audio/weapons/far_shotgun": ("WeaponSfx.playDistantShot: GunshotRemote far layer, 250..1400 studs", "freesound CC0 'distant gunshot'; BigSoundBank 'gunshot far'", "polish"),
    "audio/weapons/far_rifle": ("WeaponSfx.playDistantShot: GunshotRemote far layer, 250..1400 studs", "freesound CC0 'distant gunshot'; BigSoundBank 'gunshot far'", "polish"),
    "audio/weapons/impact_concrete_01": ("WeaponSfx.playImpacts: bullet on stone (Kenney land_hard stands in)", "freesound CC0 'bullet impact concrete'", "polish"),
    "audio/weapons/impact_concrete_02": ("WeaponSfx.playImpacts: bullet on stone, variation", "freesound CC0 'bullet impact concrete'", "polish"),
    "audio/weapons/impact_metal_01": ("WeaponSfx.playImpacts: bullet on metal (Kenney bolt stands in)", "freesound CC0 'bullet impact metal'", "polish"),
    "audio/weapons/impact_metal_02": ("WeaponSfx.playImpacts: bullet on metal, variation", "freesound CC0 'bullet impact metal'", "polish"),
    "audio/weapons/impact_wood_01": ("WeaponSfx.playImpacts: bullet on wood (Kenney land_soft stands in)", "freesound CC0 'bullet impact wood'", "polish"),
    "audio/weapons/impact_wood_02": ("WeaponSfx.playImpacts: bullet on wood, variation", "freesound CC0 'bullet impact wood'", "polish"),
    "audio/weapons/impact_dirt_01": ("WeaponSfx.playImpacts: bullet on soil (Kenney land_soft stands in)", "freesound CC0 'bullet impact dirt'", "polish"),
    "audio/weapons/impact_dirt_02": ("WeaponSfx.playImpacts: bullet on soil, variation", "freesound CC0 'bullet impact dirt'", "polish"),
    "audio/weapons/impact_flesh_01": ("WeaponSfx.playImpacts: bullet on a body (Kenney bite stands in)", "freesound CC0 'bullet impact flesh'", "polish"),
    "audio/weapons/impact_flesh_02": ("WeaponSfx.playImpacts: bullet on a body, variation", "freesound CC0 'bullet impact flesh'", "polish"),
    "audio/weapons/ricochet_01": ("WeaponSfx.playImpacts: one hard hit in six", "freesound CC0 'ricochet'", "polish"),
    "animation/player/rifle_idle": ("AnimationController: rifle set idle", "Mixamo: Rifle Idle (In Place)", "polish"),
    "animation/player/rifle_walk": ("AnimationController: rifle set walk", "Mixamo: Rifle Walk (In Place)", "polish"),
    "animation/player/rifle_run": ("AnimationController: rifle set run, replaces Run", "Mixamo: Rifle Run (In Place)", "polish"),
    "animation/player/rifle_sprint": ("AnimationController: rifle set sprint", "Mixamo: Sprint Forward, rifle carry (In Place)", "polish"),
    "animation/player/rifle_strafe_left": ("AnimationController: rifle set strafe", "Mixamo: Strafe, rifle walk, left (In Place)", "polish"),
    "animation/player/rifle_strafe_right": ("AnimationController: rifle set strafe", "Mixamo: Strafe, rifle walk, right (In Place)", "polish"),
    "animation/player/rifle_reload": ("AnimationController.playAction: rifle reload", "Mixamo: Reloading, rifle standing", "polish"),
    "animation/player/pistol_idle": ("AnimationController: pistol set idle", "Mixamo: Pistol Idle (In Place)", "polish"),
    "animation/player/pistol_walk": ("AnimationController: pistol set walk", "Mixamo: Pistol Walk (In Place)", "polish"),
    "animation/player/pistol_run": ("AnimationController: pistol set run, replaces Run", "Mixamo: Pistol Run (In Place)", "polish"),
    "animation/player/pistol_strafe_left": ("AnimationController: pistol set strafe", "Mixamo: Pistol Strafe, left (In Place)", "polish"),
    "animation/player/pistol_strafe_right": ("AnimationController: pistol set strafe", "Mixamo: Pistol Strafe, right (In Place)", "polish"),
    "animation/player/hit_rifle": ("AnimationController.playAction: hit reaction", "Mixamo: Hit Reaction, holding a rifle", "polish"),
    "animation/zombie/stand_up_back": ("ZombieAnimator: Dormant rise (idle_c stands in)", "Mixamo: Zombie Stand Up, from the back", "polish"),
    "animation/zombie/stand_up_stomach": ("ZombieAnimator: Dormant rise (idle_c stands in)", "Mixamo: Zombie Stand Up, from the stomach", "polish"),
    "animation/zombie/biting_ground": ("ZombieAnimator: Feeding pose (feeding stands in)", "Mixamo: Zombie Biting Victim On The Ground", "polish"),
    "audio/upgrade/announcer_upgrade_01": ("UpgradeStations / WeaponPickupClient: announcer on a successful upgrade, take 1", "Kenney Voiceover Pack (CC0) 'power up' / 'excellent'; freesound CC0 'announcer upgrade'; a recorded line. Never generated speech", "polish"),
    "audio/upgrade/announcer_upgrade_02": ("UpgradeStations / WeaponPickupClient: announcer on a successful upgrade, take 2", "Kenney Voiceover Pack (CC0) 'upgrade' / 'nice'; freesound CC0 'announcer upgrade'; a recorded line. Never generated speech", "polish"),
    "audio/upgrade/announcer_max": ("UpgradeStations / WeaponPickupClient: announcer when the weapon is at max level", "Kenney Voiceover Pack (CC0) 'max' / 'that is the limit'; freesound CC0 'announcer maximum'; a recorded line. Never generated speech", "polish"),
}

MEGASCANS_PREFIX = "texture/surface/megascans/"


def guide_for(key):
    """The GUIDE row, or for an imported Megascans map (docs/environment/megascans.md)
    a row that points at the upload: the file already exists on the owner's machine."""
    if key in GUIDE:
        return GUIDE[key]
    if key.startswith(MEGASCANS_PREFIX):
        return (
            "MaterialUtil: a TFZ_MS_ MaterialVariant, declared once every map of the set has an id",
            "Imported (assets/fab/, owner's machine only): python3 scripts/upload_assets.py --only " + MEGASCANS_PREFIX,
            "polish",
        )
    return ("none", "none", "polish")


CATEGORY_TITLES = {
    "animation": "Animation",
    "audio": "Audio",
    "texture": "Texture",
}


def load_manifest():
    with open(MANIFEST, "r", encoding="utf-8") as handle:
        return json.load(handle)


def empty_slots(manifest):
    slots = []
    for key, entry in sorted(manifest.items()):
        asset_id = str(entry.get("assetId") or "0").strip()
        status = str(entry.get("status") or "pending")
        if asset_id in ("", "0") or status == "rejected":
            slots.append((key, status))
    return slots


def render(slots):
    lines = [
        "# Needed assets",
        "",
        "Generated by `scripts/sync_needed.py` from `assets/manifest.json`. Every row is a slot that is",
        "currently silent or unanimated because no approved asset backs it. Systems guard on `assetId > 0`,",
        "so an empty slot degrades to nothing happening rather than an error.",
        "",
        "Rules for filling these are in [docs/asset-policy.md](../docs/asset-policy.md): real licensed files",
        "only, no synthesis, no invented ids.",
        "",
    ]

    if not slots:
        lines.append("Nothing outstanding: every manifest slot has an approved asset.")
        lines.append("")
        return "\n".join(lines)

    grouped = {}
    for key, status in slots:
        category = key.split("/")[0]
        grouped.setdefault(category, []).append((key, status))

    for category in sorted(grouped):
        lines.append(f"## {CATEGORY_TITLES.get(category, category.title())}")
        lines.append("")
        lines.append("| Slot | Used by | What to look for | Priority | Status |")
        lines.append("| --- | --- | --- | --- | --- |")
        for key, status in grouped[category]:
            used_by, search, priority = guide_for(key)
            lines.append(f"| `{key}` | {used_by} | {search} | {priority} | {status} |")
        lines.append("")

    blockers = [key for key, _ in slots if guide_for(key)[2] == "blocker"]
    lines.append(f"**{len(blockers)} blockers, {len(slots) - len(blockers)} polish items.**")
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="exit non-zero when the file is out of date")
    args = parser.parse_args()

    manifest = load_manifest()
    content = render(empty_slots(manifest))

    if args.check:
        current = ""
        if os.path.exists(OUTPUT):
            with open(OUTPUT, "r", encoding="utf-8") as handle:
                current = handle.read()
        if current != content:
            print("assets/NEEDED.md is out of date, run scripts/sync_needed.py")
            return 1
        print("assets/NEEDED.md is up to date")
        return 0

    with open(OUTPUT, "w", encoding="utf-8") as handle:
        handle.write(content)
    print(f"wrote {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
