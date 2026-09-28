# KenSoft SM-F731B feed

Branch `personal/sm-f731b` publishes a dedicated schema-v3 catalog for
SM-F731B firmware `F731BXXS7GZF1`, kernel `5.15.189`. The upstream PR remains
on `feat/b5q-f731bxxs7gzf1`; this personal feed does not depend on its merge.

The catalog references a fresh-P0 app-library build and the matched
KernelSU daemon in this fork. The app library is intended for direct app
execution without Shizuku. Direct app-domain root and KernelSU late-load have
completed end to end on the exact firmware; the route remains probabilistic,
and the current three-page/holder candidate still needs repeated runs.
The personal Android app resolves this branch to a commit and downloads both
artifacts from that same commit.

The current daemon includes the hardware-validated SELinux hiding and
`su_compat` fixes. The old userspace frontend and `/system/bin` overlay are
superseded. Use a fresh boot when switching from that earlier deployment;
the existing custom APK can fetch this updated pair without rebuilding.

The app bundles the matching root helper from
`artifacts/b5q-F731BXXS7GZF1/cve-2026-43499-root` and honors
`requiresFreshP0Session` so it does not substitute a cached physical address.
The personal profile does not require Shizuku. Recorded validation covers both
ADB-shell and direct app-domain execution, including the full personal-app
handoff. The existing custom APK fetches this branch's current catalog and
artifacts dynamically, so its binary does not need a rebuild for payload
updates.
