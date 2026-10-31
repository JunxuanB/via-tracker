#!/usr/bin/env python3
"""Remove XcodeGen's duplicate folder entries for local Swift packages.

XcodeGen 2.46 emits both a folder and an XCLocalSwiftPackageReference for
each local package. Xcode 27.2 cannot open the same path as both types.
Keep the package references and product dependencies; Xcode displays the
sources under Package Dependencies.
"""

import json
from pathlib import Path
import re
import subprocess


project = Path(__file__).resolve().parents[1] / "ios/VIATracker.xcodeproj/project.pbxproj"
objects = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", str(project)
]))["objects"]
package_paths = {
    obj["relativePath"] for obj in objects.values()
    if obj["isa"] == "XCLocalSwiftPackageReference"
}
removed = {
    key for key, obj in objects.items()
    if obj["isa"] == "PBXFileReference"
    and obj.get("lastKnownFileType") == "folder"
    and obj.get("sourceTree") == "SOURCE_ROOT"
    and obj.get("path") in package_paths
}
# Remove groups that become empty after removing the duplicate folders.
while True:
    empty_groups = {
        key for key, obj in objects.items()
        if obj["isa"] == "PBXGroup" and obj.get("children")
        and set(obj["children"]) <= removed
    } - removed
    if not empty_groups:
        break
    removed.update(empty_groups)

source = project.read_text()
for key in removed:
    # XcodeGen writes file references on one line and groups across lines.
    source = re.sub(
        rf"(?m)^\t\t{key} /\*[^\n]*\*/ = \{{(?:[^\n]*\}};\n|\n[\s\S]*?^\t\t\}};\n)",
        "", source,
    )
    source = re.sub(rf"(?m)^\t+{key} /\*[^\n]*\*/,\n", "", source)
project.write_text(source)
