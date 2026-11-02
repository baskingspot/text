# text: Unicode character data in Zig, generated from the Unicode Character Database. `just --list` shows the recipes.
# AGENTS.md holds the working conventions.

[private]
default:
    @just --list

[doc("Unit tests: the module and the generator")]
[group("test")]
test:
    zig build test --summary all

[doc("Regenerate src/tables.zig from the UCD release pinned in build.zig.zon. The first run downloads the archive; the result is committed")]
[group("data")]
regen:
    zig build regen

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
