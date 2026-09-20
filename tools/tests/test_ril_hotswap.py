#!/usr/bin/env python3
"""Run against the unmodified vendor blob; never modifies the supplied file."""
import importlib.util
from pathlib import Path
import sys

script = Path(__file__).resolve().parents[1] / 'fix-ril-hotswap.py'
spec = importlib.util.spec_from_file_location('fix_ril', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original = Path(sys.argv[1]).read_bytes()
updated = module.patch(original)
assert updated != original and len(updated) == len(original)
offset = original.index(module.ORIGINAL)
assert updated[:offset] == original[:offset]
assert updated[offset + 24:] == original[offset + 24:]
assert module.patch(updated) == updated
for invalid in (original + b'x', updated + b'x', b'not an ELF'):
    try:
        module.patch(invalid)
    except ValueError:
        pass
    else:
        raise AssertionError('unrecognized blob was accepted')
print('RIL patch: exact scope, idempotence and unknown-blob rejection passed')
