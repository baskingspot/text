# Generated data

`src/tables.zig` is generated from the Unicode Character Database by
`tools/gen.zig`. It ships the derived data, not the UCD text. This file names
the source files, their license, and the release they came from.

## Unicode Character Database

- Release: 18.0.0, published 2026-08-07
- Upstream: <https://www.unicode.org/Public/18.0.0/ucd/>
- License: Unicode License V3, reproduced in [`LICENSE-UNICODE`](LICENSE-UNICODE)

Files read by the generator:

- `UnicodeData.txt`
- `DerivedCoreProperties.txt`
- `PropList.txt`
- `Scripts.txt`
- `Blocks.txt`
- `SpecialCasing.txt`
- `CaseFolding.txt`
- `DerivedNormalizationProps.txt`
- `BidiBrackets.txt`
- `BidiMirroring.txt`
- `extracted/DerivedBidiClass.txt`
- `extracted/DerivedBinaryProperties.txt`
- `auxiliary/GraphemeBreakProperty.txt`
- `auxiliary/WordBreakProperty.txt`
- `auxiliary/SentenceBreakProperty.txt`
- `emoji/emoji-data.txt`

The generated table holds:

- The general category, canonical combining class, decomposition, and simple
  case mappings of each assigned code point, from `UnicodeData.txt`.
- `ID_Start`, `ID_Continue`, `XID_Start`, `XID_Continue`, `Cased`,
  `Case_Ignorable`, and `Indic_Conjunct_Break`, from
  `DerivedCoreProperties.txt`.
- `White_Space` and `Bidi_Mirrored`, from `PropList.txt` and
  `extracted/DerivedBinaryProperties.txt`.
- `Script`, from `Scripts.txt`, and `Block`, from `Blocks.txt`.
- The full case mappings and the Final_Sigma rule, from `SpecialCasing.txt`,
  and the case folds, from `CaseFolding.txt`.
- Full composition exclusions from `DerivedNormalizationProps.txt`, and the
  decomposition sequences from `UnicodeData.txt`.
- `Grapheme_Cluster_Break`, `Word_Break`, and `Sentence_Break` from the
  `auxiliary` files, `Extended_Pictographic` from `emoji/emoji-data.txt`, and
  the paired brackets and mirrored glyphs from `BidiBrackets.txt` and
  `BidiMirroring.txt`.
- `Bidi_Class` from `extracted/DerivedBidiClass.txt`, including the `@missing`
  defaults for unassigned code points.

The `sources` constant in `src/tables.zig` carries the SHA-256 of each input
file, so the regenerated table names exactly what produced it.

The UCD text files are not vendored. `just regen` fetches the release pinned
by the `ucd` dependency in `build.zig.zon`, verifies the archive hash, and runs
the generator. A consumer of the package fetches neither the data nor the
generator.
