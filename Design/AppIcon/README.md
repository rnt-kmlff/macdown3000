# Graphite Md app icon

The app icon uses a dark glass tile and raised silver Md lettering inspired by
early iPhone icons. The capital M is dominant, with a smaller lowercase d beside
it. The arrow is removed. Its exterior transparency and rounded square footprint
are retained across the existing macOS asset catalog slots.
Application identity, file-type icons and security settings are unchanged.

`master.png` is the untouched generated artwork. `prompt.txt` records the exact
prompt used with the built-in image generation tool. `manifest.json` identifies
the master, edit reference revision and hashes, resize utility and each
catalog derivative. Generation is not deterministic; derivatives are reproduced
from the saved master, rather than by generating the prompt again.

To reproduce the PNG slots from the repository root, use the dimensions and
filenames in `manifest.json` with:

```sh
sips -z PIXELS PIXELS Design/AppIcon/master.png \
  --out MacDown/Images.xcassets/AppIcon.appiconset/FILENAME
```

Duplicate pixel dimensions use identical PNG bytes. Keep the existing
`Contents.json` catalog structure. Review the silhouette against light and dark
backgrounds and check both letters at 16/32 pixels before accepting new artwork.
