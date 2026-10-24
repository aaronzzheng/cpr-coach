"""Configuration: loads shared/targets.json (AHA targets) and environment settings."""

from __future__ import annotations

import json
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TARGETS_PATH = REPO_ROOT / "shared" / "targets.json"
DATA_DIR = Path(os.environ.get("CPR_DATA_DIR", REPO_ROOT / "data"))
WEB_DIST = REPO_ROOT / "web" / "dist"


def load_targets() -> dict[str, float]:
    with TARGETS_PATH.open() as f:
        return json.load(f)


TARGETS = load_targets()
