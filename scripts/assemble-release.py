"""Pin both native archives in the npm bootstrap; run before npm pack."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
version = json.loads((ROOT / "package.json").read_text())["version"]
assets = {}
for platform in ("windows-x64", "macos-universal"):
    item = json.loads((args.output / (platform + ".json")).read_text())
    assert item["version"] == version and item["platform"] == platform
    assert hashlib.sha256((args.output / item["asset"]).read_bytes()).hexdigest() == item["sha256"]
    assets[platform] = {key: item[key] for key in ("asset", "url", "sha256")}
manifest = {"version": version, "assets": assets}
data = json.dumps(manifest, indent=2) + "\n"
(ROOT / "release-assets.json").write_text(data, encoding="utf-8")
(args.output / "release.json").write_text(data, encoding="utf-8")
print(data)
