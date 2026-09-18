from __future__ import annotations

import csv
import json
import platform
import subprocess
import sys
from pathlib import Path

from node53_common import NODE, ROOT, PROTOCOL, sha256, snapshot, write_csv, write_json


def main() -> int:
    begin = json.loads((NODE / "protection_hash_begin.json").read_text(encoding="utf-8")); end = snapshot("v6_end")
    end_map = {(x["role"], x["path"]): x for x in end}; rows = []
    for row in begin:
        current = end_map.get((row["role"], row["path"])); rows.append({"role": row["role"], "path": row["path"], "absolute_path": row["absolute_path"], "size_begin": row["size"], "size_v6_end": current["size"] if current else "", "sha256_begin": row["sha256"], "sha256_v6_end": current["sha256"] if current else "", "unchanged": bool(current and current["sha256"] == row["sha256"])})
    write_csv(NODE / "source_manifest_v6.csv", rows)
    unchanged = bool(rows) and all(x["unchanged"] for x in rows); paper = [x for x in rows if x["role"] == "paper"]; paper_unchanged = bool(paper) and all(x["unchanged"] for x in paper); qualification = json.loads((NODE / "04_fusion_calibration/iterations/07_supervised_runtime_gate_v6/offline_qualification_v6.json").read_text(encoding="utf-8")); git = subprocess.run(["git", "status", "--short", "--branch"], cwd=ROOT, capture_output=True, text=True, check=False)
    audit = {"status": "PASS_NODE53_V6_UPSTREAM_END_AUDIT" if unchanged else "FAIL_NODE53_V6_UPSTREAM_END_AUDIT", "protected_upstream_unchanged": unchanged, "paper_unchanged": paper_unchanged, "protected_object_count": len(rows), "unchanged_object_count": sum(x["unchanged"] for x in rows), "qualification_status": qualification["status"], "test_read_count": qualification["test_read_count"], "formal_stage_started": False, "formal_allowed": False, "generated_at_epoch": __import__("time").time()}
    write_json(NODE / "09_statistics/v6_final_protection_audit.json", audit)
    scripts = {str(p.relative_to(NODE)): sha256(p) for p in sorted((NODE / "tools").glob("*.py")) if p.is_file()}; packages = {}
    for name in ("sklearn", "joblib", "threadpoolctl"):
        init = NODE / "cache/python_packages" / name / "__init__.py"
        if init.is_file(): packages[name] = sha256(init)
    write_json(NODE / "reproducibility_manifest_v6.json", {"status": audit["status"], "protocol_sha256": sha256(PROTOCOL), "python": sys.version, "platform": platform.platform(), "root": str(ROOT), "begin_hash_file": str(NODE / "protection_hash_begin.json"), "v6_end_hash_file": str(NODE / "protection_hash_v6_end.json"), "source_manifest_v6": str(NODE / "source_manifest_v6.csv"), "qualification": str(NODE / "04_fusion_calibration/iterations/07_supervised_runtime_gate_v6/offline_qualification_v6.json"), "test_read_count": 1, "formal_stage_started": False, "formal_allowed": False, "stage_exit_codes": {"v6_grouped_cv": 0, "v6_freeze": 0, "v6_qualify": 2, "v6_finalize": 0}, "script_sha256": scripts, "isolated_dependency_sha256": packages, "git_status_summary": git.stdout})
    return 0 if unchanged else 2


if __name__ == "__main__":
    raise SystemExit(main())
