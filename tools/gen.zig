//! Generate `tables.zig` from three Unicode Character Database files.
//!
//! The generator reads the files named on the command line and writes one Zig
//! source file. `zig build regen` runs it against the pinned UCD release.
//!
//! Usage: gen --out PATH UnicodeData.txt DerivedCoreProperties.txt PropList.txt

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const usage =
    \\Usage: gen --out PATH UnicodeData.txt DerivedCoreProperties.txt PropList.txt
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

const Output = struct {
    version: []const u8,
    unicode_data_sha: [64]u8,
    derived_core_sha: [64]u8,
    prop_list_sha: [64]u8,
    categories: []const CategoryRange,
    white_space: []const Range,
    id_start: []const Range,
    id_continue: []const Range,
    xid_start: []const Range,
    xid_continue: []const Range,
    upper: []const Mapping,
    lower: []const Mapping,
    title: []const Mapping,
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

const Args = struct {
    out: []const u8,
    unicode_data: []const u8,
    derived_core: []const u8,
    prop_list: []const u8,
};

fn parseArgs(argv: std.process.Args) ?Args {
    var it = std.process.Args.iterate(argv);
    _ = it.skip();
    var out: ?[]const u8 = null;
    var files: [3][]const u8 = undefined;
    var count: usize = 0;
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out")) {
            out = it.next() orelse return null;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return null;
        } else if (count < files.len) {
            files[count] = arg;
            count += 1;
        } else {
            return null;
        }
    }
    if (out == null or count != files.len) return null;
    return .{
        .out = out.?,
        .unicode_data = files[0],
        .derived_core = files[1],
        .prop_list = files[2],
    };
}

fn run(arena: Allocator, io: Io, args: Args) !void {
    const unicode_data = try Io.Dir.cwd().readFileAlloc(
        io,
        args.unicode_data,
        arena,
        .limited(32 << 20),
    );
    const derived_core = try Io.Dir.cwd().readFileAlloc(
        io,
        args.derived_core,
        arena,
        .limited(32 << 20),
    );
    const prop_list = try Io.Dir.cwd().readFileAlloc(
        io,
        args.prop_list,
        arena,
        .limited(32 << 20),
    );

    const version = try parseVersion(derived_core);
    var mappings: Mappings = undefined;
    const categories = try parseUnicodeData(arena, unicode_data, &mappings);
    const white_space = try parseProperty("White_Space", arena, prop_list);
    const id_start = try parseProperty("ID_Start", arena, derived_core);
    const id_continue = try parseProperty("ID_Continue", arena, derived_core);
    const xid_start = try parseProperty("XID_Start", arena, derived_core);
    const xid_continue = try parseProperty("XID_Continue", arena, derived_core);

    var unicode_sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(unicode_data, &unicode_sha, .{});
    var core_sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(derived_core, &core_sha, .{});
    var props_sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(prop_list, &props_sha, .{});

    const output: Output = .{
        .version = version,
        .unicode_data_sha = std.fmt.bytesToHex(unicode_sha, .lower),
        .derived_core_sha = std.fmt.bytesToHex(core_sha, .lower),
        .prop_list_sha = std.fmt.bytesToHex(props_sha, .lower),
        .categories = categories.ranges,
        .white_space = white_space,
        .id_start = id_start,
        .id_continue = id_continue,
        .xid_start = xid_start,
        .xid_continue = xid_continue,
        .upper = mappings.upper,
        .lower = mappings.lower,
        .title = mappings.title,
    };

    var text: std.ArrayList(u8) = .empty;
    try writeOutput(arena, &text, &output);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = args.out, .data = text.items });
}

const Version = struct {
    string: []const u8,
    mappings: Mappings,
};

const Mappings = struct {
    upper: []const Mapping,
    lower: []const Mapping,
    title: []const Mapping,
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

const Categories = struct {
    ranges: []const CategoryRange,
};

fn parseUnicodeData(arena: Allocator, data: []const u8, mappings: *Mappings) !Categories {
    var ranges: std.ArrayList(CategoryRange) = .empty;
    var upper: std.ArrayList(Mapping) = .empty;
    var lower: std.ArrayList(Mapping) = .empty;
    var title: std.ArrayList(Mapping) = .empty;

    var lines = std.mem.splitScalar(u8, data, '\n');
    var first: ?struct { cp: u21, category: usize } = null;
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

        if (std.mem.endsWith(u8, name, ", First>")) {
            first = .{ .cp = cp, .category = category };
            continue;
        }
        if (std.mem.endsWith(u8, name, ", Last>")) {
            const open = first orelse return error.BadUnicodeData;
            if (open.category != category) return error.BadUnicodeData;
            try addRange(arena, &ranges, open.cp, cp, category);
            first = null;
            continue;
        }
        try addRange(arena, &ranges, cp, cp, category);

        try addMapping(arena, &upper, cp, fields[12]);
        try addMapping(arena, &lower, cp, fields[13]);
        try addMapping(arena, &title, cp, fields[14]);
    }
    if (first != null) return error.BadUnicodeData;

    mappings.* = .{
        .upper = try upper.toOwnedSlice(arena),
        .lower = try lower.toOwnedSlice(arena),
        .title = try title.toOwnedSlice(arena),
    };
    return .{ .ranges = try ranges.toOwnedSlice(arena) };
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

fn addRange(
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

fn categoryIndex(name: []const u8) ?usize {
    for (category_names, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate, name)) return index;
    }
    return null;
}

/// Parse one property out of `DerivedCoreProperties.txt` or `PropList.txt`.
fn parseProperty(comptime property: []const u8, arena: Allocator, data: []const u8) ![]const Range {
    var ranges: std.ArrayList(Range) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0 or line[0] == '#') continue;

        const fields = splitFields(line);
        if (fields.len < 2) continue;
        const name = std.mem.trim(u8, fields[1], " \t");
        if (!std.mem.eql(u8, name, property)) continue;

        const text = std.mem.trim(u8, fields[0], " \t");
        const range = try parseRange(text);
        try ranges.append(arena, range);
    }
    return ranges.toOwnedSlice(arena);
}

/// `XXXX..YYYY ; Property # comment` to at most four trimmed fields.
fn splitFields(line: []const u8) [4][]const u8 {
    var fields: [4][]const u8 = @splat("");
    const body = if (std.mem.findScalar(u8, line, '#')) |hash| line[0..hash] else line;
    var count: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index < body.len and count < fields.len) : (index += 1) {
        if (body[index] == ';') {
            fields[count] = std.mem.trim(u8, body[start..index], " \t");
            count += 1;
            start = index + 1;
        }
    }
    if (count < fields.len) {
        fields[count] = std.mem.trim(u8, body[start..], " \t");
        count += 1;
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
        \\//! Regenerate with `just regen`; it runs `zig build regen` against
        \\//! the UCD release pinned in `build.zig.zon`.
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
        \\
    );

    try emitCategoryRanges(e, output.categories);
    try emitRanges(
        e,
        "white_space",
        "Code points with the White_Space property.",
        output.white_space,
    );
    try emitRanges(e, "id_start", "UAX #31 ID_Start.", output.id_start);
    try emitRanges(e, "id_continue", "UAX #31 ID_Continue.", output.id_continue);
    try emitRanges(e, "xid_start", "UAX #31 XID_Start.", output.xid_start);
    try emitRanges(e, "xid_continue", "UAX #31 XID_Continue.", output.xid_continue);
    try emitMappings(e, "upper", "Simple uppercase mappings, ascending by `from`.", output.upper);
    try emitMappings(e, "lower", "Simple lowercase mappings, ascending by `from`.", output.lower);
    try emitMappings(e, "title", "Simple titlecase mappings, ascending by `from`.", output.title);

    try e.print(
        \\/// The files this table came from, with the SHA-256 of each.
        \\pub const sources = .{{
        \\    .unicode_data = "UnicodeData.txt sha256 {s}",
        \\    .derived_core = "DerivedCoreProperties.txt sha256 {s}",
        \\    .prop_list = "PropList.txt sha256 {s}",
        \\}};
        \\
    , .{
        output.unicode_data_sha,
        output.derived_core_sha,
        output.prop_list_sha,
    });

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

fn emitRanges(
    e: *Emitter,
    name: []const u8,
    doc: []const u8,
    ranges: []const Range,
) !void {
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

test "parse a property line" {
    const fields = splitFields("0041..005A    ; ID_Start # L&  [26] LATIN CAPITAL LETTER A");
    try std.testing.expectEqualStrings("0041..005A", fields[0]);
    try std.testing.expectEqualStrings("ID_Start", fields[1]);
}

test "parse a range" {
    const range = try parseRange("0041..005A");
    try std.testing.expectEqual(@as(u21, 0x41), range.start);
    try std.testing.expectEqual(@as(u21, 0x5A), range.end);
    const single = try parseRange("2118");
    try std.testing.expectEqual(@as(u21, 0x2118), single.start);
    try std.testing.expectEqual(single.start, single.end);
}
