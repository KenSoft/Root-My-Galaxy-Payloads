# Galaxy Z Flip5 SM-F731B (F731BXXS7GZF1) payload

Exact firmware: `F731BXXS7GZF1`, kernel
`5.15.189-android13-8-33404244-abF731BXXS7GZF1` (`android13-5.15`).

The recorded hardware runs on 2026-09-22 and 2026-09-23 completed the tracefs
route from ADB shell, root bootstrap, and KernelSU v3.2.5 late-load. UID 2000
received root with SELinux Enforcing and the official Manager connected.
See the [validation record](../../docs/SM-F731B-F731BXXS7GZF1.md).

## Files and provenance

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `cve-2026-43499-app.so` | 133760 | `651f630844905b7969c445366926404ac4fbee86c550d17d69ce01000f00cba0` |
| `cve-2026-43499-root` | 27072 | `6a397067c4ac3841de01527d1f75219baa5ca6c4a6bc4b52c4408474e2456c82` |
| `../../kernelsu/ksud-b5q-F731BXXS7GZF1-kdp` | 4888048 | `0ba2bf39f163169319f0fe9cbb0236e572d99810d934587f8280a7e90ef5c521` |
| `../../kernelsu/android13-5.15.189_kernelsu-b5q-F731BXXS7GZF1-kdp.ko` | 381216 | `dd4a7d2cad7d45b367a93c68c2b8fbb74f3d300d7ddca1c276661115f27b8285` |

The published app payload library is the exact binary validated successfully
on SM-F731B hardware. The root helper was rebuilt with Android NDK r29,
API 35, and is byte-identical to the hardware-tested file. The KernelSU pair
is the newer hardware-validated revision with both
[SELinux hiding](../../docs/SM-F731B-selinux-hide.md) and
[su compatibility](../../docs/SM-F731B-sucompat.md) fixes. It replaces the
userspace frontend and overlay workaround.

Selected [validation outputs](validation/) record the final module's
firmware audit, authorized/denied `su` behavior, and SELinux hiding regression.

The validated library was built in the development checkout, which also
contained local diagnostic probes. This PR retains upstream shared sources
without those probes. Fresh `all` and `release` builds pass, but the rebuilt
library is not byte-identical to the published hardware-validated artifact.

## Build

```sh
make TARGET=b5q-F731BXXS7GZF1 ANDROID_NDK_HOME=/path/to/android-ndk-r29 all release
```

`all` builds the standalone and app payloads, the root helper with
`--allow-shell` selected for the initial late-load.
`release` builds the size-limited app library separately. The library shipped
here is the hardware-validated regular build retained from the development
checkout, as described above.

## Integration status

- Validation covers ADB-shell execution on this exact firmware. Direct
  app-domain execution and upstream support-feed integration remain pending.
- The physical-P0 fallback and its `0xa8000000` load-address candidate remain
  unverified. The successful runs used tracefs.
- Kernel `su_compat` supplies the conventional `su` path for authorized UIDs
  without a real `/system/bin/su` file or `/system/bin` overlay. Use a fresh
  boot when upgrading from the old overlay-based build and do not restore
  that overlay.
- Root and the late-loaded module are per-boot. Select `--allow-shell` on the
  initial load; the recorded unload/reload experiment hung the device.
