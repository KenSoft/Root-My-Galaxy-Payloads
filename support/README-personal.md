# KenSoft SM-F731B feed

Branch `personal/sm-f731b` publishes a dedicated schema-v3 catalog for
SM-F731B firmware `F731BXXS7GZF1`, kernel `5.15.189`. The upstream PR remains
on `feat/b5q-f731bxxs7gzf1`; this personal feed does not depend on its merge.

The catalog references a fresh-P0 app-library build and the matched
KernelSU daemon in this fork. The app library is intended for direct app
execution without Shizuku and has not completed an end-to-end hardware run.
The personal Android app resolves this branch to a commit and downloads both
artifacts from that same commit.

The current daemon includes the hardware-validated SELinux hiding and
`su_compat` fixes. The old userspace frontend and `/system/bin` overlay are
superseded. Use a fresh boot when switching from that earlier deployment;
the existing custom APK can fetch this updated pair without rebuilding.

The app bundles the matching root helper from
`artifacts/b5q-F731BXXS7GZF1/cve-2026-43499-root` and honor
`requiresFreshP0Session` so it does not substitute a cached physical address.
The personal profile does not require Shizuku. Recorded validation was
launched from ADB shell; direct app-domain execution and the full personal-app
flow still need a device run. The existing custom APK fetches this branch's
current catalog and artifacts dynamically, so its binary does not need a
rebuild for payload updates.
