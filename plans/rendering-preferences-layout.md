# Rendering preferences layout

Impact: Narrow. Base: `5adcfe0f2ec3a4cc5c0dc9beb76969aa2b397532`.

The CSS selector and syntax-highlighting checkbox must occupy separate rows,
including when native control metrics change. The Rendering pane keeps at
least 16 points between both CSS controls and the checkbox, uses a 560-point
design width, and leaves more space between option rows. Existing fitting-size
logic determines the required height. Actions, bindings and security controls
are unchanged.

`System Charcoal` is a bundled preview style that follows system appearance.
Its dark palette uses a lighter charcoal preview surface, light text and blue
links. The light palette also applies when printing. A personal stylesheet of
the same name retains the application's existing override precedence.

Verification covers measured control separation and containment with normal
metrics, an enlarged CSS popup, and enlarged Reveal/Reload controls. The existing
locale-aware layout tests and complete native suite run on macOS 14 and 26;
the release build compiles the interface resource and bundles the stylesheet.
Candidate verification compares the tracked, packaged and active personal
stylesheet hashes and checks the actual Rendering pane on the target Mac.

The installed app remains at its separately approved source revision until a
reviewed replacement is explicitly approved. Candidate provenance and activation
receipts identify the source commit and package hash. Reverting this change and
retaining the prior app restores the previous layout; selecting another CSS
style changes preview appearance independently.
