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
//! Every table comes from `UnicodeData.txt`, `DerivedCoreProperties.txt`, and
//! `PropList.txt` at the release `version` names. `zig build regen` rebuilds
//! `tables.zig` from the UCD release pinned in `build.zig.zon`; nothing in the
//! table is edited by hand.

const std = @import("std");
const tables = @import("tables.zig");

/// The Unicode release the tables come from, such as `"18.0.0"`.
pub const version = tables.version;

/// A Unicode general category, `Lu` through `Cn`.
pub const Category = tables.Category;

/// The highest code point, U+10FFFF.
pub const max_code_point: u21 = 0x10FFFF;

/// The general category of `cp`. A code point with no explicit entry in
/// `UnicodeData.txt` is `.Cn`.
pub fn category(cp: u21) Category {
    var low: usize = 0;
    var high: usize = tables.category_ranges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = tables.category_ranges[mid];
        if (cp < range.start) {
            high = mid;
        } else if (cp > range.end) {
            low = mid + 1;
        } else {
            return range.category;
        }
    }
    return .Cn;
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

/// The White_Space property from `PropList.txt`. It covers ASCII space and
/// tab, the line breaks, the no-break spaces, and the Unicode spaces, and it
/// excludes U+200B.
pub fn isWhiteSpace(cp: u21) bool {
    return inRanges(&tables.white_space, cp);
}

/// UAX #31 `ID_Start`. A language that allows `_` or `$` in a name adds that
/// rule itself, because UAX #31 does not.
pub fn isIdStart(cp: u21) bool {
    return inRanges(&tables.id_start, cp);
}

/// UAX #31 `ID_Continue`.
pub fn isIdContinue(cp: u21) bool {
    return inRanges(&tables.id_continue, cp);
}

/// UAX #31 `XID_Start`, the NFKC-closed form.
pub fn isXidStart(cp: u21) bool {
    return inRanges(&tables.xid_start, cp);
}

/// UAX #31 `XID_Continue`, the NFKC-closed form.
pub fn isXidContinue(cp: u21) bool {
    return inRanges(&tables.xid_continue, cp);
}

/// The simple uppercase mapping from `UnicodeData.txt`, or `cp` when there is
/// none. A full mapping, such as `ß` to `SS`, needs `SpecialCasing.txt` and is
/// not here.
pub fn toUpper(cp: u21) u21 {
    return mapped(&tables.upper, cp);
}

/// The simple lowercase mapping, or `cp` when there is none.
pub fn toLower(cp: u21) u21 {
    return mapped(&tables.lower, cp);
}

/// The simple titlecase mapping, or `cp` when there is none.
pub fn toTitle(cp: u21) u21 {
    return mapped(&tables.title, cp);
}

fn inRanges(ranges: []const tables.Range, cp: u21) bool {
    var low: usize = 0;
    var high: usize = ranges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (cp < ranges[mid].start) {
            high = mid;
        } else if (cp > ranges[mid].end) {
            low = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

fn mapped(mappings: []const tables.Mapping, cp: u21) u21 {
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
            return mapping.to;
        }
    }
    return cp;
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

test "every table is sorted and its bounds agree" {
    try expectSortedCategories(&tables.category_ranges);
    try expectSortedRanges(&tables.white_space);
    try expectSortedRanges(&tables.id_start);
    try expectSortedRanges(&tables.id_continue);
    try expectSortedRanges(&tables.xid_start);
    try expectSortedRanges(&tables.xid_continue);
    try expectSortedMappings(&tables.upper);
    try expectSortedMappings(&tables.lower);
    try expectSortedMappings(&tables.title);
}

fn expectSortedCategories(ranges: []const tables.CategoryRange) !void {
    var previous: u32 = 0;
    for (ranges, 0..) |range, index| {
        try testing.expect(range.start <= range.end);
        if (index > 0) try testing.expect(previous < range.start);
        try testing.expectEqual(range.category, category(range.start));
        try testing.expectEqual(range.category, category(range.end));
        previous = range.end;
    }
}

fn expectSortedRanges(ranges: []const tables.Range) !void {
    var previous: u32 = 0;
    for (ranges, 0..) |range, index| {
        try testing.expect(range.start <= range.end);
        if (index > 0) try testing.expect(previous < range.start);
        previous = range.end;
    }
}

fn expectSortedMappings(mappings: []const tables.Mapping) !void {
    var previous: u32 = 0;
    for (mappings, 0..) |mapping, index| {
        if (index > 0) try testing.expect(previous < mapping.from);
        previous = mapping.from;
    }
}
