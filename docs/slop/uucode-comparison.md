# uucode comparison, 2026-11-02

Compared `baskingspot/text` at `a5dd59a` with
[`jacobsandlund/uucode`](https://github.com/jacobsandlund/uucode) at `1fb7343`
(2026-10-03, the Zig 0.17 migration). Both target Unicode 18.0.0 and Zig 0.17.
uucode is MIT. Its wcwidth data is Bjoern Hoehrmann's MIT table; the Unicode UCD
data is under the Unicode License V3 in both projects.

## What each library is

uucode is a configurable UCD property table with a grapheme iterator, UTF-8
iterator, and `wcwidth`. It carries decomposition and bidi data but does not
implement normalisation, word or sentence segmentation, or the bidi algorithm.

text is a smaller property surface with the algorithms on top: normalisation
(UAX #15), grapheme/word/sentence segmentation (UAX #29), and bidi (UAX #9).
Its property access is typed functions, not a `get(.field, cp)` API.

## Functionality

| Area | text | uucode |
| --- | --- | --- |
| General category, script, block | yes | yes |
| Character name and Unicode 1.0 name | no | yes |
| Numeric type and values | no | yes |
| Simple and full case mappings | yes | yes |
| Case folding | simple + full | simple + full + Turkic/common/simple-only variants |
| Special casing | root Final_Sigma applied | data exposed, including conditions |
| Normalisation | NFC/NFD/NFKC/NFKD + isNormalized | data only |
| Grapheme segmentation | `[]u21` predicate + iterator | UTF-8 iterator, streaming `isBreak`, `nextGrapheme` |
| Word and sentence segmentation | yes | no |
| Bidi | full UAX #9 resolver | data only (class, brackets, mirroring) |
| Bidi mirroring | `isMirrored`, `mirror` | `is_bidi_mirrored`, `bidi_mirroring` |
| East Asian width | no | yes |
| Emoji properties | Extended_Pictographic only | emoji, presentation, modifier, component, variation base |
| Joining type/group | no | yes |
| Indic positional/syllabic categories | no | yes |
| Derived binary properties (`is_alphabetic`, `is_math`, `is_default_ignorable`, `changes_when_*`, grapheme extend/base/link) | only Cased, Case_Ignorable, InCB | yes |
| `wcwidth` | no | standalone and zero-in-grapheme |
| Configurable fields/tables at build time | no | yes, `fields_0` through `fields_9` |
| Data release | 18.0.0 | 18.0.0 |

The support gap is real but narrow in a different direction: text has the
algorithms uucode does not, and uucode has the property and terminal-width
surface text does not.

## Benchmarks

Both suites use testingx (`b.loop()`, ReleaseFast) and the same code-point
sample and UTF-8 corpus. The sample is 65,536 code points stepped through
`0..0x10FFFF`; the segmentation corpus repeats a mixed Latin/Greek/Cyrillic/
Arabic/Hebrew/Devanagari/Hangul/CJK/emoji block to 256 KiB.

Commands:

```sh
just bench -- --benchtime=200ms --count=5
```

The uucode side uses the same testingx suite with a local path dependency on
uucode. Machine: aarch64-linux, Neoverse v3, Zig 0.17.0.

| Benchmark | text, before | text, now | uucode | text now / uucode |
| --- | ---: | ---: | ---: | ---: |
| Category lookup | 368 MB/s | 4.94 GB/s | 6.08 GB/s | 0.81x |
| Script lookup | 470 MB/s | 5.45 GB/s | 6.20 GB/s | 0.88x |
| Block lookup | 584 MB/s | 4.83 GB/s | 6.09 GB/s | 0.79x |
| Simple uppercase lookup | 452 MB/s | 5.39 GB/s | 4.82 GB/s | 1.12x |
| Category + script + block + uppercase | 115 MB/s | 1.80 GB/s | 2.89 GB/s | 0.62x |
| Grapheme segmentation | 64.6 MB/s | 371 MB/s | 544 MB/s | 0.68x |

"Before" is the range-table implementation from the previous commit. The
property change is a two-stage table: a 4,352-entry block map and deduplicated
256-entry blocks. It is 8-13x faster than binary search. The combined row is
not apples to apples: uucode's `getAll` walks one table and reads several
fields, while text calls four separate lookup functions.

text-only, for context (no uucode equivalent):

| Benchmark | Result |
| --- | ---: |
| Word segmentation | 291 MB/s |
| Sentence segmentation | 219 MB/s |
| NFC / NFD / NFKC | 112 / 191 / 112 MB/s |
| Upper / lower / fold a string | 592 / 625 / 331 MB/s |
| Bidi resolve | 140-158 MB/s |

## Where the remaining gap is

- Raw property lookups are 12-23% behind uucode. uucode's three-stage tables
  with packed fields are more compact; text's two-stage tables are close but
  lose on block and category cache behaviour.
- The combined row is a support gap, not just a speed gap: text has no grouped
  lookup. A `getAll` equivalent would make lexer-style consumers faster.
- Grapheme segmentation is 1.5x behind because uucode's state machine uses a
  derived grapheme category and compact state; text's state machine decodes
  the combined property bits and branches on each rule. The current text
  iterator already improved 5.7x by keeping state between code points.
- The property surface is the larger gap: names, numeric values, East Asian
  width, emoji, joining, Indic categories, the remaining derived binary
  properties, and wcwidth are absent.

## Suggested order

1. Add a grouped property lookup and a combined stage table for category,
   script, block, and case, then re-benchmark the combined row.
2. Add the missing UCD fields behind one typed API, starting with names,
   numeric values, East Asian width, emoji, joining type/group, and Indic
   categories. Keep `wcwidth` separate because it brings another license and
   terminal-specific rules.
3. Shrink the grapheme state machine to a derived category, or accept the
   1.5x gap because text also carries word and sentence segmentation.
4. Consider build-time field selection only if binary size becomes a problem;
   text's tables are generated source and the linker drops unused arrays.
