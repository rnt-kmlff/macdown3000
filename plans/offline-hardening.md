# Local fork security design

Status: design approved by an independent reviewer; implementation and native
verification in progress. No merge or installation approval is implied.

Base: upstream main `2d582fa10a2684ff180acd5094b8dd7380a41d03`.
Scope: a locally installed Markdown editor with offline previews and a patched
metadata parser. This is a material security/dependency change.

## Required outcomes

1. Opening an untrusted document does not invoke LibYAML 0.1.4. Ordinary YAML
   front matter remains readable, malformed input fails safely, and repeated
   malformed inputs release parser state. Input size and cyclic alias graphs
   cannot cause unbounded conversion in the Objective-C wrapper.
2. Viewing/editing Markdown or using Finder preview does not automatically
   request web resources. Remote images, CSS imports, media, fonts, scripts,
   fetch/XHR, redirects and scripted navigations must fail closed. Local and
   embedded images, code highlighting, checkboxes and diagrams still work.
   An explicit click on an HTTP(S) link may open the user's browser. Remote
   images remain in the source but do not load. No online-mode switch in v1.
3. Math rendering either works entirely from bundled files or shows an explicit
   limitation; it must never silently fall back to a CDN.
4. The fork cannot replace the official app, adopt its preferences, or update
   itself from its feed. The candidate is visibly distinct, uses separate app,
   extension and framework identifiers, and has no active updater.
5. A reviewed exact revision can be tested and packaged without Apple secrets
   or private documents. Installation/default-file association remains a
   separate decision tied to the verified artifact. No Gatekeeper disabling.

## Proposed implementation

- Pin LibYAML 0.2.5 through an in-repository podspec with an HTTPS source archive
  and SHA-256. Preserve the lockfile; add a runtime version assertion and
  regression fixtures for long tags/percent escapes, normal metadata and
  malformed data. Before composition with yaml_parser_load, preflight the event
  stream with a 64 KiB input limit, depth <= 64 and <= 4096 events. Reject alias
  events before composition (aliases, including cycles, are unsupported in v1).
  This also bounds the nesting DoS in LibYAML 0.2.5 before composition. Accept
  scalar map keys only and clean up both parsers on every error path.
- Restrict the generated preview CSP to local/data resources and no network
  connections. Also reject nonlocal resource requests at the legacy WebView
  resource delegate, including redirects, and block non-click navigations away
  from the document. Keep existing executable-link guards. Require a trusted
  native user event before opening any external link; navigation type alone is
  insufficient because script element.click() can report LinkClicked. Allow
  only HTTP(S) external browser links, not arbitrary custom schemes. If native
  user activation cannot be established reliably, disable external opening.
  The SDK has no public original-event token: implement this fallback and
  expose explicit native context-menu actions for HTTP(S)/safe local links.
  Remove stock WebKit open/download menu actions. Permit only the generated
  base URL and its fragments in preview navigation, never a sibling HTML page.
  Finder preview already
  disables JS/connections; remove its network entitlement as defense in depth.
- Prepare a complete official MathJax 2.7.9 distribution at build time from a
  pinned, hash-verified archive into an ignored bundle directory. Use a local
  loader/configuration and fonts; no CDN URLs or network fallback. Archive
  extraction must reject traversal/links and have a bounded unpacked size.
- Use the display name `MacDown Local` and identifiers rooted at
  `io.github.rnt-kmlff.macdownlocal`; isolate application support/preferences,
  CLI identity and URL scheme. Remove the legacy preference migration, not just
  its bundle identifiers. Remove upstream feed/key and disable updater
  creation/start/menu actions. Remove the unused Sparkle dependency, its
  framework-embedding build phase and unused controller property. Assert that
  neither its framework nor runtime classes exist and that the release binary
  has no Sparkle linkage. Keep release automation from publishing or
  uploading to upstream; produce a candidate artifact only.
- Extend real renderer/delegate and metadata tests, with local fixtures and a
  request-counting synthetic protocol/server. Tests must detect removal of CSP
  restrictions or delegate checks; assert local image and bundled math success,
  and test DOM link clicks versus actual native menu construction/actions.
  Update prior tests that intentionally allowed web images to reflect the new
  requirement and retain positive image coverage.
- Build/test on GitHub-hosted macOS because local full Xcode is absent. Use
  read-only workflow permissions and no deployment credentials. Run focused
  security coverage and the existing unit suite, build a universal Release
  candidate, package with exact commit/dependency/checksum metadata, then verify
  downloaded contents locally. Self-built signing/notarization limitations must
  remain explicit. A successful build alone does not authorize installation.

## Alternatives and boundaries

Retaining the old parser or relying on CSP alone does not meet the outcomes.
Removing all metadata/math would reduce compatibility unnecessarily. Full
WKWebView migration, App Sandbox conversion and a comprehensive audit of every
dependency are outside this change; these remain residual risks. Access to a
user-selected network-mounted document can cause filesystem traffic outside
the preview's web-request controls. HTML exports may reference remote resources
when the user later opens them in another application; the offline guarantee
applies to this application's previews, not arbitrary exported content.

## Review and activation gates

The fork owner explicitly approved an independent Codex reviewer in place of the upstream
CLAUDE.md requirement for Opus reviewers in this chat on 15 October 2026. All
other two-person design/implementation gates remain. Reviews must cover the
whole diff against the base above; no commit/push before implementation review.

| Mandatory criterion | Current evidence |
| --- | --- |
| Design independently reviewed | Met; reviewed plan SHA-256 `53301e1b2cf9ad57684db293e1ad9cdcef112cb9b8e69b3b3687d38af77ae0b5` |
| Parser source/version and hostile-input tests | Partial; local sanitized C harness passed; native wrapper tests await CI |
| No automatic preview web requests; local features work | Partial; native delegate/WebView tests prepared; CI pending |
| Fork identity/update isolation | Partial; separate identifiers/support/CLI, no updater created; CI pending |
| Native tests and candidate build for exact revision | Pending |
| Independent full-diff implementation review | Pending |
| Exact downloaded package, signing and rollback recorded | Pending |
| Owner merge and exact-build installation approval | Pending |

Rollback: retain any existing app/default association; install under a separate
name only after approval, with a receipt recording the previous association and
exact artifact hash. Removing the fork restores the previous application choice.
Do not overwrite documents, use private fixtures, request Full Disk Access, or
claim that tests establish security certification.

## Initial local verification

- `python3 Tools/test_yaml_safety.py --archive <verified local archive>`: PASS
  with AddressSanitizer and UndefinedBehaviorSanitizer. Covers normal/empty
  data, aliases, nesting boundary, byte/event limits, long tags/URI escapes
  and 1000 malformed-input/recovery cycles.
- `python3 Tools/test_offline_mathjax.py`: PASS, three tests including traversal,
  absolute paths, symlink/hardlink rejection, incomplete distribution and
  preservation of previous assets on checksum failure.
- Official MathJax package integrity matched npm's SHA-512 metadata and pinned
  SHA-256; preparation verified 1859 local assets.
- Project/plist/workflow syntax and `git diff --check`: PASS.
- Local native app/XCTest/archive: SKIPPED because full Xcode is absent. Hosted
  macOS 14/26 native tests and a universal Release archive are required next.
- Sparkle is absent from the dependency recipe and framework-embedding phase.
  Native tests require its framework and runtime classes to be absent before
  and after startup/update actions; release CI also rejects Sparkle linkage.
  No feed/key is configured and the localized update action stays disabled.
- Candidate packages remain unsigned until locally prepared for review. No
  Developer ID/notarization claim and no installed/default-app change.

Implementation review identified and required fixes for the unsupported legacy
WebKit original-event key, sibling-HTML navigation, and a duplicate workflow
condition. The implementation now uses the reviewed native-menu fallback,
restricts navigation to the generated page/anchors, and combines the workflow
conditions. A fresh whole-diff review is required before publication. Upstream's
legacy smoke workflow is disabled in the fork because it tests retired migration
behavior; native unit checks and the universal candidate build are the active
fork checks.

The updater-removal design received independent approval before implementation.
The `c1e2fad` package is retained only as earlier verification evidence, with
1339 native tests passing on each macOS 14/26 runner. It is not the installation
candidate: the replacement must contain no Sparkle dependency and must pass a
fresh full implementation review, exact-head CI and downloaded-artifact checks.
