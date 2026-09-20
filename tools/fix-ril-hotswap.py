#!/usr/bin/env python3
"""Guard the null Oplus radio instance in the verified RMX2061 arm64 blob."""
import hashlib
from pathlib import Path
import struct
import sys

ORIGINAL_SHA256 = '0d14d71f3ca95069d893fd748c14536310e9542cd7cc2e204e02f37f40fde376'
ORIGINAL = struct.pack('<6I', 0xb00092e8, 0xf9429508, 0x2a0103e2,
                       0x2a0003e1, 0xaa0803e0, 0x144623ef)
# Preserve w0/w1 as w1/w2 before loading this into x0. Skip the tail call
# only when this is null, using the verified frameless ret at thunk + 0x38.
REPLACEMENT = struct.pack('<6I', 0x2a0103e2, 0x2a0003e1, 0xb00092e8,
                          0xf9429500, 0xb4000140, 0x144623ef)


def patch(data):
    if data.count(REPLACEMENT) == 1:
        offset = data.index(REPLACEMENT)
        original = data[:offset] + ORIGINAL + data[offset + len(ORIGINAL):]
        if hashlib.sha256(original).hexdigest() == ORIGINAL_SHA256:
            return data
    if hashlib.sha256(data).hexdigest() != ORIGINAL_SHA256:
        raise ValueError('unsupported RIL blob; refusing an unverified binary patch')
    if data.count(ORIGINAL) != 1:
        raise ValueError('expected RIL thunk is not unique')
    offset = data.index(ORIGINAL)
    if data[offset + 0x38:offset + 0x3c] != struct.pack('<I', 0xd65f03c0):
        raise ValueError('expected frameless return instruction is missing')
    return data[:offset] + REPLACEMENT + data[offset + len(ORIGINAL):]


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('usage: fix-ril-hotswap.py LIBRIL_QC_HAL_QMI_SO')
    path = Path(sys.argv[1])
    try:
        original = path.read_bytes()
        updated = patch(original)
        if updated != original:
            path.write_bytes(updated)
    except (OSError, ValueError) as error:
        sys.exit(str(error))
