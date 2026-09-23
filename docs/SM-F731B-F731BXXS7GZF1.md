# SM-F731B — F731BXXS7GZF1

Galaxy Z Flip5 (international, `b5q`) on firmware `F731BXXS7GZF1`
(`BP4A.251205.006/F731BXXS7GZF1`, June 2026 patch), kernel
`5.15.189-android13-8-33404244-abF731BXXS7GZF1`.

Status: **hardware verified from ADB shell** — the tracefs slide route, controlled
reclaim, MCAST stack writer, fake fops, configfs read/write, pipe physical
read/write, root UMH, KernelSU late-load, and trusted Manager connection all
completed on the exact firmware. The current personal feed uses a fresh-P0
build for direct app execution without Shizuku; that binary has not completed
an end-to-end device run.

The [published artifacts](../artifacts/b5q-F731BXXS7GZF1/README.md) retain
the hardware-validated root helper and the current unverified fresh-P0 app
library. The current
KernelSU pair includes the hardware-validated SELinux hiding and `su_compat`
fixes described below; the earlier frontend and overlay are superseded.

## Kernel and platform

- SoC: Snapdragon 8 Gen 2 (SM8550)
- Kernel: `5.15.189-android13-8-33404244` — the **same 5.15.189 KMI/version
  family** as the S23 Ultra (S918B FZF5, build 33413713) and S23+ (S916B
  FZG1), but not the same Samsung build. The sampled `.text` functions used by
  this profile have matching offsets and bytes; whole-image byte identity is
  not established because the S918B kernel Image is not present in this
  workspace. Several `.data` symbols demonstrably differ.
- KMI: `android13-5.15`, toolchain clang 14.0.7
- Boot image: 100663296 bytes (100 MiB)
- Kernel Image: 46860800 bytes
  SHA-256: `BAC978D97C5A0D269EEE11B22EB1A770416AEF6DFC3C7B80B91430F526AE6648`
- Raw BTF: `[0x21ef2ac, 0x27bf188)` (5,963,484 bytes)
  SHA-256: `047909BAE9B9AA860473870CBD3EABDDE23C468088461802745C29D3C508023D`

## The pselect roadblock and MCAST solution

The standard pselect fd_set stack-overlay route **does not work** on this
5.15 kernel. The futex waiter sits at S−0x2D8 while pselect's fd_set buffer
covers only S−0x210 to S−0x110 — a 0xC8-byte gap makes the waiter's first
qword (`tree_entry.__rb_parent_color`, the write destination) unreachable.

The sendmmsg combined-vehicle route (plant with failing sendmmsg at S−0x2C8,
dwell with nanosleep) covers qwords 2–10 but always zeroes qword 0 via the
msghdr clear. Without controlling qword 0, the write primitive has no target.

The solution is the **MCAST stack writer** (`setsockopt(MCAST_JOIN_SOURCE_GROUP)`),
hardware-verified on the S918B (S23 Ultra) profile:

```text
setsockopt chain: sys 0x10 + __sys 0x70 + sock_common 0x10 +
  ipv6_setsockopt 0x40 + do_ipv6_setsockopt 0x2c0 = 0x390
greqs @ do_ipv6 sp+0x40 = S0−0x350
waiter @ S0−0x2D8
MCAST_WAITER_OFF = 0x350 − 0x2D8 = 0x78
```

The callback is `ipv6_setsockopt`, whose `0x40` frame directly calls
`do_ipv6_setsockopt`. Its Flip5 frame is confirmed in `vmlinux`: a
pre-indexed `stp` of `0x60` followed by `sub sp, #0x260`, totaling `0x2c0`.
The arithmetic yields the same MCAST offset as S23 Ultra. Hardware validation
confirmed `MCAST_WAITER_OFF=0x78`: the scheduler window opened with the expected
`ret=-1 errno=99`, after which the fake-fops, configfs, pipe-physrw, and root
UMH stages all completed.

## .data symbol differences vs S918B

The sampled `.text` routines match; the `.data` symbol offsets differ as below:

| Symbol | b5q | S918B | Delta |
|---|---|---|---|
| ASHMEM_FOPS | 0x200d3f8 | 0x200d5b8 | +0x1c0 |
| ANON_PIPE_BUF_OPS | 0x1e7f3a0 | 0x1e7f560 | +0x1c0 |
| KMALLOC_CACHES | 0x20643b8 | 0x2064578 | +0x1c0 |
| NFULNL_LOGGER_NAME | 0x1d5dbe6 | 0x1d5dd96 | +0x1b0 |
| NFULNL_LOGGER_OBJ | 0x2a91e48 | 0x2a91e48 | 0 |
| INIT_TASK | 0x2c05080 | 0x2c05080 | 0 |
| SELINUX_ENFORCING | 0x2d8e5c0 | 0x2d8e5c0 | 0 |

## P0 candidate address

`P0_KERNEL_PHYS_LOAD = 0xa8000000` — **CANDIDATE, not device-confirmed**.

Reasoning: the ABL constant tables are byte-identical between this platform
and the S25, both have DDR at 0x80000000, and 0xa8000000 is the value the
ABL chose on the S25. The P0 fingerprint is a clean pass/fail oracle: a
wrong base aliases a page that is not kernel image, the score stays low,
and `scan_p0_pipe_oracle` fails into the restore path.

## P0 fingerprint

32 candidates at 0x10000 step. The hardware run observed a VA slide of
`0x108000` through tracefs. That value is not 64K-aligned, so it does not by
itself validate the physical-placement model; the P0 oracle remains the
required test. The candidate table still covers the full `[0, 0x1F0000]`
range at 0x10000 steps.

## Build

```sh
make TARGET=b5q-F731BXXS7GZF1 ANDROID_NDK_HOME=/path/to/android-ndk
make TARGET=b5q-F731BXXS7GZF1 ANDROID_NDK_HOME=/path/to/android-ndk release
```

## Hardware validation

Validated on `SM-F731B`, running the exact
`F731BXXS7GZF1` build on 2026-09-22. The successful run recovered a KASLR slide
of `0x108000` through tracefs and ended with `done=1 root=1 uid=2000->0`.
The root helper reported `uid=0(root)` in `u:r:kernel:s0`; its temporary
permissive state was restored to Enforcing by the KernelSU late-load flow.

Captured device evidence:

These files are retained in the local validation workspace and are not
included in this repository.

| File | SHA-256 |
| --- | --- |
| `build/b5q-F731BXXS7GZF1/device-full.log` | `7CF1B31EEF5EF3DFBFC40439CDCAE77752C8C53A97E22BBF6C498F85214976AB` |
| `build/b5q-F731BXXS7GZF1/config.gz` | `F3285FF8A19F501A2DE3D878FCC936B7B1F78E870AF4906455B3910696F191CE` |
| `build/b5q-F731BXXS7GZF1/kallsyms.txt` | `A0E8D4D356D91A586139B402F39A3FE085727E36281746D081DE6C5DA927668F` |

## KernelSU late-load

The exact KernelSU v3.2.5 module uses the full target release string and the
Samsung KDP/RKP/DEFEX compatibility path. RKP syscall-table writes and live
text patching are disabled. The original module's 200 imports were audited
against the recovered target `vmlinux` and live `kallsyms`. The current
[su compatibility revision](SM-F731B-sucompat.md), which includes the
[SELinux hide fix](SM-F731B-selinux-hide.md), has 205 imports, all present
in the recovered target, with zero CRC mismatches. Plain `insmod` is not supported;
the matched `ksud` performs kallsyms-aware relocation and load.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `kernelsu/android13-5.15.189_kernelsu-b5q-F731BXXS7GZF1-kdp.ko` | 381216 | `DD4A7D2CAD7D45B367A93C68C2B8FBB74F3D300D7DDCA1C276661115F27B8285` |
| `kernelsu/ksud-b5q-F731BXXS7GZF1-kdp` | 4888048 | `0BA2BF39F163169319F0FE9CBB0236E572D99810D934587F8280A7E90EF5C521` |
| Official KernelSU v3.2.5 Manager APK (not bundled) | 9083665 | `1417081413BF7AB1DE8E440ECBCB62685037C8F28F048F0F8B79E305B31AB916` |
| `build/b5q-F731BXXS7GZF1/cve-2026-43499-root` (`--allow-shell` build) | 27072 | `6A397067C4AC3841DE01527D1F75219BAA5CA6C4A6BC4B52C4408474E2456C82` |

The original hardware late-load left
`kernelsu 208896 1 - Live 0x0000000000000000 (OE)` in `/proc/modules` under
Enforcing SELinux. The installed Manager is v3.2.5 (`versionCode=32525`); its
v2 signing-certificate SHA-256 is
`c371061b19d8c7d7d6133c6a9bafe198fa944e50c1b31c9d8daa8d7f1fc2d2d6`,
which exactly matches the module's compiled Manager trust hash. Manager startup
logged `KsuCli install result: true`, and its open control FD raised the module
reference count from zero to one.

The 2026-09-23 validation reran the exploit after a clean reboot and passed
`--allow-shell` on the **initial** matched late-load. The live kernel log then
reported `KernelSU: allow root for: 2000`, and an unprivileged ADB shell
successfully ran `ksud debug su` as
`uid=0(root) gid=0(root) context=u:r:ksu:s0` while SELinux remained Enforcing.
The captured exploit log is
`build/b5q-F731BXXS7GZF1/device-allow-shell-full.log` (SHA-256
`24CEF7F80FC4A483230C7C75CDFA34D1EC2563DD1CDC7DDAC1C66523278126DD`).

The current no-patch-text Samsung build supports kernel `su_compat` through
the existing syscall probes. Its initialization now resolves the syscall
table read-only before returning at the RKP guard. Authorized callers can
use the conventional `su` path without a real file or an overlay. The
previous userspace `su` frontend overlay workaround is superseded and should
not be restored. Hardware verification:

```sh
adb shell su -c id
# uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0
```

`command -v su` reports `/system/bin/su`; `su -v` reports
`3.2.5:KernelSU`, `su -V` reports `32525`, and SELinux remains Enforcing.
The denied Native Root Detector UID receives `ENOENT` from lookup and
execution of `/system/bin/su`. There is no `/system/bin` mount, and the
SELinux hide regression probe still passes. The user confirmed Native Root
Detector reports a normal environment. See the
[validation notes](SM-F731B-sucompat.md) for the tests and evidence.

Do not unload and reload the live module merely to change `allow_shell`: the
device hung during that experiment and required a manual reboot. Select
`--allow-shell` on the first late-load after running the exploit instead.

This is a per-boot late-load. The locked boot image was not modified, so a
reboot removes the live module and requires the exploit plus matched late-load
sequence again. The target `ksud` remains staged in `/data/local/tmp`; the
official Manager may replace `/data/adb/ksud` with its stock daemon.

## Open items

1. Device validation of `P0_KERNEL_PHYS_LOAD` (`0xa8000000` candidate)
2. Upstream Root My Galaxy app packaging and support-feed integration
3. A persistent boot integration, if the bootloader is later unlocked
