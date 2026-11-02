//! Unicode character data in Zig, generated from the Unicode Character
//! Database.
//!
//! `category` answers the general category of one code point. The group
//! predicates (`isLetter`, `isMark`, and the rest) are that answer checked
//! against a set. `isIdStart` and `isIdContinue` are UAX #31 identifiers, and
//! the `xid` forms are the NFKC-closed versions. `isWhiteSpace` is the
//! White_Space property. The `toUpper`, `toLower`, and `toTitle` functions are
//! the simple one-to-one mappings.
//!
//! Every table comes from the Unicode Character Database at the release
//! `version` names. `just regen` rebuilds `tables.zig` from the UCD release
//! pinned in `build.zig.zon`; nothing in the table is edited by hand.

const std = @import("std");
const tables = @import("tables.zig");

/// The Unicode release the tables come from, such as `"18.0.0"`.
pub const version = tables.version;

/// A Unicode general category, `Lu` through `Cn`.
pub const Category = tables.Category;

/// A Unicode script, from `Scripts.txt`.
pub const Script = tables.Script;

/// A Unicode block, from `Blocks.txt`.
pub const Block = tables.Block;

/// The highest code point, U+10FFFF.
pub const max_code_point: u21 = 0x10FFFF;

/// The general category of `cp`. A code point with no explicit entry in
/// `UnicodeData.txt` is `.Cn`.
pub fn category(cp: u21) Category {
    return tables.category_stage.get(cp);
}

/// Lu, Ll, Lt, Lm, and Lo.
pub fn isLetter(cp: u21) bool {
    return switch (category(cp)) {
        .Lu, .Ll, .Lt, .Lm, .Lo => true,
        else => false,
    };
}

/// Mn, Mc, and Me.
pub fn isMark(cp: u21) bool {
    return switch (category(cp)) {
        .Mn, .Mc, .Me => true,
        else => false,
    };
}

/// Nd, Nl, and No.
pub fn isNumber(cp: u21) bool {
    return switch (category(cp)) {
        .Nd, .Nl, .No => true,
        else => false,
    };
}

/// Pc, Pd, Ps, Pe, Pi, Pf, and Po.
pub fn isPunctuation(cp: u21) bool {
    return switch (category(cp)) {
        .Pc, .Pd, .Ps, .Pe, .Pi, .Pf, .Po => true,
        else => false,
    };
}

/// Sm, Sc, Sk, and So.
pub fn isSymbol(cp: u21) bool {
    return switch (category(cp)) {
        .Sm, .Sc, .Sk, .So => true,
        else => false,
    };
}

/// Zs, Zl, and Zp.
pub fn isSeparator(cp: u21) bool {
    return switch (category(cp)) {
        .Zs, .Zl, .Zp => true,
        else => false,
    };
}

/// Cc, Cf, Cs, Co, and Cn.
pub fn isOther(cp: u21) bool {
    return switch (category(cp)) {
        .Cc, .Cf, .Cs, .Co, .Cn => true,
        else => false,
    };
}

/// Cc.
pub fn isControl(cp: u21) bool {
    return category(cp) == .Cc;
}

/// Cs.
pub fn isSurrogate(cp: u21) bool {
    return category(cp) == .Cs;
}

/// Co.
pub fn isPrivateUse(cp: u21) bool {
    return category(cp) == .Co;
}

/// Cn.
pub fn isUnassigned(cp: u21) bool {
    return category(cp) == .Cn;
}

/// True for every code point with an assigned category, which is everything
/// except `.Cn`.
pub fn isAssigned(cp: u21) bool {
    return category(cp) != .Cn;
}

/// The script of `cp`, from the Script property. Unassigned code points are
/// `.Unknown`.
pub fn script(cp: u21) Script {
    return tables.script_stage.get(cp);
}

/// The block of `cp`, from the Block property. Code points between blocks are
/// `.No_Block`.
pub fn block(cp: u21) Block {
    return tables.block_stage.get(cp);
}

/// A block and the code points it covers.
pub const BlockRange = tables.BlockRange;

/// The range `block_value` covers, or null when the block has no entries.
pub fn blockRange(block_value: Block) ?BlockRange {
    for (tables.block_ranges) |range| {
        if (range.block == block_value) return range;
    }
    return null;
}

/// The Cased property. Cased letters are those whose case mapping can change,
/// used by the Final_Sigma rule.
pub fn isCased(cp: u21) bool {
    return tables.cased_stage.get(cp);
}

/// The Case_Ignorable property: case mapping skips these when it looks for a
/// neighboring cased letter.
pub fn isCaseIgnorable(cp: u21) bool {
    return tables.case_ignorable_stage.get(cp);
}

/// The White_Space property from `PropList.txt`. It covers ASCII space and
/// tab, the line breaks, the no-break spaces, and the Unicode spaces, and it
/// excludes U+200B.
pub fn isWhiteSpace(cp: u21) bool {
    return tables.white_space_stage.get(cp);
}

/// UAX #31 `ID_Start`. A language that allows `_` or `$` in a name adds that
/// rule itself, because UAX #31 does not.
pub fn isIdStart(cp: u21) bool {
    return tables.id_start_stage.get(cp);
}

/// UAX #31 `ID_Continue`.
pub fn isIdContinue(cp: u21) bool {
    return tables.id_continue_stage.get(cp);
}

/// UAX #31 `XID_Start`, the NFKC-closed form.
pub fn isXidStart(cp: u21) bool {
    return tables.xid_start_stage.get(cp);
}

/// UAX #31 `XID_Continue`, the NFKC-closed form.
pub fn isXidContinue(cp: u21) bool {
    return tables.xid_continue_stage.get(cp);
}

/// The simple uppercase mapping from `UnicodeData.txt`, or `cp` when there is
/// none. `toUpperFull` is the mapping that can expand.
pub fn toUpper(cp: u21) u21 {
    return tables.upper_stage.get(cp);
}

/// The simple lowercase mapping, or `cp` when there is none.
pub fn toLower(cp: u21) u21 {
    return tables.lower_stage.get(cp);
}

/// The simple titlecase mapping, or `cp` when there is none.
pub fn toTitle(cp: u21) u21 {
    return tables.title_stage.get(cp);
}

/// The full uppercase mapping, which can expand to three code points. The
/// result points into `buf`.
pub fn toUpperFull(cp: u21, buf: *[3]u21) []const u21 {
    return fullMapping(&tables.full_upper, tables.upper_stage, cp, buf);
}

/// The full lowercase mapping, which can expand to three code points. The
/// result points into `buf`. The Final_Sigma rule depends on context; `lower`
/// applies it.
pub fn toLowerFull(cp: u21, buf: *[3]u21) []const u21 {
    return fullMapping(&tables.full_lower, tables.lower_stage, cp, buf);
}

/// The full titlecase mapping, which can expand to three code points. The
/// result points into `buf`.
pub fn toTitleFull(cp: u21, buf: *[3]u21) []const u21 {
    return fullMapping(&tables.full_title, tables.title_stage, cp, buf);
}

/// The full uppercase mapping of a string. The caller frees the result.
pub fn upper(allocator: std.mem.Allocator, input: []const u21) ![]u21 {
    var out: std.ArrayList(u21) = .empty;
    for (input) |cp| {
        var buf: [3]u21 = undefined;
        try out.appendSlice(allocator, toUpperFull(cp, &buf));
    }
    return out.toOwnedSlice(allocator);
}

/// The full lowercase mapping of a string, including the Final_Sigma rule.
/// The caller frees the result.
pub fn lower(allocator: std.mem.Allocator, input: []const u21) ![]u21 {
    var out: std.ArrayList(u21) = .empty;
    for (input, 0..) |cp, index| {
        if (findMulti(&tables.final_sigma, cp)) |mapping| {
            if (isFinalSigma(input, index)) {
                try out.appendSlice(allocator, mapping.to[0..mapping.len]);
                continue;
            }
        }
        var buf: [3]u21 = undefined;
        try out.appendSlice(allocator, toLowerFull(cp, &buf));
    }
    return out.toOwnedSlice(allocator);
}

/// The full titlecase mapping applied to each code point. Word-aware title
/// casing belongs to the caller; this does not segment words.
pub fn title(allocator: std.mem.Allocator, input: []const u21) ![]u21 {
    var out: std.ArrayList(u21) = .empty;
    for (input) |cp| {
        var buf: [3]u21 = undefined;
        try out.appendSlice(allocator, toTitleFull(cp, &buf));
    }
    return out.toOwnedSlice(allocator);
}

/// The full case folding of one code point, which can expand to three. The
/// result points into `buf`.
pub fn foldFull(cp: u21, buf: *[3]u21) []const u21 {
    if (findMulti(&tables.fold_full, cp)) |mapping| {
        @memcpy(buf[0..mapping.len], mapping.to[0..mapping.len]);
        return buf[0..mapping.len];
    }
    buf[0] = tables.fold_simple_stage.get(cp);
    return buf[0..1];
}

/// The simple case folding of one code point, or `cp` when there is none.
/// Simple folding does not expand; `ß > ss` needs `foldFull`.
pub fn foldSimple(cp: u21) u21 {
    return tables.fold_simple_stage.get(cp);
}

/// The full case folding of a string. The caller frees the result.
pub fn fold(allocator: std.mem.Allocator, input: []const u21) ![]u21 {
    var out: std.ArrayList(u21) = .empty;
    for (input) |cp| {
        var buf: [3]u21 = undefined;
        try out.appendSlice(allocator, foldFull(cp, &buf));
    }
    return out.toOwnedSlice(allocator);
}

fn fullMapping(
    special: []const tables.MultiMapping,
    simple: tables.MappingStage(u21),
    cp: u21,
    buf: *[3]u21,
) []const u21 {
    if (findMulti(special, cp)) |mapping| {
        @memcpy(buf[0..mapping.len], mapping.to[0..mapping.len]);
        return buf[0..mapping.len];
    }
    buf[0] = simple.get(cp);
    return buf[0..1];
}

fn findMulti(mappings: []const tables.MultiMapping, cp: u21) ?tables.MultiMapping {
    var low: usize = 0;
    var high: usize = mappings.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const mapping = mappings[mid];
        if (cp < mapping.from) {
            high = mid;
        } else if (cp > mapping.from) {
            low = mid + 1;
        } else {
            return mapping;
        }
    }
    return null;
}

fn isFinalSigma(input: []const u21, index: usize) bool {
    var before = index;
    var preceded = false;
    while (before > 0) {
        before -= 1;
        const cp = input[before];
        if (isCaseIgnorable(cp)) continue;
        preceded = isCased(cp);
        break;
    }
    if (!preceded) return false;

    var after = index + 1;
    while (after < input.len) : (after += 1) {
        const cp = input[after];
        if (isCaseIgnorable(cp)) continue;
        return !isCased(cp);
    }
    return true;
}

const testing = std.testing;

test "the table names the release" {
    try testing.expectEqualStrings("18.0.0", version);
}

test "categories" {
    try testing.expectEqual(Category.Lu, category('A'));
    try testing.expectEqual(Category.Ll, category('a'));
    try testing.expectEqual(Category.Nd, category('0'));
    try testing.expectEqual(Category.Zs, category(' '));
    try testing.expectEqual(Category.Mn, category(0x0300));
    try testing.expectEqual(Category.So, category(0x2603));
    try testing.expectEqual(Category.Cs, category(0xD800));
    try testing.expectEqual(Category.Co, category(0xE000));
    try testing.expectEqual(Category.Cn, category(0x10FFFF));
}

test "the group predicates agree with the category" {
    try testing.expect(isLetter('A'));
    try testing.expect(isLetter('δ'));
    try testing.expect(!isLetter('0'));
    try testing.expect(isMark(0x0300));
    try testing.expect(!isMark('A'));
    try testing.expect(isNumber('0'));
    try testing.expect(isNumber(0x2160));
    try testing.expect(isPunctuation(','));
    try testing.expect(isSymbol(0x2603));
    try testing.expect(isSeparator(' '));
    try testing.expect(isControl('\n'));
    try testing.expect(isSurrogate(0xD800));
    try testing.expect(isPrivateUse(0xE000));
    try testing.expect(isUnassigned(0x10FFFF));
    try testing.expect(!isAssigned(0x10FFFF));
    try testing.expect(isAssigned('A'));
}

test "white space" {
    try testing.expect(isWhiteSpace(' '));
    try testing.expect(isWhiteSpace('\t'));
    try testing.expect(isWhiteSpace(0x00A0));
    try testing.expect(isWhiteSpace(0x2028));
    try testing.expect(!isWhiteSpace(0x200B));
    try testing.expect(!isWhiteSpace('a'));
}

test "identifiers" {
    try testing.expect(isIdStart('A'));
    try testing.expect(isIdStart(0x00AA));
    try testing.expect(!isIdStart('_'));
    try testing.expect(!isIdStart('$'));
    try testing.expect(!isIdStart('0'));
    try testing.expect(isIdContinue('_'));
    try testing.expect(isIdContinue('0'));
    try testing.expect(isIdContinue(0x0300));
    try testing.expect(isIdContinue(0x200C));
    try testing.expect(isIdContinue(0x00B7));
    try testing.expect(!isIdContinue('-'));
}

test "the NFKC-closed identifiers differ where NFKC maps the character" {
    // U+037A is ID_Start and ID_Continue, and not XID_Start or XID_Continue:
    // NFKC turns it into a space followed by a combining mark.
    try testing.expect(isIdStart(0x037A));
    try testing.expect(!isXidStart(0x037A));
    try testing.expect(isIdContinue(0x037A));
    try testing.expect(!isXidContinue(0x037A));
}

test "simple case mappings" {
    try testing.expectEqual(@as(u21, 'A'), toUpper('a'));
    try testing.expectEqual(@as(u21, 'a'), toLower('A'));
    try testing.expectEqual(@as(u21, 0x01C5), toTitle(0x01C4));
    // A simple mapping leaves a character alone when the full mapping is
    // more than one code point.
    try testing.expectEqual(@as(u21, 0x00DF), toUpper(0x00DF));
    try testing.expectEqual(@as(u21, 'i'), toLower(0x0130));
    try testing.expectEqual(@as(u21, 0x10FFFF), toUpper(0x10FFFF));
}

test "generated stage tables are well formed" {
    try expectStage(Category, tables.category_stage);
    try expectStage(Script, tables.script_stage);
    try expectStage(Block, tables.block_stage);
    try expectStage(tables.GraphemeBreak, tables.grapheme_stage);
    try expectStage(tables.WordBreak, tables.word_stage);
    try expectStage(tables.SentenceBreak, tables.sentence_stage);
    try expectStage(tables.InCb, tables.incb_stage);
    try expectStage(tables.BidiClass, tables.bidi_stage);
    try expectBoolStage(tables.white_space_stage);
    try expectBoolStage(tables.bidi_mirrored_stage);
    try expectBoolStage(tables.id_start_stage);
    try expectBoolStage(tables.id_continue_stage);
    try expectBoolStage(tables.xid_start_stage);
    try expectBoolStage(tables.xid_continue_stage);
    try expectBoolStage(tables.cased_stage);
    try expectBoolStage(tables.case_ignorable_stage);
    try expectBoolStage(tables.extended_pictographic_stage);
    try expectMappingStage(tables.upper_stage);
    try expectMappingStage(tables.lower_stage);
    try expectMappingStage(tables.title_stage);
    try expectMappingStage(tables.fold_simple_stage);
}

fn expectStage(comptime T: type, stage: tables.Stage(T)) !void {
    try testing.expectEqual(@as(usize, 0x1100), stage.stage1.len);
    try testing.expectEqual(@as(usize, 0), stage.stage2.len % 256);
    for (stage.stage1) |offset| {
        try testing.expect(offset < stage.stage2.len);
        try testing.expectEqual(@as(u16, 0), offset % 256);
    }
}

fn expectBoolStage(stage: tables.BoolStage) !void {
    try testing.expectEqual(@as(usize, 0x1100), stage.stage1.len);
    try testing.expectEqual(@as(usize, 0), stage.stage2.len % 256);
    for (stage.stage1) |offset| {
        try testing.expect(offset < stage.stage2.len);
        try testing.expectEqual(@as(u16, 0), offset % 256);
    }
}

fn expectMappingStage(stage: tables.MappingStage(u21)) !void {
    try testing.expectEqual(@as(usize, 0x1100), stage.stage1.len);
    try testing.expectEqual(@as(usize, 0), stage.stage2.len % 256);
    for (stage.stage1) |offset| {
        try testing.expect(offset < stage.stage2.len);
        try testing.expectEqual(@as(u16, 0), offset % 256);
    }
    for (stage.stage2) |index| try testing.expect(index <= stage.values.len);
}

test "scripts" {
    try testing.expectEqual(Script.Latin, script('A'));
    try testing.expectEqual(Script.Greek, script(0x03B1));
    try testing.expectEqual(Script.Han, script(0x4E00));
    try testing.expectEqual(Script.Common, script('0'));
    try testing.expectEqual(Script.Inherited, script(0x0300));
    try testing.expectEqual(Script.Unknown, script(0x10FFFF));
}

test "blocks" {
    try testing.expectEqual(Block.Basic_Latin, block('A'));
    try testing.expectEqual(Block.Combining_Diacritical_Marks, block(0x0300));
    try testing.expectEqual(Block.CJK_Unified_Ideographs, block(0x4E00));
    try testing.expectEqual(Block.No_Block, block(0x2FE0));
    try testing.expectEqual(Block.Supplementary_Private_Use_Area_B, block(0x10FFFF));

    const latin = blockRange(.Basic_Latin) orelse return error.NoBlock;
    try testing.expectEqual(@as(u21, 0x0000), latin.start);
    try testing.expectEqual(@as(u21, 0x007F), latin.end);
}

test "full case mappings" {
    var buf: [3]u21 = undefined;
    try testing.expectEqualSlices(u21, &.{ 'S', 'S' }, toUpperFull(0x00DF, &buf));
    try testing.expectEqualSlices(u21, &.{'A'}, toUpperFull('a', &buf));
    try testing.expectEqualSlices(u21, &.{ 0x0069, 0x0307 }, toLowerFull(0x0130, &buf));
    try testing.expectEqualSlices(u21, &.{0x01C5}, toTitleFull(0x01C6, &buf));
}

test "string casing and the final sigma" {
    const allocator = testing.allocator;

    const upper_str = try upper(allocator, &.{ 's', 't', 'r', 'a', 0x00DF, 'e' });
    defer allocator.free(upper_str);
    try testing.expectEqualSlices(u21, &.{ 'S', 'T', 'R', 'A', 'S', 'S', 'E' }, upper_str);

    const final = try lower(allocator, &.{ 0x0391, 0x03A3 });
    defer allocator.free(final);
    try testing.expectEqualSlices(u21, &.{ 0x03B1, 0x03C2 }, final);

    // A lone sigma has no preceding cased letter, so it is not final.
    const lone = try lower(allocator, &.{0x03A3});
    defer allocator.free(lone);
    try testing.expectEqualSlices(u21, &.{0x03C3}, lone);

    // A following cased letter also keeps the ordinary sigma.
    const medial = try lower(allocator, &.{ 0x0391, 0x03A3, 0x0391 });
    defer allocator.free(medial);
    try testing.expectEqualSlices(u21, &.{ 0x03B1, 0x03C3, 0x03B1 }, medial);

    const titled = try title(allocator, &.{ 0x01C6, 'a' });
    defer allocator.free(titled);
    try testing.expectEqualSlices(u21, &.{ 0x01C5, 'A' }, titled);
}

test "case folding" {
    var buf: [3]u21 = undefined;
    try testing.expectEqualSlices(u21, &.{ 's', 's' }, foldFull(0x00DF, &buf));
    try testing.expectEqualSlices(u21, &.{ 's', 's' }, foldFull(0x1E9E, &buf));
    try testing.expectEqualSlices(u21, &.{'a'}, foldFull('A', &buf));
    try testing.expectEqual(@as(u21, 0x00DF), foldSimple(0x00DF));
    try testing.expectEqual(@as(u21, 'a'), foldSimple('A'));

    const allocator = testing.allocator;
    const folded = try fold(allocator, &.{ 'S', 't', 'r', 'a', 0x00DF, 'e' });
    defer allocator.free(folded);
    try testing.expectEqualSlices(u21, &.{ 's', 't', 'r', 'a', 's', 's', 'e' }, folded);
}

test "generated sparse tables are sorted" {
    try expectSortedCcc(&tables.ccc);
    try expectSortedDecompositions(&tables.decompositions);
    try expectSortedCompositions(&tables.compositions);
    try expectSortedBrackets(&tables.brackets);
    try expectSortedMirrors(&tables.mirrors);
}

fn expectSortedCcc(ranges: []const tables.CccRange) !void {
    var previous: u32 = 0;
    for (ranges, 0..) |range, index| {
        try testing.expect(range.start <= range.end);
        try testing.expect(range.ccc != 0);
        if (index > 0) try testing.expect(previous < range.start);
        previous = range.end;
    }
}

fn expectSortedDecompositions(entries: []const tables.Decomposition) !void {
    var previous: u32 = 0;
    for (entries, 0..) |entry, index| {
        try testing.expect(entry.len != 0);
        try testing.expect(@as(usize, entry.offset) + entry.len <= tables.decomposition_values.len);
        if (index > 0) try testing.expect(previous < entry.from);
        previous = entry.from;
    }
}

fn expectSortedCompositions(entries: []const tables.Composition) !void {
    for (entries, 0..) |entry, index| {
        if (index > 0) {
            const previous = entries[index - 1];
            const ordered = previous.first < entry.first or
                (previous.first == entry.first and previous.second < entry.second);
            try testing.expect(ordered);
        }
    }
}

fn expectSortedBrackets(entries: []const tables.Bracket) !void {
    var previous: u32 = 0;
    for (entries, 0..) |entry, index| {
        if (index > 0) try testing.expect(previous < entry.cp);
        previous = entry.cp;
    }
}

fn expectSortedMirrors(entries: []const tables.Mirror) !void {
    var previous: u32 = 0;
    for (entries, 0..) |entry, index| {
        if (index > 0) try testing.expect(previous < entry.from);
        previous = entry.from;
    }
}

test "generated case tables are sorted" {
    try expectMappingStage(tables.fold_simple_stage);
    try expectSortedMulti(&tables.full_upper);
    try expectSortedMulti(&tables.full_lower);
    try expectSortedMulti(&tables.full_title);
    try expectSortedMulti(&tables.final_sigma);
    try expectSortedMulti(&tables.fold_full);
}

fn expectSortedMulti(mappings: []const tables.MultiMapping) !void {
    var previous: u32 = 0;
    for (mappings, 0..) |mapping, index| {
        try testing.expect(mapping.len != 0);
        try testing.expect(mapping.len <= 3);
        if (index > 0) try testing.expect(previous < mapping.from);
        previous = mapping.from;
    }
}
