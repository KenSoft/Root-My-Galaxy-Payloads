# KenSoft SM-F731B feed

Branch `personal/sm-f731b` publishes a dedicated schema-v3 catalog for
SM-F731B firmware `F731BXXS7GZF1`, kernel `5.15.189`. The upstream PR remains
on `feat/b5q-f731bxxs7gzf1`; this personal feed does not depend on its merge.

The catalog references the exact hardware-validated app library and matched
KernelSU daemon in this fork. The personal Android app resolves this branch
to a commit and downloads both artifacts from that same commit.

The app must bundle the matching root helper from
`artifacts/b5q-F731BXXS7GZF1/cve-2026-43499-root` and honor
`requiresFreshP0Session` so it does not substitute a cached physical address.
The personal build retains both normal and Shizuku execution modes.
Recorded validation was launched from ADB shell; direct app-domain execution
and the full personal-app flow have not been verified by this build step.
