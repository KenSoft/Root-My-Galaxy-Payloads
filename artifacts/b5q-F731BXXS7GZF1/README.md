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
| `ksu-su` | 7496 | `e28d19384c71e9a646740b22ac699a57d7ca828337c69b61421e4e9a5ffe26f3` |
| `../../kernelsu/ksud-b5q-F731BXXS7GZF1-kdp` | 4886944 | `a9086788d602539e09ec88194947e0e9591c3958172b1c746b45b61c2a715db5` |
| `../../kernelsu/android13-5.15.189_kernelsu-b5q-F731BXXS7GZF1-kdp.ko` | 377160 | `d652b6529eb8892b23bbd0bb34b20875cf3e49e4c32d32df7038a7a10f694548` |

The published app payload library is the exact binary validated successfully
on SM-F731B hardware. The KernelSU pair is also unchanged from that validation.
The root helper and frontend were rebuilt with Android NDK r29, API 35, and
are byte-identical to the hardware-tested files.

The validated library was built in the development checkout, which also
contained local diagnostic probes. This PR retains upstream shared sources
without those probes. Fresh `all` and `release` builds pass, but the rebuilt
library is not byte-identical to the published hardware-validated artifact.

## Build

```sh
make TARGET=b5q-F731BXXS7GZF1 ANDROID_NDK_HOME=/path/to/android-ndk-r29 all release
```

`all` builds the standalone and app payloads, the root helper with
`--allow-shell` selected for the initial late-load, and the `ksu-su` frontend.
`release` builds the size-limited app library separately. The library shipped
here is the hardware-validated regular build retained from the development
checkout, as described above.

## Integration status

- Validation covers ADB-shell execution on this exact firmware. Direct
  app-domain execution and support-feed integration remain pending.
- The physical-P0 fallback and its `0xa8000000` load-address candidate remain
  unverified. The successful runs used tracefs.
- The root helper does not install a `/system/bin` overlay automatically.
  The recorded `su -c id` check used a manually installed per-boot overlay
  exposing `ksu-su`, with the matched daemon also staged at
  `/data/local/tmp/ksud-b5q-kdp-v2`.
- Root and the late-loaded module are per-boot. Select `--allow-shell` on the
  initial load; the recorded unload/reload experiment hung the device.
