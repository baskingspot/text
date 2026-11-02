# text: Unicode character data in Zig, generated from the Unicode Character Database. `just --list` shows the recipes.
# AGENTS.md holds the working conventions.

[private]
default:
    @just --list

[doc("Unit tests: the module and the generator")]
[group("test")]
test:
    zig build test --summary all

[doc("Fetch the UCD conformance files and run the tests against them")]
[group("test")]
conformance:
    zig build test -Dconformance --summary all

[doc("Run the benchmarks (ReleaseFast). Extra args go to the benchmark binary")]
[group("bench")]
bench *ARGS:
    zig build bench -- {{ ARGS }}

[doc("Fetch the pinned UCD and regenerate src/tables.zig. Commit the result")]
[group("data")]
regen:
    zig build regen -Dregen

[doc("Lint Zig, Nix, Markdown, the workflows, and this justfile: ziglint, zig fmt, nix fmt, oxfmt, actionlint, zizmor, and just --fmt")]
[group("lint")]
lint:
    ziglint
    zig fmt --check src tools bench build.zig build.zig.zon
    nix fmt -- --ci
    oxfmt --check README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md .github .oxfmtrc.jsonc
    actionlint
    zizmor .
    just --fmt --check

[doc("Format everything lint checks")]
[group("lint")]
fmt:
    zig fmt src tools bench build.zig build.zig.zon
    nix fmt
    oxfmt README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md .github .oxfmtrc.jsonc
    just --fmt

[doc("Everything CI runs: the tests, lint, and conformance")]
[group("ci")]
ci: test lint conformance
