# RIL hot-swap fixup

`fix-ril-hotswap.py` guards the null radio instance in the arm64
`oemHotswapProcessInd(int, int)` forwarding thunk. The boot tombstone has
build ID `d384501c5a950aa2c25f3f853fc49488`, a null `x0`, and a fault at the
member function's `ldr x0, [x0, #0x18]`. The exact matching local blob was
disassembled before preparing this patch.

The reordered six-instruction thunk preserves both arguments and the
existing non-null tail call. A null instance returns through the existing
frameless `ret`; it cannot receive a callback before it exists. No radio
service, SIM slot, or initialized hot-swap callback is disabled.

The fixup accepts only the recorded SHA-256 or its exact patched output.
It refuses other firmware versions and is idempotent. Extraction applies
it automatically; an already-generated vendor checkout must be updated too:

```sh
python3 device/realme/sm7125-common/tools/fix-ril-hotswap.py \
    vendor/realme/sm7125-common/proprietary/vendor/lib64/libril-qc-hal-qmi.so
```

Do not change the checksum to accept a different blob without disassembling
and validating that blob. Test dual-SIM startup and SIM hot-swap after
flashing. Host patch checks and disassembly do not replace device testing.
