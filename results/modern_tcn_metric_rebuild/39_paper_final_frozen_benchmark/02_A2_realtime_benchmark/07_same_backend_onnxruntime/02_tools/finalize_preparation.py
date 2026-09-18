from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

from a2ort_paths import ORT_ROOT


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    excluded_roots = [ORT_ROOT / "05_formal/runs"]
    artifacts = []
    for path in sorted(ORT_ROOT.rglob("*")):
        if not path.is_file() or path.name == "artifact_manifest.json":
            continue
        if any(root == path or root in path.parents for root in excluded_roots):
            continue
        artifacts.append(
            {
                "relative_path": path.relative_to(ORT_ROOT).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
    manifest = {
        "created_at": datetime.now(timezone.utc).astimezone().isoformat(),
        "scope": "preparation artifacts; formal runs excluded",
        "artifact_count": len(artifacts),
        "artifacts": artifacts,
    }
    (ORT_ROOT / "artifact_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Preparation artifact manifest written: {len(artifacts)} files")


if __name__ == "__main__":
    main()

