# Galaxy Z Flip5 SM-F731B (F731BXXS7GZF1) payload

Exact firmware: `F731BXXS7GZF1`, kernel
`5.15.189-android13-8-33404244-abF731BXXS7GZF1` (`android13-5.15`).

The ADB-shell tracefs route, root bootstrap, and KernelSU v3.2.5 late-load were
hardware-validated on 2026-09-22 and 2026-09-23. The Shizuku-free app library
uses fresh P0 discovery with 4K slide-fingerprint coverage. Its first device
run reached the FOPS handoff but did not complete; a stale slide-bank selection
was found and fixed in this revision. The fix is compiled but still needs a
device retest. UID 2000 received root on the validated ADB-shell path with
SELinux Enforcing and the official Manager connected. See the
[validation record](../../docs/SM-F731B-F731BXXS7GZF1.md).

## Files and provenance

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `cve-2026-43499-app.so` | 170136 | `508af8ecdf09e33f06a9b532c6e3a9f187d3053ac5eb9cc5ef63eee17a0fe8fa` |
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
The physical alias is therefore confirmed. A later app-domain run accumulated
the full 32-entry controlled-mm group in both stages (47 attempts for P0 and
85 for FOPS); the logged 0–3 collision messages are per-attempt misses, not the
final group size. It completed P0 discovery and prepared the FOPS page, then
stopped during the FOPS PI handoff before the phone rebooted.

The route audit found that `APP_CLOSED_FOPS_ROUTE` prepares its fake lock,
task, parent, and target for the new `PAGE_PAYLOAD_FOPS` page, but the fresh-P0
trigger then called `select_slide_payload_index(0)`. That selector still
described the earlier `PAGE_PAYLOAD_SLIDE` page and overwrote the new route
state. The fixed closed route now keeps the fields prepared for the FOPS page.
The reboot reason remains unconfirmed because Android exposed only the generic
`reboot` reason and the available ADB shell could not read a preserved kernel
crash record. App-domain root completion still needs a hardware retest of this
revision.

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
