# Galaxy Z Flip5 SM-F731B (F731BXXS7GZF1) payload

Exact firmware: `F731BXXS7GZF1`, kernel
`5.15.189-android13-8-33404244-abF731BXXS7GZF1` (`android13-5.15`).

The ADB-shell tracefs route, root bootstrap, and KernelSU v3.2.5 late-load were
hardware-validated on 2026-09-22 and 2026-09-23. The app library is a Shizuku-free
fresh-P0 build with 4K slide-fingerprint coverage. This revision has compiled
but has not completed a device run. UID 2000 received root on the validated
ADB-shell path with SELinux Enforcing and the official Manager connected. See
the [validation record](../../docs/SM-F731B-F731BXXS7GZF1.md).

## Files and provenance

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `cve-2026-43499-app.so` | 170152 | `886c1f4134f2bb9688cc879beb3fa0683a068adc0b1f741fae5fd5fbdb9a47be` |
| `cve-2026-43499-root` | 27072 | `6a397067c4ac3841de01527d1f75219baa5ca6c4a6bc4b52c4408474e2456c82` |
| `../../kernelsu/ksud-b5q-F731BXXS7GZF1-kdp` | 4888048 | `0ba2bf39f163169319f0fe9cbb0236e572d99810d934587f8280a7e90ef5c521` |
| `../../kernelsu/android13-5.15.189_kernelsu-b5q-F731BXXS7GZF1-kdp.ko` | 381216 | `dd4a7d2cad7d45b367a93c68c2b8fbb74f3d300d7ddca1c276661115f27b8285` |

The published app payload library enables `APP_REQUIRE_FRESH_P0_SESSION`,
matching the personal feed's fresh-session profile. The root helper was rebuilt with Android NDK r29,
API 35, and is byte-identical to the hardware-tested file. The KernelSU pair
is the newer hardware-validated revision with both
[SELinux hiding](../../docs/SM-F731B-selinux-hide.md) and
[su compatibility](../../docs/SM-F731B-sucompat.md) fixes. It replaces the
userspace frontend and overlay workaround.

Selected [validation outputs](validation/) record the final module's
firmware audit, authorized/denied `su` behavior, and SELinux hiding regression.

The previous app library's 64K slide table omitted the latest run's
`0x178000` slide. Its logged P0 sample scores 8/8 against the exact local
kernel image with runner-up 0 in this 4K table (the old table scores 0/8).
The physical alias is therefore confirmed; app-domain root completion remains
pending an end-to-end device run.

## Build

```sh
make TARGET=b5q-F731BXXS7GZF1 ANDROID_NDK_HOME=/path/to/android-ndk-r29 all
```

`all` builds the standalone and app payloads, the root helper with
`--allow-shell` selected for the initial late-load.
The shared Makefile's fixed-size `release` target is still capped at 104128
bytes, which is too small for this target's expanded fingerprint table. The
published app library is the regular build with fresh-P0 enforcement and the
expanded 4K fingerprint table.

## Integration status

- Validation covers ADB-shell execution on this exact firmware. Direct
  app-domain execution of the current library remains pending; the profile
  does not require Shizuku.
- The exact `0xa8000000` physical alias is confirmed by the latest P0 sample
  at slide `0x178000`; end-to-end app-domain root handoff remains unverified.
- Kernel `su_compat` supplies the conventional `su` path for authorized UIDs
  without a real `/system/bin/su` file or `/system/bin` overlay. Use a fresh
  boot when upgrading from the old overlay-based build and do not restore
  that overlay.
- Root and the late-loaded module are per-boot. Select `--allow-shell` on the
  initial load; the recorded unload/reload experiment hung the device.
