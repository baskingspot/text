# Changelog

All notable changes to text are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `unicode` holds the general categories, the UAX #31 `ID_Start` and `ID_Continue` predicates with their NFKC-closed `XID` forms, the `White_Space` property, and the simple `toUpper`, `toLower`, and `toTitle` mappings.
- `unicode.script` and `unicode.block` answer the Script and Block properties.
- `unicode.toUpperFull`, `toLowerFull`, and `toTitleFull` expand to up to three code points. `unicode.upper`, `lower`, and `title` map a string; `lower` applies the Final_Sigma rule. `unicode.fold` and `foldSimple` are case folding.
- `normalize.normalize` and `normalize.isNormalized` implement NFC, NFD, NFKC, and NFKD from UAX #15.
- `segment.graphemes`, `words`, and `sentences` implement the UAX #29 boundaries, with `isGraphemeBoundary`, `isWordBoundary`, and `isSentenceBoundary` for one position.
- `bidi.resolve` implements UAX #9 for one paragraph, and `bidi.mirror` exposes the data rule L4 needs.
- `unicode.version` names the Unicode release the tables come from, 18.0.0.
