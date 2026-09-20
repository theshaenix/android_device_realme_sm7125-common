# SM7125 thermal HAL

Device-owned copy of LineageOS/QTI's AIDL thermal HAL, from
`LineageOS/android_hardware_qcom_thermal`, branch `lineage-23.2-legacy-um`,
commit `4a1526223983c5db137d0b87e8c2e1a752d2b72c`. Copyright and license
notices are retained in each source file.

Local differences:

- Add SoC ID 443 to the existing lito/atoll sensor configuration. CPU, GPU,
  and XO sensor names were checked against RMX2061 recovery sysfs.
- Build the legacy uevent backend. This device's 4.14 thermal UAPI does
  not implement the newer generic-netlink events used by the other backend.
- Store the initialized sensor state in the lookup map.
- Initialize the limit-profile value for SoCs without a profile override.
- Keep the next-trip sentinel as a float so NaN remains representable;
  convert to an integer only when writing a valid trip to sysfs.
- Select a uniquely named build module while retaining the original binary
  filename, service name, and VINTF instance for existing SELinux policy.

The vendor thermal-engine and kernel thermal protection remain responsible
for their existing mitigation policies. This is not new thermal calibration:
the existing upstream atoll reporting thresholds are retained.

Build in the ROM checkout:

```sh
m android.hardware.thermal-service.realme_sm7125
```

After flashing, check `dumpsys thermalservice` for real CPU/GPU/skin readings
and threshold entries, and check logcat for sensor initialization failures
and SELinux denials. Reporting and callbacks still require device validation;
a source/build check cannot establish their runtime correctness.
