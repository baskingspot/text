//! Unicode normalization forms.
//!
//! `normalize` implements the four forms from UAX #15: NFC, NFD, NFKC, and
//! NFKD. It works on code points, so a UTF-8 caller decodes and re-encodes.
//! The data comes from `UnicodeData.txt`, `DerivedNormalizationProps.txt`, and
//! the Hangul syllable algorithm.

const std = @import("std");
const tables = @import("tables.zig");
const build_options = @import("build_options");

/// One of the four normalization forms.
pub const Form = enum {
    /// Canonical decomposition.
    nfd,
    /// Canonical decomposition followed by canonical composition.
    nfc,
    /// Compatibility decomposition.
    nfkd,
    /// Compatibility decomposition followed by canonical composition.
    nfkc,
};

/// Normalize `input` into `form`. The caller frees the result.
pub fn normalize(
    allocator: std.mem.Allocator,
    form: Form,
    input: []const u21,
) ![]u21 {
    var out: std.ArrayList(u21) = .empty;
    errdefer out.deinit(allocator);

    const compatibility = form == .nfkc or form == .nfkd;
    for (input) |cp| {
        try decomposeInto(allocator, &out, cp, compatibility);
    }
    canonicalOrder(out.items);

    if (form == .nfc or form == .nfkc) {
        out.shrinkRetainingCapacity(compose(out.items));
    }
    return out.toOwnedSlice(allocator);
}

/// True when `input` is already in `form`. The check normalizes and compares,
/// so it allocates.
pub fn isNormalized(
    allocator: std.mem.Allocator,
    form: Form,
    input: []const u21,
) !bool {
    const normalized = try normalize(allocator, form, input);
    defer allocator.free(normalized);
    return std.mem.eql(u21, normalized, input);
}

/// The canonical combining class of `cp`. Code points with no entry are 0.
pub fn combiningClass(cp: u21) u8 {
    var low: usize = 0;
    var high: usize = tables.ccc.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = tables.ccc[mid];
        if (cp < range.start) {
            high = mid;
        } else if (cp > range.end) {
            low = mid + 1;
        } else {
            return range.ccc;
        }
    }
    return 0;
}

const hangul = struct {
    const s_base: u21 = 0xAC00;
    const l_base: u21 = 0x1100;
    const v_base: u21 = 0x1161;
    const t_base: u21 = 0x11A7;
    const l_count: u21 = 19;
    const v_count: u21 = 21;
    const t_count: u21 = 28;
    const n_count: u21 = v_count * t_count;
    const s_count: u21 = l_count * n_count;
};

fn decomposeInto(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u21),
    cp: u21,
    compatibility: bool,
) !void {
    if (cp >= hangul.s_base and cp < hangul.s_base + hangul.s_count) {
        const index = cp - hangul.s_base;
        try out.append(allocator, hangul.l_base + index / hangul.n_count);
        try out.append(allocator, hangul.v_base + (index % hangul.n_count) / hangul.t_count);
        const trailing = index % hangul.t_count;
        if (trailing != 0) {
            try out.append(allocator, hangul.t_base + trailing);
        }
        return;
    }

    if (decomposition(cp)) |entry| {
        if (entry.compat and !compatibility) {
            try out.append(allocator, cp);
            return;
        }
        const sequence = tables.decomposition_values[entry.offset..][0..entry.len];
        for (sequence) |part| {
            try decomposeInto(allocator, out, part, compatibility);
        }
        return;
    }

    try out.append(allocator, cp);
}

const Decomposition = struct {
    offset: usize,
    len: usize,
    compat: bool,
};

fn decomposition(cp: u21) ?Decomposition {
    var low: usize = 0;
    var high: usize = tables.decompositions.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const entry = tables.decompositions[mid];
        if (cp < entry.from) {
            high = mid;
        } else if (cp > entry.from) {
            low = mid + 1;
        } else {
            return .{
                .offset = entry.offset,
                .len = entry.len,
                .compat = entry.compat,
            };
        }
    }
    return null;
}

/// Stable insertion sort by combining class, one starter-delimited segment at
/// a time. A starter (class 0) never moves.
fn canonicalOrder(items: []u21) void {
    var index: usize = 1;
    while (index < items.len) : (index += 1) {
        const ccc = combiningClass(items[index]);
        if (ccc == 0) continue;

        var position = index;
        while (position > 0) {
            const previous = combiningClass(items[position - 1]);
            if (previous <= ccc) break;
            std.mem.swap(u21, &items[position - 1], &items[position]);
            position -= 1;
        }
    }
}

/// Compose `items` in place and return the new length. Hangul syllables are
/// composed algorithmically; the rest are in the composition table.
fn compose(items: []u21) usize {
    if (items.len == 0) return 0;

    var starter_index: usize = 0;
    var starter = items[0];
    var last_ccc: u8 = 0;
    var write: usize = 1;

    var read: usize = 1;
    while (read < items.len) : (read += 1) {
        const cp = items[read];
        const ccc = combiningClass(cp);

        if (last_ccc == 0 or last_ccc < ccc) {
            if (composePair(starter, cp)) |composed| {
                items[starter_index] = composed;
                starter = composed;
                continue;
            }
        }

        items[write] = cp;
        write += 1;
        if (ccc == 0) {
            starter_index = write - 1;
            starter = cp;
            last_ccc = 0;
        } else {
            last_ccc = ccc;
        }
    }
    return write;
}

fn composePair(first: u21, second: u21) ?u21 {
    if (first >= hangul.l_base and first < hangul.l_base + hangul.l_count and
        second >= hangul.v_base and second < hangul.v_base + hangul.v_count)
    {
        const l_index = first - hangul.l_base;
        const v_index = second - hangul.v_base;
        return hangul.s_base + (l_index * hangul.v_count + v_index) * hangul.t_count;
    }

    if (first >= hangul.s_base and first < hangul.s_base + hangul.s_count and
        (first - hangul.s_base) % hangul.t_count == 0 and
        second > hangul.t_base and second < hangul.t_base + hangul.t_count)
    {
        return first + (second - hangul.t_base);
    }

    var low: usize = 0;
    var high: usize = tables.compositions.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const entry = tables.compositions[mid];
        if (first < entry.first) {
            high = mid;
        } else if (first > entry.first) {
            low = mid + 1;
        } else if (second < entry.second) {
            high = mid;
        } else if (second > entry.second) {
            low = mid + 1;
        } else {
            return entry.composed;
        }
    }
    return null;
}

const testing = std.testing;

test "canonical decomposition and composition" {
    const allocator = testing.allocator;

    const decomposed = try normalize(allocator, .nfd, &.{0x00C5});
    defer allocator.free(decomposed);
    try testing.expectEqualSlices(u21, &.{ 'A', 0x030A }, decomposed);

    const composed = try normalize(allocator, .nfc, decomposed);
    defer allocator.free(composed);
    try testing.expectEqualSlices(u21, &.{0x00C5}, composed);
}

test "compatibility decomposition" {
    const allocator = testing.allocator;

    const decomposed = try normalize(allocator, .nfkd, &.{0xFB01});
    defer allocator.free(decomposed);
    try testing.expectEqualSlices(u21, &.{ 'f', 'i' }, decomposed);

    const canonical = try normalize(allocator, .nfd, &.{0xFB01});
    defer allocator.free(canonical);
    try testing.expectEqualSlices(u21, &.{0xFB01}, canonical);
}

test "canonical order sorts combining marks" {
    const allocator = testing.allocator;

    // a + marking above (230) + marking below (220) reorders below first.
    const ordered = try normalize(allocator, .nfd, &.{ 'a', 0x0301, 0x0323 });
    defer allocator.free(ordered);
    try testing.expectEqualSlices(u21, &.{ 'a', 0x0323, 0x0301 }, ordered);
}

test "Hangul decomposes and composes algorithmically" {
    const allocator = testing.allocator;

    const decomposed = try normalize(allocator, .nfd, &.{0xAC01});
    defer allocator.free(decomposed);
    try testing.expectEqualSlices(u21, &.{ 0x1100, 0x1161, 0x11A8 }, decomposed);

    const composed = try normalize(allocator, .nfc, decomposed);
    defer allocator.free(composed);
    try testing.expectEqualSlices(u21, &.{0xAC01}, composed);
}

test "isNormalized" {
    try testing.expect(try isNormalized(testing.allocator, .nfc, &.{0x00C5}));
    try testing.expect(!try isNormalized(testing.allocator, .nfc, &.{ 'A', 0x030A }));
    try testing.expect(try isNormalized(testing.allocator, .nfd, &.{ 'A', 0x030A }));
}

test "NormalizationTest.txt" {
    const directory = build_options.conformance_dir;
    if (directory.len == 0) return error.SkipZigTest;

    const allocator = testing.allocator;
    const path = try std.Io.Dir.path.join(allocator, &.{ directory, "NormalizationTest.txt" });
    defer allocator.free(path);
    const data = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        path,
        allocator,
        .limited(64 << 20),
    );
    defer allocator.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0 or line[0] == '#' or line[0] == '@') continue;

        const comment = std.mem.findScalar(u8, line, '#') orelse line.len;
        const body = line[0..comment];
        var fields = std.mem.splitScalar(u8, body, ';');
        var columns: [5][]u21 = undefined;
        var count: usize = 0;
        while (count < columns.len) : (count += 1) {
            columns[count] = try parseSequence(allocator, fields.next() orelse "");
        }
        defer for (columns) |column| allocator.free(column);

        const c1 = columns[0];
        const c2 = columns[1];
        const c3 = columns[2];
        const c4 = columns[3];
        const c5 = columns[4];

        try expectNormalized(allocator, .nfc, c1, c2);
        try expectNormalized(allocator, .nfc, c2, c2);
        try expectNormalized(allocator, .nfc, c3, c2);
        try expectNormalized(allocator, .nfc, c4, c4);
        try expectNormalized(allocator, .nfc, c5, c4);

        try expectNormalized(allocator, .nfd, c1, c3);
        try expectNormalized(allocator, .nfd, c2, c3);
        try expectNormalized(allocator, .nfd, c3, c3);
        try expectNormalized(allocator, .nfd, c4, c5);
        try expectNormalized(allocator, .nfd, c5, c5);

        try expectNormalized(allocator, .nfkc, c1, c4);
        try expectNormalized(allocator, .nfkc, c2, c4);
        try expectNormalized(allocator, .nfkc, c3, c4);
        try expectNormalized(allocator, .nfkc, c4, c4);
        try expectNormalized(allocator, .nfkc, c5, c4);

        try expectNormalized(allocator, .nfkd, c1, c5);
        try expectNormalized(allocator, .nfkd, c2, c5);
        try expectNormalized(allocator, .nfkd, c3, c5);
        try expectNormalized(allocator, .nfkd, c4, c5);
        try expectNormalized(allocator, .nfkd, c5, c5);
    }
}

fn parseSequence(allocator: std.mem.Allocator, text: []const u8) ![]u21 {
    var out: std.ArrayList(u21) = .empty;
    errdefer out.deinit(allocator);
    var tokens = std.mem.tokenizeScalar(u8, text, ' ');
    while (tokens.next()) |token| {
        try out.append(allocator, try std.fmt.parseInt(u21, token, 16));
    }
    return out.toOwnedSlice(allocator);
}

fn expectNormalized(
    allocator: std.mem.Allocator,
    form: Form,
    input: []const u21,
    expected: []const u21,
) !void {
    const actual = try normalize(allocator, form, input);
    defer allocator.free(actual);
    try testing.expectEqualSlices(u21, expected, actual);
}
