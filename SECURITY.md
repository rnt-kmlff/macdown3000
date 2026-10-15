# MacDown Local security boundaries

This fork blocks automatic HTTP(S) and other nonlocal preview resource requests
and redirects. Its preview CSP permits local/data images and media, local styles
and scripts, and no network connections. Finder preview has JavaScript disabled
and no network entitlement. Web images stay in the document source but do not
load. Opening a link in the browser requires the native context-menu action
`Open Link in Browser`. Ordinary clicks cannot leave the protected preview;
script-generated clicks and arbitrary URL schemes are denied. Local file links
use `Open Local Link`, retaining executable-file guards. Same-page anchors work.
Only copy commands and the application's reload action are retained from
WebKit's default preview menu. Unknown/private actions are rejected.

MathJax 2.7.9 is bundled from a pinned, hash-verified source archive, including
its configuration, extensions, renderers and fonts. There is no CDN fallback.
Build with `python3 Tools/prepare_offline_mathjax.py` before using Xcode.

Metadata uses pinned LibYAML 0.2.5. Before composition, the wrapper enforces a
64 KiB UTF-8 input limit, 4096 events and 64 nested collections. YAML aliases
and nonscalar mapping keys are unsupported and rejected; the Markdown body is
still rendered and the source is preserved. Parser state is released on failure.

The application, settings, support files, CLI and URL scheme are separate from
the official application. Legacy preference migration and the Sparkle updater
dependency are removed, and no update feed is configured. Install reviewed
updates manually; do not install an upstream
release over this fork and assume these controls remain.

This is targeted hardening, not a security certification. The editor still uses
the legacy WebView and does not adopt App Sandbox. Local files/styles/scripts
remain subject to normal macOS permissions; untrusted local assets need care.
Reading a user-selected network-mounted document may cause filesystem traffic.
Exported HTML may contain external references if opened in another application.
Unsigned/ad-hoc candidates are not Developer ID notarized releases. Keep those
limitations visible when choosing an exact build for installation.
