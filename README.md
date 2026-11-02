# text

Unicode character data and algorithms in Zig, generated from the Unicode
Character Database.

`std.unicode` has the codecs and no character tables. This package answers what
a code point is, how text is normalized, where graphemes, words, and sentences
end, and how a bidirectional paragraph resolves. Every answer comes from the
Unicode Character Database at the release named by `unicode.version`, generated
by `tools/gen.zig` and checked in.

```zig
const text = @import("text");

if (!text.unicode.isXidStart(cp)) return error.NotAnIdentifier;
const upper = text.unicode.toUpper(cp);
const composed = try text.normalize.normalize(allocator, .nfc, code_points);
```

This project is incubating. Its API will change, and it is not ready to depend
on.

## What is in it

- `unicode.category` returns the general category as a `Category`, from `Lu` to `Cn`. The group predicates `isLetter`, `isMark`, `isNumber`, `isPunctuation`, `isSymbol`, `isSeparator`, and `isOther` are that answer checked against a set.
- `unicode.isIdStart` and `unicode.isIdContinue` are UAX #31 identifiers. The `xid` forms are the NFKC-closed versions. `_` and `$` are not ID_Start; a language that allows them adds that rule.
- `unicode.isWhiteSpace` is the White_Space property. `unicode.script` and `unicode.block` answer the Script and Block properties.
- `unicode.toUpper`, `toLower`, and `toTitle` are the simple one-to-one case mappings. The `Full` forms expand to up to three code points, `unicode.upper` and `unicode.lower` map a string, and `unicode.fold` is full case folding. `lower` applies the Final_Sigma rule.
- `normalize.normalize` implements NFC, NFD, NFKC, and NFKD from UAX #15, and `normalize.isNormalized` checks a string.
- `segment.graphemes`, `segment.words`, and `segment.sentences` implement the UAX #29 boundaries. The `is…Boundary` predicates answer one position.
- `bidi.resolve` implements UAX #9 for one paragraph: explicit levels and isolates, weak and neutral types, bracket pairs, implicit levels, and reordering. `bidi.mirror` exposes the glyph mapping that rule L4 needs.

Not implemented:

- Locale-specific case rules: the Turkish, Azeri, and Lithuanian conditions in `SpecialCasing.txt` are not applied. Casing is the root locale, so `lower('I')` is `i`.
- `unicode.title` maps each code point. Word-aware title casing belongs to the caller.
- `Script_Extensions` (`scx`). `unicode.script` is the single Script property.
- Rules L3 and L4 of the bidi algorithm are rendering. `bidi.mirror` carries the data, but this package does not draw glyphs.
- Paragraph splitting for bidi: `bidi.resolve` takes one paragraph. Split at `B` first.

## Install

```sh
zig fetch --save git+https://github.com/baskingspot/text
```

Add the module in `build.zig`:

```zig
const text = b.dependency("text", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("text", text.module("text"));
```

`text` builds with Zig 0.17 only.

## Work on it

```sh
just ci
```

`nix develop` provides the toolchain. `just` lists the recipes, and `just ci` runs what CI runs: the tests, lint, and the conformance suites. `just regen` fetches the UCD release pinned in `build.zig.zon` and rebuilds `src/tables.zig`; commit the result. `just conformance` fetches the same release and runs the UCD test files against it. `just bench` runs the local benchmarks with testingx; the numbers are not claims.

The generator is `tools/gen.zig`. It reads the UCD directory named by the `ucd` dependency and writes the ranges, properties, and mappings in one file. `just test` runs the generator's own tests with the module's.

## License

MIT. See [`LICENSE`](LICENSE). The Unicode data is under the Unicode License V3; [`LICENSE-UNICODE`](LICENSE-UNICODE) reproduces it and [`THIRD_PARTY.md`](THIRD_PARTY.md) names the files.

## How it's made

Built with LLM assistance. [How, in detail](https://github.com/baskingspot/.github/blob/main/docs/AI.md).

<a href="https://github.com/baskingspot"><img src="https://raw.githubusercontent.com/baskingspot/.github/main/brand/assets/badge.svg" alt="baskingspot" height="24"></a>
