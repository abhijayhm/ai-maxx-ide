"""Device identifier hashing."""

import hashlib
import json


def compute_device_hash(data: dict) -> str:
    """Compute deterministic sha256 hash from device info payload."""
    canonical = json.dumps(data, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()
