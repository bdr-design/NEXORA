#!/usr/bin/env python3
"""Bounded transport regression: real K3 truncation and exact recovery, not C closure."""
import argparse
import json
import shutil
import struct
import tempfile
from pathlib import Path

from stage005_c_crash import kill_at, run


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve()
    with tempfile.TemporaryDirectory(prefix="nxr-c-mid-record-") as temporary:
        root = Path(temporary)
        baseline = run(binary, "stage-c-crash-bootstrap", root / "base", 1000000)
        case = root / "case"
        shutil.copytree(root / "base", case)
        kill_at(binary, case, "c.k3.mid_record")
        partial = (case / "snapshot-2.tmp").read_bytes()
        assert partial[:8] == b"NXRSNAP2"
        offset, complete = 16, 0
        while True:
            assert offset + 16 <= len(partial), "K3 must leave a real record header"
            kind, reserved, index, elements, payload = struct.unpack_from("<HHIII", partial, offset)
            assert reserved == 0 and kind <= 3 and elements > 0
            full = 16 + payload + 32
            remaining = len(partial) - offset
            if remaining < full:
                assert kind > 0 and 16 <= remaining < 16 + payload, "K3 must leave an incomplete payload"
                break
            offset += full
            complete += 1
        restored = run(binary, "stage-c-recover", case)
        assert restored["epoch"] == 1 and restored["digest"] == baseline["digest"]
        report = {"status": "pass", "point": "c.k3.mid_record", "signal": "SIGKILL",
                  "population": 1000000, "variant": "S", "completeRecords": complete,
                  "partialRecordKind": kind, "partialRecordIndex": index,
                  "partialRecordBytes": remaining, "expectedRecordBytes": full,
                  "exactRecoveredDigest": True, "restoredEpoch": 1,
                  "scope": "bounded batched-writer K3 regression; not K1-K10 or C acceptance"}
    args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
