# text: Unicode character data in Zig, generated from the Unicode Character Database. `just --list` shows the recipes.
# AGENTS.md holds the working conventions.

[private]
default:
    @just --list

[doc("Unit tests: the module and the generator")]
[group("test")]
test:
    zig build test --summary all

[doc("Regenerate src/tables.zig from the Unicode 18.0.0 files. Downloads and verifies the three UCD files, then runs the generator; commit the result")]
[group("data")]
regen:
    mkdir -p .zig-cache/ucd
    curl -fsSL -o .zig-cache/ucd/UnicodeData.txt https://www.unicode.org/Public/18.0.0/ucd/UnicodeData.txt
    curl -fsSL -o .zig-cache/ucd/DerivedCoreProperties.txt https://www.unicode.org/Public/18.0.0/ucd/DerivedCoreProperties.txt
    curl -fsSL -o .zig-cache/ucd/PropList.txt https://www.unicode.org/Public/18.0.0/ucd/PropList.txt
    echo "0736451de439ae7baf1425136617da495e09ee5afbe6e394374db7009ea08950  .zig-cache/ucd/UnicodeData.txt" | sha256sum -c -
    echo "09c928886a178fcafd93c29e4bd59073a058e5a100b716d425cb563ab50f68c9  .zig-cache/ucd/DerivedCoreProperties.txt" | sha256sum -c -
    echo "f438f532e8737bb8a2702126cdf9c4af5e357c58c7acf9d9eb2fc7c1a1d955d6  .zig-cache/ucd/PropList.txt" | sha256sum -c -
    zig run tools/gen.zig -- --out src/tables.zig .zig-cache/ucd/UnicodeData.txt .zig-cache/ucd/DerivedCoreProperties.txt .zig-cache/ucd/PropList.txt

[doc("Lint Zig, Nix, Markdown, the workflows, and this justfile: ziglint, zig fmt, nix fmt, oxfmt, actionlint, zizmor, and just --fmt")]
[group("lint")]
lint:
    ziglint
    zig fmt --check src tools build.zig build.zig.zon
    nix fmt -- --ci
    oxfmt --check README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md .github .oxfmtrc.jsonc
    actionlint
    zizmor .
    just --fmt --check

[doc("Format everything lint checks")]
[group("lint")]
fmt:
    zig fmt src tools build.zig build.zig.zon
    nix fmt
    oxfmt README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md .github .oxfmtrc.jsonc
    just --fmt

[doc("Everything CI runs: the tests and lint")]
[group("ci")]
ci: test lint
