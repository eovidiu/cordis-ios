#!/usr/bin/env bash
# Checks AppStore/metadata.md fields against App Store Connect limits and
# the screenshots against the 6.9-inch iPhone size. Exits non-zero on any
# violation.
set -euo pipefail
cd "$(dirname "$0")"

python3 - <<'PY'
import re, struct, sys, pathlib

text = pathlib.Path("metadata.md").read_text()
problems = []

fields = re.findall(r"<!-- field: (\w+) \(max (\d+)\) -->\n(.*?)\n<!-- end -->", text, flags=re.S)
names = {name for name, _, _ in fields}
for required in ["promotional", "description", "keywords", "whatsnew", "copyright", "reviewnotes"]:
    if required not in names:
        problems.append(f"missing field {required}")
for name, limit, value in fields:
    value = value.strip()
    if not value:
        problems.append(f"{name} is empty")
    if len(value) > int(limit):
        problems.append(f"{name} is {len(value)} characters, limit {limit}")
    if name == "keywords" and any(not k.strip() for k in value.split(",")):
        problems.append("keywords contain an empty entry")

table = dict(re.findall(r"^\| (Name|Subtitle) \| (.+?) \|$", text, flags=re.M))
for field, limit in [("Name", 30), ("Subtitle", 30)]:
    if field not in table:
        problems.append(f"missing {field}")
    elif len(table[field]) > limit:
        problems.append(f"{field} is {len(table[field])} characters, limit {limit}")

shots = sorted(pathlib.Path("screenshots").glob("*.png"))
if not 1 <= len(shots) <= 10:
    problems.append(f"{len(shots)} screenshots; App Store Connect takes 1 to 10")
for shot in shots:
    data = shot.read_bytes()[:32]
    width, height = struct.unpack(">II", data[16:24])
    color_type = data[25]
    if (width, height) not in [(1320, 2868), (2868, 1320)]:
        problems.append(f"{shot.name} is {width}x{height}, expected 1320x2868")
    if color_type in (4, 6):
        problems.append(f"{shot.name} has an alpha channel")

for problem in problems:
    print(f"AppStore/check.sh: {problem}", file=sys.stderr)
if problems:
    sys.exit(1)
print(f"metadata ok: {len(fields)} text fields within limits, {len(shots)} screenshots at 1320x2868")
PY
