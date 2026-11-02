//! Generate `tables.zig` from the Unicode Character Database.
//!
//! The generator reads a directory of UCD files and writes one Zig source
//! file. `just regen` fetches the pinned release, then runs it.
//!
//! Usage: gen --out PATH UCD_DIR

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const usage =
    \\Usage: gen --out PATH UCD_DIR
    \\
;

/// The general categories, in the order the generated enum declares them.
const category_names = [_][]const u8{
    "Lu", "Ll", "Lt", "Lm", "Lo",
    "Mn", "Mc", "Me", "Nd", "Nl",
    "No", "Pc", "Pd", "Ps", "Pe",
    "Pi", "Pf", "Po", "Sm", "Sc",
    "Sk", "So", "Zs", "Zl", "Zp",
    "Cc", "Cf", "Cs", "Co", "Cn",
};

const Range = struct {
    start: u21,
    end: u21,
};

const CategoryRange = struct {
    start: u21,
    end: u21,
    category: usize,
};

const Mapping = struct {
    from: u21,
    to: u21,
};

const MultiMapping = struct {
    from: u21,
    to: [3]u21,
    len: u8,
};

const TaggedRange = struct {
    start: u21,
    end: u21,
    value: usize,
};

const CccRange = struct {
    start: u21,
    end: u21,
    ccc: u8,
};

const Decomposition = struct {
    from: u21,
    compat: bool,
    offset: usize,
    len: usize,
};

const Composition = struct {
    first: u21,
    second: u21,
    composed: u21,
};

const Bracket = struct {
    cp: u21,
    pair: u21,
    kind: usize,
};

const Mirror = struct {
    from: u21,
    to: u21,
};

const Source = struct {
    name: []const u8,
    sha256: [64]u8,
};

const NamedRange = struct {
    start: u21,
    end: u21,
    name: []const u8,
};

const Output = struct {
    version: []const u8,
    sources: []const Source,
    categories: []const CategoryRange,
    white_space: []const Range,
    bidi_mirrored: []const Range,
    id_start: []const Range,
    id_continue: []const Range,
    xid_start: []const Range,
    xid_continue: []const Range,
    cased: []const Range,
    case_ignorable: []const Range,
    upper: []const Mapping,
    lower: []const Mapping,
    title: []const Mapping,
    full_upper: []const MultiMapping,
    full_lower: []const MultiMapping,
    full_title: []const MultiMapping,
    final_sigma: []const MultiMapping,
    fold_full: []const MultiMapping,
    fold_simple: []const Mapping,
    scripts: []const []const u8,
    script_ranges: []const TaggedRange,
    blocks: []const []const u8,
    block_ranges: []const TaggedRange,
    ccc: []const CccRange,
    decompositions: []const Decomposition,
    decomposition_values: []const u21,
    compositions: []const Composition,
    grapheme_breaks: []const []const u8,
    grapheme_ranges: []const TaggedRange,
    word_breaks: []const []const u8,
    word_ranges: []const TaggedRange,
    sentence_breaks: []const []const u8,
    sentence_ranges: []const TaggedRange,
    extended_pictographic: []const Range,
    incb: []const []const u8,
    incb_ranges: []const TaggedRange,
    bidi_classes: []const []const u8,
    bidi_ranges: []const TaggedRange,
    bidi_defaults: []const TaggedRange,
    brackets: []const Bracket,
    mirrors: []const Mirror,
};

const Args = struct {
    out: []const u8,
    dir: []const u8,
};

pub fn main(init: std.process.Init) u8 {
    const arena = init.arena.allocator();
    const io = init.io;

    const args = parseArgs(init.minimal.args) orelse {
        std.debug.print("{s}", .{usage});
        return 2;
    };

    run(arena, io, args) catch |err| {
        std.debug.print("gen: {s}: {s}\n", .{ args.out, @errorName(err) });
        return 1;
    };
    return 0;
}

fn parseArgs(argv: std.process.Args) ?Args {
    var it = std.process.Args.iterate(argv);
    _ = it.skip();
    var out: ?[]const u8 = null;
    var dir: ?[]const u8 = null;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out")) {
            out = it.next() orelse return null;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return null;
        } else if (dir == null) {
            dir = arg;
        } else {
            return null;
        }
    }
    if (out == null or dir == null) return null;
    return .{ .out = out.?, .dir = dir.? };
}

fn run(arena: Allocator, io: Io, args: Args) !void {
    const data = try Inputs.load(arena, io, args.dir);

    var mappings: Mappings = undefined;
    const categories = try parseUnicodeData(arena, data.unicode_data, &mappings);
    const white_space = try parseProperty("White_Space", arena, data.prop_list);
    const bidi_mirrored = try parseProperty(
        "Bidi_Mirrored",
        arena,
        data.derived_binary,
    );
    const id_start = try parseProperty("ID_Start", arena, data.derived_core);
    const id_continue = try parseProperty("ID_Continue", arena, data.derived_core);
    const xid_start = try parseProperty("XID_Start", arena, data.derived_core);
    const xid_continue = try parseProperty("XID_Continue", arena, data.derived_core);
    const cased = try parseProperty("Cased", arena, data.derived_core);
    const case_ignorable = try parseProperty("Case_Ignorable", arena, data.derived_core);
    const extended_pictographic = try parseProperty(
        "Extended_Pictographic",
        arena,
        data.emoji_data,
    );

    const scripts = try parseNamedRanges(arena, data.scripts, 1);
    var blocks = try parseNamedRanges(arena, data.blocks, 1);
    try blocks.convertToIdentifiers(arena);

    const special = try parseSpecialCasing(arena, data.special_casing);
    const folds = try parseCaseFolding(arena, data.case_folding);
    const exclusions = try parseProperty(
        "Full_Composition_Exclusion",
        arena,
        data.derived_normalization,
    );
    const compositions = try buildCompositions(
        arena,
        categories.decompositions,
        categories.decomposition_values,
        exclusions,
    );

    const grapheme = try parseNamedRanges(arena, data.grapheme_break, 1);
    const word = try parseNamedRanges(arena, data.word_break, 1);
    const sentence = try parseNamedRanges(arena, data.sentence_break, 1);
    const incb = try parseInCb(arena, data.derived_core);
    const bidi = try parseBidiClasses(arena, data.derived_bidi);

    var unicode_sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data.unicode_data, &unicode_sha, .{});

    const output: Output = .{
        .version = try parseVersion(data.derived_core),
        .sources = try data.sources(arena),
        .categories = categories.ranges,
        .white_space = white_space,
        .bidi_mirrored = bidi_mirrored,
        .id_start = id_start,
        .id_continue = id_continue,
        .xid_start = xid_start,
        .xid_continue = xid_continue,
        .cased = cased,
        .case_ignorable = case_ignorable,
        .upper = mappings.upper,
        .lower = mappings.lower,
        .title = mappings.title,
        .full_upper = special.upper,
        .full_lower = special.lower,
        .full_title = special.title,
        .final_sigma = special.final_sigma,
        .fold_full = folds.full,
        .fold_simple = folds.simple,
        .scripts = scripts.names,
        .script_ranges = scripts.ranges,
        .blocks = blocks.names,
        .block_ranges = blocks.ranges,
        .ccc = categories.ccc,
        .decompositions = categories.decompositions,
        .decomposition_values = categories.decomposition_values,
        .compositions = compositions,
        .grapheme_breaks = grapheme.names,
        .grapheme_ranges = grapheme.ranges,
        .word_breaks = word.names,
        .word_ranges = word.ranges,
        .sentence_breaks = sentence.names,
        .sentence_ranges = sentence.ranges,
        .extended_pictographic = extended_pictographic,
        .incb = incb.names,
        .incb_ranges = incb.ranges,
        .bidi_classes = bidi.names,
        .bidi_ranges = bidi.ranges,
        .bidi_defaults = bidi.defaults,
        .brackets = try parseBrackets(arena, data.bidi_brackets),
        .mirrors = try parseMirrors(arena, data.bidi_mirroring),
    };

    var text: std.ArrayList(u8) = .empty;
    try writeOutput(arena, &text, &output);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = args.out, .data = text.items });
}

const Inputs = struct {
    unicode_data: []const u8,
    derived_core: []const u8,
    prop_list: []const u8,
    scripts: []const u8,
    blocks: []const u8,
    special_casing: []const u8,
    case_folding: []const u8,
    derived_normalization: []const u8,
    bidi_brackets: []const u8,
    bidi_mirroring: []const u8,
    derived_bidi: []const u8,
    derived_binary: []const u8,
    grapheme_break: []const u8,
    word_break: []const u8,
    sentence_break: []const u8,
    emoji_data: []const u8,

    fn load(arena: Allocator, io: Io, dir: []const u8) !Inputs {
        return .{
            .unicode_data = try read(arena, io, dir, "UnicodeData.txt"),
            .derived_core = try read(arena, io, dir, "DerivedCoreProperties.txt"),
            .prop_list = try read(arena, io, dir, "PropList.txt"),
            .scripts = try read(arena, io, dir, "Scripts.txt"),
            .blocks = try read(arena, io, dir, "Blocks.txt"),
            .special_casing = try read(arena, io, dir, "SpecialCasing.txt"),
            .case_folding = try read(arena, io, dir, "CaseFolding.txt"),
            .derived_normalization = try read(arena, io, dir, "DerivedNormalizationProps.txt"),
            .bidi_brackets = try read(arena, io, dir, "BidiBrackets.txt"),
            .bidi_mirroring = try read(arena, io, dir, "BidiMirroring.txt"),
            .derived_bidi = try read(arena, io, dir, "extracted/DerivedBidiClass.txt"),
            .derived_binary = try read(arena, io, dir, "extracted/DerivedBinaryProperties.txt"),
            .grapheme_break = try read(arena, io, dir, "auxiliary/GraphemeBreakProperty.txt"),
            .word_break = try read(arena, io, dir, "auxiliary/WordBreakProperty.txt"),
            .sentence_break = try read(arena, io, dir, "auxiliary/SentenceBreakProperty.txt"),
            .emoji_data = try read(arena, io, dir, "emoji/emoji-data.txt"),
        };
    }

    fn read(arena: Allocator, io: Io, dir: []const u8, name: []const u8) ![]const u8 {
        const path = try Io.Dir.path.join(arena, &.{ dir, name });
        return Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(32 << 20));
    }

    fn sources(self: *const Inputs, arena: Allocator) ![]const Source {
        const entries = [_]struct { name: []const u8, data: []const u8 }{
            .{ .name = "UnicodeData.txt", .data = self.unicode_data },
            .{ .name = "DerivedCoreProperties.txt", .data = self.derived_core },
            .{ .name = "PropList.txt", .data = self.prop_list },
            .{ .name = "Scripts.txt", .data = self.scripts },
            .{ .name = "Blocks.txt", .data = self.blocks },
            .{ .name = "SpecialCasing.txt", .data = self.special_casing },
            .{ .name = "CaseFolding.txt", .data = self.case_folding },
            .{ .name = "DerivedNormalizationProps.txt", .data = self.derived_normalization },
            .{ .name = "BidiBrackets.txt", .data = self.bidi_brackets },
            .{ .name = "BidiMirroring.txt", .data = self.bidi_mirroring },
            .{ .name = "extracted/DerivedBidiClass.txt", .data = self.derived_bidi },
            .{ .name = "extracted/DerivedBinaryProperties.txt", .data = self.derived_binary },
            .{ .name = "auxiliary/GraphemeBreakProperty.txt", .data = self.grapheme_break },
            .{ .name = "auxiliary/WordBreakProperty.txt", .data = self.word_break },
            .{ .name = "auxiliary/SentenceBreakProperty.txt", .data = self.sentence_break },
            .{ .name = "emoji/emoji-data.txt", .data = self.emoji_data },
        };
        const list = try arena.alloc(Source, entries.len);
        for (entries, list) |entry, *source| {
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(entry.data, &digest, .{});
            source.* = .{
                .name = entry.name,
                .sha256 = std.fmt.bytesToHex(digest, .lower),
            };
        }
        return list;
    }
};

/// The first line names the release: `# DerivedCoreProperties-18.0.0.txt`.
fn parseVersion(data: []const u8) ![]const u8 {
    const line_end = std.mem.findScalar(u8, data, '\n') orelse data.len;
    const line = std.mem.trim(u8, data[0..line_end], " \r");
    const prefix = "# DerivedCoreProperties-";
    if (!std.mem.startsWith(u8, line, prefix)) return error.MissingVersion;
    const rest = line[prefix.len..];
    const suffix = std.mem.find(u8, rest, ".txt") orelse return error.MissingVersion;
    return rest[0..suffix];
}

const Mappings = struct {
    upper: []const Mapping,
    lower: []const Mapping,
    title: []const Mapping,
};

const Categories = struct {
    ranges: []const CategoryRange,
    ccc: []const CccRange,
    decompositions: []const Decomposition,
    decomposition_values: []const u21,
};

fn parseUnicodeData(arena: Allocator, data: []const u8, mappings: *Mappings) !Categories {
    var ranges: std.ArrayList(CategoryRange) = .empty;
    var upper: std.ArrayList(Mapping) = .empty;
    var lower: std.ArrayList(Mapping) = .empty;
    var title: std.ArrayList(Mapping) = .empty;
    var ccc: std.ArrayList(CccRange) = .empty;
    var decompositions: std.ArrayList(Decomposition) = .empty;
    var decomposition_values: std.ArrayList(u21) = .empty;

    var lines = std.mem.splitScalar(u8, data, '\n');
    var first: ?struct { cp: u21, category: usize, ccc: u8 } = null;
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;

        var fields: [15][]const u8 = @splat("");
        var parts = std.mem.splitScalar(u8, line, ';');
        var index: usize = 0;
        while (parts.next()) |part| {
            if (index == fields.len) break;
            fields[index] = part;
            index += 1;
        }
        if (index < 15) return error.BadUnicodeData;

        const cp = try std.fmt.parseInt(u21, fields[0], 16);
        const name = fields[1];
        const category = categoryIndex(fields[2]) orelse return error.UnknownCategory;
        const combining = if (fields[3].len == 0)
            0
        else
            try std.fmt.parseInt(u8, fields[3], 10);

        if (std.mem.endsWith(u8, name, ", First>")) {
            first = .{ .cp = cp, .category = category, .ccc = combining };
            continue;
        }
        if (std.mem.endsWith(u8, name, ", Last>")) {
            const open = first orelse return error.BadUnicodeData;
            if (open.category != category or open.ccc != combining) {
                return error.BadUnicodeData;
            }
            try addCategoryRange(arena, &ranges, open.cp, cp, category);
            try addCccRange(arena, &ccc, open.cp, cp, combining);
            first = null;
            continue;
        }
        try addCategoryRange(arena, &ranges, cp, cp, category);
        try addCccRange(arena, &ccc, cp, cp, combining);

        try addMapping(arena, &upper, cp, fields[12]);
        try addMapping(arena, &lower, cp, fields[13]);
        try addMapping(arena, &title, cp, fields[14]);
        try addDecomposition(arena, &decompositions, &decomposition_values, cp, fields[5]);
    }
    if (first != null) return error.BadUnicodeData;

    mappings.* = .{
        .upper = try upper.toOwnedSlice(arena),
        .lower = try lower.toOwnedSlice(arena),
        .title = try title.toOwnedSlice(arena),
    };
    return .{
        .ranges = try ranges.toOwnedSlice(arena),
        .ccc = try ccc.toOwnedSlice(arena),
        .decompositions = try decompositions.toOwnedSlice(arena),
        .decomposition_values = try decomposition_values.toOwnedSlice(arena),
    };
}

fn addMapping(
    arena: Allocator,
    list: *std.ArrayList(Mapping),
    from: u21,
    field: []const u8,
) !void {
    if (field.len == 0) return;
    const to = try std.fmt.parseInt(u21, field, 16);
    try list.append(arena, .{ .from = from, .to = to });
}

fn addCategoryRange(
    arena: Allocator,
    list: *std.ArrayList(CategoryRange),
    start: u21,
    end: u21,
    category: usize,
) !void {
    if (list.items.len > 0) {
        const last = &list.items[list.items.len - 1];
        if (last.category == category and @as(u32, last.end) + 1 == start) {
            last.end = end;
            return;
        }
    }
    try list.append(arena, .{ .start = start, .end = end, .category = category });
}

fn addCccRange(
    arena: Allocator,
    list: *std.ArrayList(CccRange),
    start: u21,
    end: u21,
    ccc: u8,
) !void {
    if (ccc == 0) return;
    if (list.items.len > 0) {
        const last = &list.items[list.items.len - 1];
        if (last.ccc == ccc and @as(u32, last.end) + 1 == start) {
            last.end = end;
            return;
        }
    }
    try list.append(arena, .{ .start = start, .end = end, .ccc = ccc });
}

fn addDecomposition(
    arena: Allocator,
    list: *std.ArrayList(Decomposition),
    values: *std.ArrayList(u21),
    cp: u21,
    field: []const u8,
) !void {
    if (field.len == 0) return;
    var rest = field;
    var compat = false;
    if (rest[0] == '<') {
        const close = std.mem.findScalar(u8, rest, '>') orelse return error.BadDecomposition;
        rest = std.mem.trim(u8, rest[close + 1 ..], " ");
        compat = true;
    }
    const offset = values.items.len;
    var it = std.mem.tokenizeScalar(u8, rest, ' ');
    while (it.next()) |part| {
        try values.append(arena, try std.fmt.parseInt(u21, part, 16));
    }
    if (values.items.len == offset) return error.BadDecomposition;
    try list.append(arena, .{
        .from = cp,
        .compat = compat,
        .offset = offset,
        .len = values.items.len - offset,
    });
}

fn categoryIndex(name: []const u8) ?usize {
    for (category_names, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate, name)) return index;
    }
    return null;
}

/// Parse one property out of `DerivedCoreProperties.txt`, `PropList.txt`, or
/// `DerivedNormalizationProps.txt`.
fn parseProperty(comptime property: []const u8, arena: Allocator, data: []const u8) ![]const Range {
    var ranges: std.ArrayList(Range) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0 or line[0] == '#') continue;

        const fields = splitFields(line);
        if (fields.len < 2) continue;
        if (!std.mem.eql(u8, fields.get(1), property)) continue;

        const range = try parseRange(fields.get(0));
        try ranges.append(arena, range);
    }
    return ranges.toOwnedSlice(arena);
}

/// `XXXX..YYYY ; Property # comment` to at most six trimmed fields.
const Fields = struct {
    items: [6][]const u8 = @splat(""),
    len: usize = 0,

    fn get(self: Fields, index: usize) []const u8 {
        return if (index < self.len) self.items[index] else "";
    }
};

fn splitFields(line: []const u8) Fields {
    var fields: Fields = .{};
    const body = if (std.mem.findScalar(u8, line, '#')) |hash| line[0..hash] else line;
    var parts = std.mem.splitScalar(u8, body, ';');
    while (parts.next()) |part| {
        if (fields.len == fields.items.len) break;
        fields.items[fields.len] = std.mem.trim(u8, part, " \t\r");
        fields.len += 1;
    }
    return fields;
}

fn parseRange(text: []const u8) !Range {
    if (std.mem.find(u8, text, "..")) |dots| {
        return .{
            .start = try std.fmt.parseInt(u21, text[0..dots], 16),
            .end = try std.fmt.parseInt(u21, text[dots + 2 ..], 16),
        };
    }
    const cp = try std.fmt.parseInt(u21, text, 16);
    return .{ .start = cp, .end = cp };
}

const NamedRanges = struct {
    names: []const []const u8,
    ranges: []const TaggedRange,

    /// Blocks use spaces and hyphens; an enum needs underscores.
    fn convertToIdentifiers(self: *NamedRanges, arena: Allocator) !void {
        const converted = try arena.alloc([]const u8, self.names.len);
        for (self.names, converted) |name, *out| {
            out.* = try identifier(arena, name);
        }
        self.names = converted;
    }
};

fn identifier(arena: Allocator, name: []const u8) ![]const u8 {
    const out = try arena.dupe(u8, name);
    for (out) |*byte| {
        if (byte.* == ' ' or byte.* == '-') byte.* = '_';
    }
    return out;
}

/// The last field of a `# @missing: RANGE; PROPERTY; VALUE` line.
fn missingValue(line: []const u8) []const u8 {
    var value: []const u8 = "";
    var parts = std.mem.splitScalar(u8, line["# @missing:".len..], ';');
    while (parts.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t\r");
        if (trimmed.len > 0) value = trimmed;
    }
    return value;
}

/// A property file whose second field is a value name.
fn parseNamedRanges(arena: Allocator, data: []const u8, value_field: usize) !NamedRanges {
    var named: std.ArrayList(NamedRange) = .empty;
    var names: std.ArrayList([]const u8) = .empty;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "# @missing:")) {
            const name = missingValue(line);
            if (name.len > 0 and indexOf(names.items, name) == null) {
                try names.append(arena, name);
            }
            continue;
        }
        if (line[0] == '#') continue;

        const fields = splitFields(line);
        if (fields.len <= value_field) continue;
        const name = fields.get(value_field);
        if (name.len == 0) continue;

        if (indexOf(names.items, name) == null) try names.append(arena, name);
        const range = try parseRange(fields.get(0));
        try named.append(arena, .{ .start = range.start, .end = range.end, .name = name });
    }

    std.mem.sort(NamedRange, named.items, {}, lessNamed);
    const sorted_names = try names.toOwnedSlice(arena);
    std.mem.sort([]const u8, sorted_names, {}, lessString);

    var ranges: std.ArrayList(TaggedRange) = .empty;
    for (named.items) |entry| {
        const value = indexOf(sorted_names, entry.name) orelse return error.MissingName;
        try addTaggedRange(arena, &ranges, entry.start, entry.end, value);
    }
    return .{ .names = sorted_names, .ranges = try ranges.toOwnedSlice(arena) };
}

fn addTaggedRange(
    arena: Allocator,
    list: *std.ArrayList(TaggedRange),
    start: u21,
    end: u21,
    value: usize,
) !void {
    if (list.items.len > 0) {
        const last = &list.items[list.items.len - 1];
        if (last.value == value and @as(u32, last.end) + 1 == start) {
            last.end = end;
            return;
        }
    }
    try list.append(arena, .{ .start = start, .end = end, .value = value });
}

fn indexOf(names: []const []const u8, name: []const u8) ?usize {
    for (names, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate, name)) return index;
    }
    return null;
}

fn lessNamed(_: void, a: NamedRange, b: NamedRange) bool {
    if (a.start != b.start) return a.start < b.start;
    return a.end < b.end;
}

fn lessString(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

const InCb = struct {
    names: []const []const u8,
    ranges: []const TaggedRange,
};

/// `DerivedCoreProperties.txt` carries `InCB; Linker`, and the value is the
/// third field, not the second.
fn parseInCb(arena: Allocator, data: []const u8) !InCb {
    var named: std.ArrayList(NamedRange) = .empty;
    var names: std.ArrayList([]const u8) = .empty;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "# @missing:")) {
            const name = missingValue(line);
            if (name.len > 0 and indexOf(names.items, name) == null) {
                try names.append(arena, name);
            }
            continue;
        }
        if (line[0] == '#') continue;

        const fields = splitFields(line);
        if (fields.len < 3) continue;
        if (!std.mem.eql(u8, fields.get(1), "InCB")) continue;
        const name = fields.get(2);
        if (indexOf(names.items, name) == null) try names.append(arena, name);
        const range = try parseRange(fields.get(0));
        try named.append(arena, .{ .start = range.start, .end = range.end, .name = name });
    }

    std.mem.sort(NamedRange, named.items, {}, lessNamed);
    const sorted_names = try names.toOwnedSlice(arena);
    std.mem.sort([]const u8, sorted_names, {}, lessString);

    var ranges: std.ArrayList(TaggedRange) = .empty;
    for (named.items) |entry| {
        const value = indexOf(sorted_names, entry.name) orelse return error.MissingName;
        try addTaggedRange(arena, &ranges, entry.start, entry.end, value);
    }
    return .{ .names = sorted_names, .ranges = try ranges.toOwnedSlice(arena) };
}

const SpecialCasing = struct {
    upper: []const MultiMapping,
    lower: []const MultiMapping,
    title: []const MultiMapping,
    final_sigma: []const MultiMapping,
};

fn parseSpecialCasing(arena: Allocator, data: []const u8) !SpecialCasing {
    var upper: std.ArrayList(MultiMapping) = .empty;
    var lower: std.ArrayList(MultiMapping) = .empty;
    var title: std.ArrayList(MultiMapping) = .empty;
    var final_sigma: std.ArrayList(MultiMapping) = .empty;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0 or line[0] == '#') continue;

        const fields = splitFields(line);
        if (fields.len < 4) continue;
        const cp = try std.fmt.parseInt(u21, fields.get(0), 16);
        const conditions = fields.get(4);

        // Language-tagged entries (tr, az, lt) are locale-specific. Root
        // casing uses only the unconditional entries and Final_Sigma.
        if (conditions.len == 0) {
            try addMultiMapping(arena, &lower, cp, fields.get(1));
            try addMultiMapping(arena, &title, cp, fields.get(2));
            try addMultiMapping(arena, &upper, cp, fields.get(3));
        } else if (std.mem.eql(u8, conditions, "Final_Sigma")) {
            try addMultiMapping(arena, &final_sigma, cp, fields.get(1));
        }
    }

    std.mem.sort(MultiMapping, upper.items, {}, lessMultiMapping);
    std.mem.sort(MultiMapping, lower.items, {}, lessMultiMapping);
    std.mem.sort(MultiMapping, title.items, {}, lessMultiMapping);
    std.mem.sort(MultiMapping, final_sigma.items, {}, lessMultiMapping);

    return .{
        .upper = try upper.toOwnedSlice(arena),
        .lower = try lower.toOwnedSlice(arena),
        .title = try title.toOwnedSlice(arena),
        .final_sigma = try final_sigma.toOwnedSlice(arena),
    };
}

fn lessMultiMapping(_: void, a: MultiMapping, b: MultiMapping) bool {
    return a.from < b.from;
}

fn addMultiMapping(
    arena: Allocator,
    list: *std.ArrayList(MultiMapping),
    from: u21,
    field: []const u8,
) !void {
    var mapping: MultiMapping = .{ .from = from, .to = .{ 0, 0, 0 }, .len = 0 };
    var it = std.mem.tokenizeScalar(u8, field, ' ');
    while (it.next()) |part| {
        if (mapping.len == mapping.to.len) return error.BadSpecialCasing;
        mapping.to[mapping.len] = try std.fmt.parseInt(u21, part, 16);
        mapping.len += 1;
    }
    if (mapping.len == 0) return error.BadSpecialCasing;
    // An identity mapping adds nothing to the table.
    if (mapping.len == 1 and mapping.to[0] == from) return;
    try list.append(arena, mapping);
}

const Folds = struct {
    full: []const MultiMapping,
    simple: []const Mapping,
};

fn parseCaseFolding(arena: Allocator, data: []const u8) !Folds {
    var full: std.ArrayList(MultiMapping) = .empty;
    var simple: std.ArrayList(Mapping) = .empty;
    var pending: ?struct { cp: u21, full: ?MultiMapping, simple: ?Mapping } = null;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0 or line[0] == '#') continue;

        const fields = splitFields(line);
        if (fields.len < 3) continue;
        const cp = try std.fmt.parseInt(u21, fields.get(0), 16);
        const status = fields.get(1);
        var mapping = try parseCaseMapping(fields.get(2));
        mapping.from = cp;

        if (pending == null or pending.?.cp != cp) {
            if (pending) |entry| try flushFold(arena, &full, &simple, entry);
            pending = .{ .cp = cp, .full = null, .simple = null };
        }
        if (std.mem.eql(u8, status, "F") or std.mem.eql(u8, status, "C")) {
            pending.?.full = mapping;
        }
        if (std.mem.eql(u8, status, "S") or std.mem.eql(u8, status, "C")) {
            pending.?.simple = .{ .from = cp, .to = mapping.to[0] };
        }
    }
    if (pending) |entry| try flushFold(arena, &full, &simple, entry);

    return .{
        .full = try full.toOwnedSlice(arena),
        .simple = try simple.toOwnedSlice(arena),
    };
}

fn flushFold(
    arena: Allocator,
    full: *std.ArrayList(MultiMapping),
    simple: *std.ArrayList(Mapping),
    entry: anytype,
) !void {
    if (entry.full) |mapping| {
        if (!(mapping.len == 1 and mapping.to[0] == entry.cp)) {
            try full.append(arena, mapping);
        }
    }
    if (entry.simple) |mapping| {
        if (mapping.to != mapping.from) try simple.append(arena, mapping);
    }
}

fn parseCaseMapping(field: []const u8) !MultiMapping {
    var mapping: MultiMapping = .{ .from = 0, .to = .{ 0, 0, 0 }, .len = 0 };
    var it = std.mem.tokenizeScalar(u8, field, ' ');
    while (it.next()) |part| {
        if (mapping.len == mapping.to.len) return error.BadCaseFolding;
        mapping.to[mapping.len] = try std.fmt.parseInt(u21, part, 16);
        mapping.len += 1;
    }
    if (mapping.len == 0) return error.BadCaseFolding;
    return mapping;
}

fn buildCompositions(
    arena: Allocator,
    decompositions: []const Decomposition,
    values: []const u21,
    exclusions: []const Range,
) ![]const Composition {
    var compositions: std.ArrayList(Composition) = .empty;
    for (decompositions) |entry| {
        if (entry.compat or entry.len != 2) continue;
        if (inRanges(exclusions, entry.from)) continue;
        try compositions.append(arena, .{
            .first = values[entry.offset],
            .second = values[entry.offset + 1],
            .composed = entry.from,
        });
    }
    std.mem.sort(Composition, compositions.items, {}, lessComposition);
    return compositions.toOwnedSlice(arena);
}

fn lessComposition(_: void, a: Composition, b: Composition) bool {
    if (a.first != b.first) return a.first < b.first;
    return a.second < b.second;
}

fn inRanges(ranges: []const Range, cp: u21) bool {
    for (ranges) |range| {
        if (cp < range.start) return false;
        if (cp <= range.end) return true;
    }
    return false;
}

const BidiClasses = struct {
    names: []const []const u8,
    ranges: []const TaggedRange,
    defaults: []const TaggedRange,
};

/// `DerivedBidiClass.txt` gives short names on data lines and long names on
/// `@missing` lines. The defaults cover code points with no explicit entry.
fn parseBidiClasses(arena: Allocator, data: []const u8) !BidiClasses {
    const class_names = [_][]const u8{
        "L",   "R",   "AL",  "EN",  "ES",  "ET",  "AN",  "CS",
        "NSM", "BN",  "B",   "S",   "WS",  "ON",  "LRE", "LRO",
        "RLE", "RLO", "PDF", "LRI", "RLI", "FSI", "PDI",
    };
    const defaults = [_]NamedRange{
        .{ .start = 0x0000, .end = 0x10FFFF, .name = "L" },
        .{ .start = 0x0590, .end = 0x05FF, .name = "R" },
        .{ .start = 0x0600, .end = 0x07BF, .name = "AL" },
        .{ .start = 0x07C0, .end = 0x085F, .name = "R" },
        .{ .start = 0x0860, .end = 0x08FF, .name = "AL" },
        .{ .start = 0x20A0, .end = 0x20CF, .name = "ET" },
        .{ .start = 0xFB1D, .end = 0xFB4F, .name = "R" },
        .{ .start = 0xFB50, .end = 0xFDCF, .name = "AL" },
        .{ .start = 0xFDF0, .end = 0xFDFF, .name = "AL" },
        .{ .start = 0xFE70, .end = 0xFEFF, .name = "AL" },
        .{ .start = 0x10800, .end = 0x10CFF, .name = "R" },
        .{ .start = 0x10D00, .end = 0x10D3F, .name = "AL" },
        .{ .start = 0x10D40, .end = 0x10EBF, .name = "R" },
        .{ .start = 0x10EC0, .end = 0x10EFF, .name = "AL" },
        .{ .start = 0x10F00, .end = 0x10F2F, .name = "R" },
        .{ .start = 0x10F30, .end = 0x10F6F, .name = "AL" },
        .{ .start = 0x10F70, .end = 0x10FFF, .name = "R" },
        .{ .start = 0x1E800, .end = 0x1EC6F, .name = "R" },
        .{ .start = 0x1EC70, .end = 0x1ECBF, .name = "AL" },
        .{ .start = 0x1ECC0, .end = 0x1ECFF, .name = "R" },
        .{ .start = 0x1ED00, .end = 0x1ED4F, .name = "AL" },
        .{ .start = 0x1ED50, .end = 0x1EDFF, .name = "R" },
        .{ .start = 0x1EE00, .end = 0x1EEFF, .name = "AL" },
        .{ .start = 0x1EF00, .end = 0x1EFFF, .name = "R" },
    };

    var named: std.ArrayList(NamedRange) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0 or line[0] == '#') continue;
        const fields = splitFields(line);
        if (fields.len < 2) continue;
        const name = fields.get(1);
        if (indexOf(&class_names, name) == null) return error.UnknownBidiClass;
        const range = try parseRange(fields.get(0));
        try named.append(arena, .{ .start = range.start, .end = range.end, .name = name });
    }

    std.mem.sort(NamedRange, named.items, {}, lessNamed);
    const sorted_names = try arena.dupe([]const u8, &class_names);
    std.mem.sort([]const u8, sorted_names, {}, lessString);

    var ranges: std.ArrayList(TaggedRange) = .empty;
    for (named.items) |entry| {
        const value = indexOf(sorted_names, entry.name) orelse return error.MissingName;
        try addTaggedRange(arena, &ranges, entry.start, entry.end, value);
    }

    var default_ranges: std.ArrayList(TaggedRange) = .empty;
    for (defaults) |entry| {
        const value = indexOf(sorted_names, entry.name) orelse return error.MissingName;
        try default_ranges.append(arena, .{
            .start = entry.start,
            .end = entry.end,
            .value = value,
        });
    }

    return .{
        .names = sorted_names,
        .ranges = try ranges.toOwnedSlice(arena),
        .defaults = try default_ranges.toOwnedSlice(arena),
    };
}

fn parseBrackets(arena: Allocator, data: []const u8) ![]const Bracket {
    var brackets: std.ArrayList(Bracket) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0 or line[0] == '#') continue;
        const fields = splitFields(line);
        if (fields.len < 3) continue;
        try brackets.append(arena, .{
            .cp = try std.fmt.parseInt(u21, fields.get(0), 16),
            .pair = try std.fmt.parseInt(u21, fields.get(1), 16),
            .kind = if (std.mem.eql(u8, fields.get(2), "o")) 0 else 1,
        });
    }
    std.mem.sort(Bracket, brackets.items, {}, lessBracket);
    return brackets.toOwnedSlice(arena);
}

fn lessBracket(_: void, a: Bracket, b: Bracket) bool {
    return a.cp < b.cp;
}

fn parseMirrors(arena: Allocator, data: []const u8) ![]const Mirror {
    var mirrors: std.ArrayList(Mirror) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0 or line[0] == '#') continue;
        const fields = splitFields(line);
        if (fields.len < 2) continue;
        try mirrors.append(arena, .{
            .from = try std.fmt.parseInt(u21, fields.get(0), 16),
            .to = try std.fmt.parseInt(u21, fields.get(1), 16),
        });
    }
    std.mem.sort(Mirror, mirrors.items, {}, lessMirror);
    return mirrors.toOwnedSlice(arena);
}

fn lessMirror(_: void, a: Mirror, b: Mirror) bool {
    return a.from < b.from;
}

const Emitter = struct {
    arena: Allocator,
    bytes: std.ArrayList(u8) = .empty,

    fn write(self: *Emitter, text: []const u8) !void {
        try self.bytes.appendSlice(self.arena, text);
    }

    fn print(self: *Emitter, comptime format: []const u8, args: anytype) !void {
        try self.bytes.appendSlice(self.arena, try self.arena.print(format, args));
    }
};

fn writeOutput(arena: Allocator, out: *std.ArrayList(u8), output: *const Output) !void {
    var emitter: Emitter = .{ .arena = arena };
    const e = &emitter;

    try e.write(
        \\//! Generated from the Unicode Character Database. Do not edit.
        \\//!
        \\//! Regenerate with `just regen`; it fetches the pinned UCD release
        \\//! and runs the generator.
        \\
        \\
    );
    try e.print("pub const version = \"{s}\";\n\n", .{output.version});

    try e.write(
        \\/// The general categories.
        \\pub const Category = enum {
        \\
    );
    for (category_names) |name| {
        try e.print("    {s},\n", .{name});
    }
    try e.write(
        \\};
        \\
        \\/// One contiguous run of code points.
        \\pub const Range = struct {
        \\    start: u21,
        \\    end: u21,
        \\};
        \\
        \\/// A range tagged with a value.
        \\pub fn TaggedRange(comptime T: type) type {
        \\    return struct {
        \\        start: u21,
        \\        end: u21,
        \\        value: T,
        \\    };
        \\}
        \\
        \\/// A range tagged with its general category.
        \\pub const CategoryRange = struct {
        \\    start: u21,
        \\    end: u21,
        \\    category: Category,
        \\};
        \\
        \\/// One simple case mapping.
        \\pub const Mapping = struct {
        \\    from: u21,
        \\    to: u21,
        \\};
        \\
        \\/// One case mapping that can expand to three code points.
        \\pub const MultiMapping = struct {
        \\    from: u21,
        \\    len: u8,
        \\    to: [3]u21,
        \\};
        \\
        \\/// One nonzero canonical combining class.
        \\pub const CccRange = struct {
        \\    start: u21,
        \\    end: u21,
        \\    ccc: u8,
        \\};
        \\
        \\/// One decomposition. `offset` and `len` index `decomposition_values`.
        \\pub const Decomposition = struct {
        \\    from: u21,
        \\    compat: bool,
        \\    offset: u32,
        \\    len: u8,
        \\};
        \\
        \\/// One primary composite.
        \\pub const Composition = struct {
        \\    first: u21,
        \\    second: u21,
        \\    composed: u21,
        \\};
        \\
        \\/// One paired bracket from `BidiBrackets.txt`.
        \\pub const Bracket = struct {
        \\    cp: u21,
        \\    pair: u21,
        \\    kind: enum { open, close },
        \\};
        \\
        \\/// One mirrored glyph from `BidiMirroring.txt`.
        \\pub const Mirror = struct {
        \\    from: u21,
        \\    to: u21,
        \\};
        \\
        \\/// One input file and its SHA-256.
        \\pub const Source = struct {
        \\    name: []const u8,
        \\    sha256: [64]u8,
        \\};
        \\
        \\
    );

    try emitCategoryRanges(e, output.categories);
    try emitRanges(
        e,
        "white_space",
        "Code points with the White_Space property.",
        output.white_space,
    );
    try emitRanges(
        e,
        "bidi_mirrored",
        "The Bidi_Mirrored property.",
        output.bidi_mirrored,
    );
    try emitRanges(e, "id_start", "UAX #31 ID_Start.", output.id_start);
    try emitRanges(e, "id_continue", "UAX #31 ID_Continue.", output.id_continue);
    try emitRanges(e, "xid_start", "UAX #31 XID_Start.", output.xid_start);
    try emitRanges(e, "xid_continue", "UAX #31 XID_Continue.", output.xid_continue);
    try emitRanges(e, "cased", "The Cased property.", output.cased);
    try emitRanges(e, "case_ignorable", "The Case_Ignorable property.", output.case_ignorable);
    try emitMappings(
        e,
        "upper",
        "Simple uppercase mappings, ascending by `from`.",
        output.upper,
    );
    try emitMappings(
        e,
        "lower",
        "Simple lowercase mappings, ascending by `from`.",
        output.lower,
    );
    try emitMappings(
        e,
        "title",
        "Simple titlecase mappings, ascending by `from`.",
        output.title,
    );
    try emitMultiMappings(
        e,
        "full_upper",
        "Unconditional full uppercase mappings.",
        output.full_upper,
    );
    try emitMultiMappings(
        e,
        "full_lower",
        "Unconditional full lowercase mappings.",
        output.full_lower,
    );
    try emitMultiMappings(
        e,
        "full_title",
        "Unconditional full titlecase mappings.",
        output.full_title,
    );
    try emitMultiMappings(
        e,
        "final_sigma",
        "The Final_Sigma lowercase mappings.",
        output.final_sigma,
    );
    try emitMultiMappings(
        e,
        "fold_full",
        "Full case folding, ascending by `from`.",
        output.fold_full,
    );
    try emitMappings(
        e,
        "fold_simple",
        "Simple case folding, ascending by `from`.",
        output.fold_simple,
    );
    try emitNamedRanges(
        e,
        "script_ranges",
        "Script",
        "The Script property.",
        output.scripts,
        output.script_ranges,
    );
    try emitNamedRanges(
        e,
        "block_ranges",
        "Block",
        "The Block property.",
        output.blocks,
        output.block_ranges,
    );
    try emitCcc(e, output.ccc);
    try emitDecompositions(e, output.decompositions, output.decomposition_values);
    try emitCompositions(e, output.compositions);
    try emitNamedRanges(
        e,
        "grapheme_ranges",
        "GraphemeBreak",
        "UAX #29 Grapheme_Cluster_Break.",
        output.grapheme_breaks,
        output.grapheme_ranges,
    );
    try emitNamedRanges(
        e,
        "word_ranges",
        "WordBreak",
        "UAX #29 Word_Break.",
        output.word_breaks,
        output.word_ranges,
    );
    try emitNamedRanges(
        e,
        "sentence_ranges",
        "SentenceBreak",
        "UAX #29 Sentence_Break.",
        output.sentence_breaks,
        output.sentence_ranges,
    );
    try emitRanges(
        e,
        "extended_pictographic",
        "The Extended_Pictographic property.",
        output.extended_pictographic,
    );
    try emitNamedRanges(
        e,
        "incb_ranges",
        "InCb",
        "Indic_Conjunct_Break.",
        output.incb,
        output.incb_ranges,
    );
    try emitNamedRanges(
        e,
        "bidi_ranges",
        "BidiClass",
        "The Bidi_Class property.",
        output.bidi_classes,
        output.bidi_ranges,
    );
    try emitBidiDefaults(e, output.bidi_classes, output.bidi_defaults);
    try emitBrackets(e, output.brackets);
    try emitMirrors(e, output.mirrors);
    try emitSources(e, output.sources);

    out.* = emitter.bytes;
}

fn emitCategoryRanges(e: *Emitter, ranges: []const CategoryRange) !void {
    try e.write(
        \\/// The category of every code point that is not Cn.
        \\pub const category_ranges = [_]CategoryRange{
        \\
    );
    for (ranges) |range| {
        try e.print(
            "    .{{ .start = 0x{X:0>6}, .end = 0x{X:0>6}, .category = .{s} }},\n",
            .{ range.start, range.end, category_names[range.category] },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitRanges(e: *Emitter, name: []const u8, doc: []const u8, ranges: []const Range) !void {
    try e.print("/// {s}\npub const {s} = [_]Range{{\n", .{ doc, name });
    for (ranges) |range| {
        try e.print(
            "    .{{ .start = 0x{X:0>6}, .end = 0x{X:0>6} }},\n",
            .{ range.start, range.end },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitMappings(
    e: *Emitter,
    name: []const u8,
    doc: []const u8,
    mappings: []const Mapping,
) !void {
    try e.print("/// {s}\npub const {s} = [_]Mapping{{\n", .{ doc, name });
    for (mappings) |mapping| {
        try e.print(
            "    .{{ .from = 0x{X:0>6}, .to = 0x{X:0>6} }},\n",
            .{ mapping.from, mapping.to },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitMultiMappings(
    e: *Emitter,
    name: []const u8,
    doc: []const u8,
    mappings: []const MultiMapping,
) !void {
    try e.print("/// {s}\npub const {s} = [_]MultiMapping{{\n", .{ doc, name });
    for (mappings) |mapping| {
        try e.print(
            "    .{{ .from = 0x{X:0>6}, .len = {d}, .to = .{{ " ++
                "0x{X:0>6}, 0x{X:0>6}, 0x{X:0>6} }} }},\n",
            .{ mapping.from, mapping.len, mapping.to[0], mapping.to[1], mapping.to[2] },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitBidiDefaults(
    e: *Emitter,
    names: []const []const u8,
    ranges: []const TaggedRange,
) !void {
    try e.write(
        \\/// Bidi_Class for code points with no explicit entry.
        \\pub const bidi_defaults = [_]TaggedRange(BidiClass){
        \\
    );
    for (ranges) |range| {
        try e.print(
            "    .{{ .start = 0x{X:0>6}, .end = 0x{X:0>6}, .value = .{s} }},\n",
            .{ range.start, range.end, names[range.value] },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitNamedRanges(
    e: *Emitter,
    name: []const u8,
    comptime enum_name: []const u8,
    doc: []const u8,
    names: []const []const u8,
    ranges: []const TaggedRange,
) !void {
    try e.print("/// {s}\npub const {s} = enum {{\n", .{ doc, enum_name });
    for (names) |value| {
        try e.print("    {s},\n", .{value});
    }
    try e.write(
        \\};
        \\
        \\
    );
    try e.print(
        "/// The values of `{s}`.\npub const {s} = [_]TaggedRange({s}){{\n",
        .{ enum_name, name, enum_name },
    );
    for (ranges) |range| {
        try e.print(
            "    .{{ .start = 0x{X:0>6}, .end = 0x{X:0>6}, .value = .{s} }},\n",
            .{ range.start, range.end, names[range.value] },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitCcc(e: *Emitter, ranges: []const CccRange) !void {
    try e.write(
        \\/// Nonzero canonical combining classes. Code points not listed are 0.
        \\pub const ccc = [_]CccRange{
        \\
    );
    for (ranges) |range| {
        try e.print(
            "    .{{ .start = 0x{X:0>6}, .end = 0x{X:0>6}, .ccc = {d} }},\n",
            .{ range.start, range.end, range.ccc },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitDecompositions(
    e: *Emitter,
    decompositions: []const Decomposition,
    values: []const u21,
) !void {
    try e.write(
        \\/// Decompositions, ascending by `from`.
        \\pub const decompositions = [_]Decomposition{
        \\
    );
    for (decompositions) |entry| {
        try e.print(
            "    .{{ .from = 0x{X:0>6}, .compat = {}, .offset = {d}, .len = {d} }},\n",
            .{ entry.from, entry.compat, entry.offset, entry.len },
        );
    }
    try e.write(
        \\};
        \\
        \\/// The code points each decomposition expands to.
        \\pub const decomposition_values = [_]u21{
        \\
    );
    for (values, 0..) |value, index| {
        if (index % 10 == 0) try e.write("    ") else try e.write(" ");
        try e.print("0x{X:0>6},", .{value});
        if (index % 10 == 9 or index + 1 == values.len) try e.write("\n");
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitCompositions(e: *Emitter, compositions: []const Composition) !void {
    try e.write(
        \\/// Primary composites, ascending by `first` then `second`.
        \\pub const compositions = [_]Composition{
        \\
    );
    for (compositions) |entry| {
        try e.print(
            "    .{{ .first = 0x{X:0>6}, .second = 0x{X:0>6}, .composed = 0x{X:0>6} }},\n",
            .{ entry.first, entry.second, entry.composed },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitBrackets(e: *Emitter, brackets: []const Bracket) !void {
    try e.write(
        \\/// Paired brackets, ascending by `cp`.
        \\pub const brackets = [_]Bracket{
        \\
    );
    for (brackets) |entry| {
        try e.print(
            "    .{{ .cp = 0x{X:0>6}, .pair = 0x{X:0>6}, .kind = .{s} }},\n",
            .{ entry.cp, entry.pair, if (entry.kind == 0) "open" else "close" },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitMirrors(e: *Emitter, mirrors: []const Mirror) !void {
    try e.write(
        \\/// Mirrored glyph mappings, ascending by `from`.
        \\pub const mirrors = [_]Mirror{
        \\
    );
    for (mirrors) |entry| {
        try e.print(
            "    .{{ .from = 0x{X:0>6}, .to = 0x{X:0>6} }},\n",
            .{ entry.from, entry.to },
        );
    }
    try e.write(
        \\};
        \\
        \\
    );
}

fn emitSources(e: *Emitter, sources: []const Source) !void {
    try e.write(
        \\/// The files this table came from, with the SHA-256 of each.
        \\pub const sources = [_]Source{
        \\
    );
    for (sources) |source| {
        try e.print(
            "    .{{ .name = \"{s}\", .sha256 = \"{s}\" }},\n",
            .{ source.name, source.sha256 },
        );
    }
    try e.write(
        \\};
        \\
    );
}

test "parse a property line" {
    const fields = splitFields("0041..005A    ; ID_Start # L&  [26] LATIN CAPITAL LETTER A");
    try std.testing.expectEqualStrings("0041..005A", fields.get(0));
    try std.testing.expectEqualStrings("ID_Start", fields.get(1));
}

test "parse a range" {
    const range = try parseRange("0041..005A");
    try std.testing.expectEqual(@as(u21, 0x41), range.start);
    try std.testing.expectEqual(@as(u21, 0x5A), range.end);
    const single = try parseRange("2118");
    try std.testing.expectEqual(@as(u21, 0x2118), single.start);
    try std.testing.expectEqual(single.start, single.end);
}

test "identifiers replace block punctuation" {
    const arena = std.testing.allocator;
    const name = try identifier(arena, "Latin-1 Supplement");
    defer arena.free(name);
    try std.testing.expectEqualStrings("Latin_1_Supplement", name);
}
