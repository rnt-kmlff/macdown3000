# MacDown Local fork

Follow CLAUDE.md and CONTRIBUTING.md except for this owner-approved reviewer
substitution: independent Codex reviewers replace Opus reviewers in this fork.
Keep the separate design and full-implementation review gates. No writer may
approve their own changes; no commit/push before implementation review.

Security hardening is material. Record scope, exact base/revision, meaningful
tests, skipped checks and remaining risks. Work on one isolated feature branch
with one writer. Do not use real/private documents in fixtures, CI or reports.

The owner approves merge and exact-build installation separately. Do not
auto-merge, change default file associations or replace an installed app before
that approval. Never disable Gatekeeper globally or request Full Disk Access.

Prepare offline assets with `python3 Tools/prepare_offline_mathjax.py` before
building. Run `python3 Tools/test_yaml_safety.py`,
`python3 Tools/test_offline_mathjax.py` and the existing native XCTest suite.
The verified dependency assets are generated locally, not committed binaries.

This fork uses manual reviewed builds. Upstream signing, appcast and website
publication workflows must stay disabled here. See plans/offline-hardening.md.
