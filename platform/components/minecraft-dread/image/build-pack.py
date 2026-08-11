#!/usr/bin/env python3
"""Build the DREAD server pack from the local CurseForge client instance.

DREAD ships no server pack, so the server side is the client instance minus the mods
listed in client-only-mods.txt. Output is two zips, both laid out to unpack over the
itzg/minecraft-server /data directory (mods/, config/, defaultconfigs/ at the top level),
which is what GENERIC_PACKS expects:

    dread-server.zip    the pack — the client instance, minus client-only mods
    server-extras.zip   server-mods/ and server-overrides/ from this directory

GENERIC_PACKS applies them in order, so server-extras wins on any file both contain. That
split is the whole point: the pack half stays a faithful copy of what the players have, and
anything that should differ on the server is a reviewable file in git rather than a
hand-edit inside a running container.

    python build-pack.py                    # uses the default instance path
    python build-pack.py --instance "D:\\path\\to\\instance" --out dist/

Run this on the machine that has the CurseForge instance. It is deliberately a build-time
step and not something the server does at boot: the pack is pinned to the exact jars the
players already have, rather than to whatever CurseForge serves that day.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_INSTANCE = r"C:\Users\isaac\curseforge\minecraft\Instances\DREAD - A Horror Survival Pack"

# Copied verbatim into the pack. `config` carries the pack's tuning — including
# biome_replacer.properties, which is what actually drives DREAD's worldgen — and
# `defaultconfigs` is what Forge seeds a new world's serverconfig from.
COPY_DIRS = ("config", "defaultconfigs")


def _mods_toml(jar: str) -> str:
    with zipfile.ZipFile(jar) as z:
        for n in z.namelist():
            if n.lower().endswith("mods.toml"):
                return z.read(n).decode("utf-8", "replace")
    return ""


def _provides(toml: str) -> list[str]:
    """modIds a jar PROVIDES — only those inside [[mods]] blocks.

    Deliberately not a blanket search for `modId=`: that also matches the modId lines inside
    [[dependencies.x]] blocks, which makes every jar look like it provides exactly what it
    requires and turns the check below into a no-op that always passes.
    """
    out = []
    for block in re.finditer(r"\[\[mods\]\](.*?)(?=^\s*\[\[|\Z)", toml, re.S | re.M):
        got = re.search(r'^\s*modId\s*=\s*"([^"]+)"', block.group(1), re.M)
        if got:
            out.append(got.group(1))
    return out


def _requires(toml: str):
    """(owner, needed modId, mandatory, side) from each [[dependencies.<owner>]] block."""
    out = []
    for m in re.finditer(r"\[\[dependencies\.([A-Za-z0-9_\-]+)\]\](.*?)(?=\[\[|\Z)", toml, re.S):
        owner, body = m.group(1), m.group(2)
        mid = re.search(r'modId\s*=\s*"([^"]+)"', body)
        if not mid:
            continue
        man = re.search(r"mandatory\s*=\s*(true|false)", body)
        side = re.search(r'side\s*=\s*"([^"]+)"', body)
        out.append((owner, mid.group(1),
                    (man.group(1) == "true") if man else False,
                    (side.group(1) if side else "BOTH").upper()))
    return out


LOADER_PROVIDED = {"minecraft", "forge", "neoforge", "java", "fml"}


def check_dependencies(kept: list[tuple[str, str]], removed: list[tuple[str, str]]) -> list[str]:
    """Every mandatory server-side dependency of a kept mod must also be kept.

    This exists because a library can look client-only by every available signal — client-only
    mixins, a client-side consumer — and still be a hard dependency of a server mod. Removing
    playeranimator (client mixins, used by firstperson) broke bettercombat, which needs it and
    runs on the server. Forge does not warn: it refuses to start.
    """
    provided, problems = set(), []
    for _, path in kept:
        provided.update(_provides(_mods_toml(path)))

    removed_provides = {}
    for name, path in removed:
        for mid in _provides(_mods_toml(path)):
            removed_provides[mid] = name

    for name, path in kept:
        for owner, need, mandatory, side in _requires(_mods_toml(path)):
            if not mandatory or need in LOADER_PROVIDED or need in provided or side == "CLIENT":
                continue
            culprit = removed_provides.get(need)
            problems.append(
                f"  {name}: mod {owner!r} needs {need!r} (side={side}) -- "
                + (f"removed by client-only-mods.txt as {culprit}" if culprit
                   else "not present in the pack at all")
            )
    return problems


def write_zip(zip_path: str, staging: str) -> str:
    """Zip `staging` deterministically and return the archive's sha256.

    Sorted entries and a fixed timestamp mean an unchanged input rebuilds to an identical
    archive, so the server sees the same checksum and skips re-applying the pack.
    """
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for root, dirs, files in os.walk(staging):
            dirs.sort()
            for f in sorted(files):
                full = os.path.join(root, f)
                rel = os.path.relpath(full, staging).replace(os.sep, "/")
                info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                with open(full, "rb") as fh:
                    z.writestr(info, fh.read())
    with open(zip_path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def read_exclusions(path: str) -> list[str]:
    names = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            if line:
                names.append(line)
    return names


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--instance", default=DEFAULT_INSTANCE)
    ap.add_argument("--exclusions", default=os.path.join(HERE, "client-only-mods.txt"))
    ap.add_argument("--out", default=os.path.join(HERE, "dist"))
    args = ap.parse_args()

    inst = args.instance
    if not os.path.isdir(os.path.join(inst, "mods")):
        print(f"error: no mods/ under {inst}", file=sys.stderr)
        return 1

    manifest = json.load(open(os.path.join(inst, "manifest.json"), encoding="utf-8"))
    mc_version = manifest["minecraft"]["version"]
    forge_version = next(
        l["id"].split("-", 1)[1] for l in manifest["minecraft"]["modLoaders"] if l.get("primary")
    )
    pack_version = manifest.get("name", "pack").split()[-1]

    exclusions = read_exclusions(args.exclusions)
    jars = sorted(f for f in os.listdir(os.path.join(inst, "mods")) if f.lower().endswith(".jar"))

    # A stale exclusion means the pack updated and a jar was renamed — the mod it names is
    # then silently back on the server. Fail rather than ship a pack nobody reviewed.
    stale = [n for n in exclusions if n not in jars]
    if stale:
        print("error: client-only-mods.txt lists jars that are not in the instance:", file=sys.stderr)
        for n in stale:
            print(f"  {n}", file=sys.stderr)
        print("\nthe pack was probably updated — re-check the list against mods/", file=sys.stderr)
        return 1

    keep = [j for j in jars if j not in set(exclusions)]

    # Every mandatory server-side dependency of a kept mod must itself be kept. Forge does
    # not degrade here — a missing hard dependency is a refusal to start — so this is a build
    # failure, not a warning.
    extra_dir = os.path.join(HERE, "server-mods")
    kept_pairs = [(j, os.path.join(inst, "mods", j)) for j in keep]
    if os.path.isdir(extra_dir):
        kept_pairs += [(j, os.path.join(extra_dir, j))
                       for j in sorted(os.listdir(extra_dir)) if j.lower().endswith(".jar")]
    removed_pairs = [(j, os.path.join(inst, "mods", j)) for j in exclusions]

    broken = check_dependencies(kept_pairs, removed_pairs)
    if broken:
        print("error: removing those mods breaks a mandatory dependency:\n", file=sys.stderr)
        for line in broken:
            print(line, file=sys.stderr)
        print("\nkeep the named jar (move it to the DELIBERATELY KEPT section of "
              "client-only-mods.txt with a note)", file=sys.stderr)
        return 1

    os.makedirs(args.out, exist_ok=True)
    zip_path = os.path.join(args.out, "dread-server.zip")

    with tempfile.TemporaryDirectory() as staging:
        mods_dst = os.path.join(staging, "mods")
        os.makedirs(mods_dst)
        for j in keep:
            shutil.copy2(os.path.join(inst, "mods", j), os.path.join(mods_dst, j))
        for d in COPY_DIRS:
            src = os.path.join(inst, d)
            if os.path.isdir(src):
                shutil.copytree(src, os.path.join(staging, d))

        digest = write_zip(zip_path, staging)

    # ── the overlay ──────────────────────────────────────────────────────────
    # server-mods/ are jars the CLIENT does not have. That is only safe for mods Forge's
    # handshake ignores — ones that register no network channel and no registry objects.
    # A mod with side=BOTH that does register either will reject every player who joins
    # without it, so check before adding to that directory.
    extras_zip = os.path.join(args.out, "server-extras.zip")
    extra_mods, extra_files = [], 0
    with tempfile.TemporaryDirectory() as staging:
        src_mods = os.path.join(HERE, "server-mods")
        if os.path.isdir(src_mods):
            extra_mods = sorted(f for f in os.listdir(src_mods) if f.lower().endswith(".jar"))
            if extra_mods:
                os.makedirs(os.path.join(staging, "mods"))
                for j in extra_mods:
                    shutil.copy2(os.path.join(src_mods, j), os.path.join(staging, "mods", j))

        src_over = os.path.join(HERE, "server-overrides")
        if os.path.isdir(src_over):
            for entry in sorted(os.listdir(src_over)):
                s = os.path.join(src_over, entry)
                d = os.path.join(staging, entry)
                if os.path.isdir(s):
                    shutil.copytree(s, d, dirs_exist_ok=True)
                else:
                    shutil.copy2(s, d)
            extra_files = sum(len(f) for _, _, f in os.walk(src_over))

        extras_digest = write_zip(extras_zip, staging)

    print(f"minecraft   {mc_version}")
    print(f"forge       {forge_version}")
    print(f"pack        {manifest.get('name')} (version tag: {pack_version})")
    print(f"mods        {len(jars)} in instance -> {len(keep)} on server ({len(exclusions)} removed)")
    print(f"extras      {len(extra_mods)} server-only mods, {extra_files} override file(s)")
    for j in extra_mods:
        print(f"              + {j}")
    print(f"output      {zip_path}  ({os.path.getsize(zip_path)/1024/1024:.0f} MiB)")
    print(f"sha256      {digest}")
    print(f"output      {extras_zip}  ({os.path.getsize(extras_zip)/1024/1024:.1f} MiB)")
    print(f"sha256      {extras_digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
