# Generated data

`src/tables.zig` is generated from the Unicode Character Database by
`tools/gen.zig`. It ships the derived data, not the UCD text. This file names
the source files, their license, and the release they came from.

## Unicode Character Database

- Release: 18.0.0, published 2026-08-07
- Upstream: <https://www.unicode.org/Public/18.0.0/ucd/>
- Files: `UnicodeData.txt`, `DerivedCoreProperties.txt`, `PropList.txt`
- License: Unicode License V3, reproduced in [`LICENSE-UNICODE`](LICENSE-UNICODE)

The generated table holds:

- The general category of each assigned code point, from `UnicodeData.txt`.
- The simple uppercase, lowercase, and titlecase mappings, from the same file.
- `ID_Start`, `ID_Continue`, `XID_Start`, and `XID_Continue`, from
  `DerivedCoreProperties.txt`.
- `White_Space`, from `PropList.txt`.

The `sources` constant in `src/tables.zig` carries the SHA-256 of each input
file, so the regenerated table names exactly what produced it.

`UnicodeData.txt` and the two derived files are not vendored. `just regen`
fetches the three files from the URLs pinned in the recipe, verifies each
SHA-256, and runs the generator. A consumer of the package fetches neither the
data nor the generator.
