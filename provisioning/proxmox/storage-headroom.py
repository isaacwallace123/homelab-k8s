#!/usr/bin/env python3
"""Report storage pressure from the hypervisor, even when Kubernetes is down."""

import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
from urllib.error import URLError
from urllib.request import Request, urlopen


def usage():
    report = subprocess.check_output(
        ["lvs", "--reportformat", "json", "--select", "segtype=thin-pool",
         "-o", "vg_name,lv_name,data_percent,metadata_percent"],
        text=True,
    )
    for pool in json.loads(report)["report"][0]["lv"]:
        name = f"{pool['vg_name']}/{pool['lv_name']}"
        yield f"{name} data", float(pool["data_percent"])
        yield f"{name} metadata", float(pool["metadata_percent"])

    paths = ["/"]
    if os.path.ismount("/mnt/backups"):
        paths.append("/mnt/backups")
    for path in paths:
        disk = shutil.disk_usage(path)
        yield path, 100 * disk.used / (disk.used + disk.free)


def threshold(percent):
    return max(level for level in (0, 75, 85, 95) if percent >= level)


def run():
    measurements = dict(usage())
    if sys.argv[1:] == ["--check"]:
        for name, percent in measurements.items():
            print(f"{name}: {percent:.1f}%")
        return

    state_path = Path(os.environ["STATE_DIRECTORY"]) / "sent.json"
    sent = json.loads(state_path.read_text()) if state_path.exists() else {}
    for name, percent in measurements.items():
        level = threshold(percent)
        previous = sent.get(name, 0)
        if level < previous:
            sent[name] = level
        if level <= previous:
            continue

        message = f"{socket.gethostname()} {name} is {percent:.1f}% full (threshold {level}%)."
        print(message, flush=True)
        request = Request(
            os.environ["NTFY_URL"],
            data=message.encode(),
            headers={"Title": "Proxmox storage pressure", "Priority": "high" if level >= 85 else "default"},
        )
        try:
            with urlopen(request, timeout=4):
                sent[name] = level
        except (URLError, TimeoutError) as error:
            print(f"ntfy unavailable, will retry: {error}", file=sys.stderr)

    temporary = state_path.with_suffix(".tmp")
    temporary.write_text(json.dumps(sent))
    temporary.replace(state_path)


if __name__ == "__main__":
    run()
