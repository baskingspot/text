//! Unicode text segmentation from UAX #29.
//!
//! `isGraphemeBoundary`, `isWordBoundary`, and `isSentenceBoundary` answer
//! whether a boundary falls before `input[index]`. The iterators
//! `graphemes`, `words`, and `sentences` walk the same boundaries and return
//! slices of the input.
//!
//! The properties come from `auxiliary/GraphemeBreakProperty.txt`,
//! `auxiliary/WordBreakProperty.txt`, `auxiliary/SentenceBreakProperty.txt`,
//! `emoji/emoji-data.txt`, and the `InCB` property in
//! `DerivedCoreProperties.txt`.

const std = @import("std");
const tables = @import("tables.zig");
const build_options = @import("build_options");

/// The Grapheme_Cluster_Break property.
pub const GraphemeBreak = tables.GraphemeBreak;
/// The Word_Break property.
pub const WordBreak = tables.WordBreak;
/// The Sentence_Break property.
pub const SentenceBreak = tables.SentenceBreak;
/// The Indic_Conjunct_Break property.
pub const InCb = tables.InCb;

/// The Grapheme_Cluster_Break property of `cp`.
pub fn graphemeBreak(cp: u21) GraphemeBreak {
    return tagged(GraphemeBreak, &tables.grapheme_ranges, cp, .Other);
}

/// The Word_Break property of `cp`.
pub fn wordBreak(cp: u21) WordBreak {
    return tagged(WordBreak, &tables.word_ranges, cp, .Other);
}

/// The Sentence_Break property of `cp`.
pub fn sentenceBreak(cp: u21) SentenceBreak {
    return tagged(SentenceBreak, &tables.sentence_ranges, cp, .Other);
}

/// The Indic_Conjunct_Break property of `cp`.
pub fn indicConjunctBreak(cp: u21) InCb {
    return tagged(InCb, &tables.incb_ranges, cp, .None);
}

/// True when `cp` has the Extended_Pictographic property.
pub fn isExtendedPictographic(cp: u21) bool {
    return inRanges(&tables.extended_pictographic, cp);
}

/// True when there is a grapheme cluster boundary before `input[index]`.
/// Index 0 and `input.len` are boundaries.
pub fn isGraphemeBoundary(input: []const u21, index: usize) bool {
    if (index == 0 or index >= input.len) return true;

    const previous = input[index - 1];
    const next = input[index];
    const previous_class = graphemeBreak(previous);
    const next_class = graphemeBreak(next);

    // GB3
    if (previous_class == .CR and next_class == .LF) return false;
    // GB4, GB5
    if (isGraphemeControl(previous_class) or isGraphemeControl(next_class)) return true;
    // GB6
    if (previous_class == .L and
        (next_class == .L or next_class == .V or next_class == .LV or next_class == .LVT))
    {
        return false;
    }
    // GB7
    if ((previous_class == .LV or previous_class == .V) and
        (next_class == .V or next_class == .T))
    {
        return false;
    }
    // GB8
    if ((previous_class == .LVT or previous_class == .T) and next_class == .T) {
        return false;
    }
    // GB9, GB9a
    if (next_class == .Extend or next_class == .ZWJ or next_class == .SpacingMark) {
        return false;
    }
    // GB9b
    if (previous_class == .Prepend) return false;
    // GB9c
    if (indicConjunctBreak(next) == .Consonant) {
        if (isIndicConjunctBoundary(input, index)) return false;
    }
    // GB11
    if (isExtendedPictographic(next) and isEmojiSequenceBoundary(input, index)) {
        return false;
    }
    // GB12, GB13
    if (previous_class == .Regional_Indicator and next_class == .Regional_Indicator) {
        if (countRegionalIndicators(input, index) % 2 == 1) return false;
    }
    // GB999
    return true;
}

/// True when there is a word boundary before `input[index]`.
pub fn isWordBoundary(input: []const u21, index: usize) bool {
    if (index == 0 or index >= input.len) return true;

    const previous_raw = wordBreak(input[index - 1]);
    const next_raw = wordBreak(input[index]);

    // WB3
    if (previous_raw == .CR and next_raw == .LF) return false;
    // WB3a, WB3b
    if (isWordNewline(previous_raw) or isWordNewline(next_raw)) return true;
    // WB3c
    if (previous_raw == .ZWJ and isExtendedPictographic(input[index])) return false;
    // WB3d uses the characters on each side of the boundary, before WB4
    // ignores anything.
    if (previous_raw == .WSegSpace and next_raw == .WSegSpace) return false;
    // WB4
    if (next_raw == .Extend or next_raw == .Format or next_raw == .ZWJ) return false;

    const previous_index = previousSignificant(input, index) orelse return true;
    const next_index = index;
    const previous_class = wordBreak(input[previous_index]);
    const next_class = wordBreak(input[next_index]);

    // WB5
    if (isAhLetter(previous_class) and isAhLetter(next_class)) return false;
    // WB6
    if (isAhLetter(previous_class) and isMidLetterQ(next_class)) {
        if (nextSignificant(input, next_index + 1)) |after| {
            if (isAhLetter(wordBreak(input[after]))) return false;
        }
    }
    // WB7
    if (isMidLetterQ(previous_class) and isAhLetter(next_class)) {
        const before = previousSignificant(input, previous_index) orelse return true;
        if (isAhLetter(wordBreak(input[before]))) return false;
    }
    // WB7a
    if (previous_class == .Hebrew_Letter and next_class == .Single_Quote) return false;
    // WB7b
    if (previous_class == .Hebrew_Letter and next_class == .Double_Quote) {
        if (nextSignificant(input, next_index + 1)) |after| {
            if (wordBreak(input[after]) == .Hebrew_Letter) return false;
        }
    }
    // WB7c
    if (previous_class == .Double_Quote and next_class == .Hebrew_Letter) {
        const before = previousSignificant(input, previous_index) orelse return true;
        if (wordBreak(input[before]) == .Hebrew_Letter) return false;
    }
    // WB8
    if (previous_class == .Numeric and next_class == .Numeric) return false;
    // WB9
    if (isAhLetter(previous_class) and next_class == .Numeric) return false;
    // WB10
    if (previous_class == .Numeric and isAhLetter(next_class)) return false;
    // WB11
    if (isMidNumQ(previous_class) and next_class == .Numeric) {
        const before = previousSignificant(input, previous_index) orelse return true;
        if (wordBreak(input[before]) == .Numeric) return false;
    }
    // WB12
    if (previous_class == .Numeric and isMidNumQ(next_class)) {
        if (nextSignificant(input, next_index + 1)) |after| {
            if (wordBreak(input[after]) == .Numeric) return false;
        }
    }
    // WB13
    if (previous_class == .Katakana and next_class == .Katakana) return false;
    // WB13a
    if (isWordExtendNumLetBase(previous_class) and next_class == .ExtendNumLet) {
        return false;
    }
    // WB13b
    if (previous_class == .ExtendNumLet and isExtendNumLetBase(next_class)) {
        return false;
    }
    // WB15, WB16
    if (previous_class == .Regional_Indicator and next_class == .Regional_Indicator) {
        if (countWordRegionalIndicators(input, previous_index) % 2 == 1) return false;
    }
    // WB999
    return true;
}

/// True when there is a sentence boundary before `input[index]`.
pub fn isSentenceBoundary(input: []const u21, index: usize) bool {
    if (index == 0 or index >= input.len) return true;

    const previous_raw = sentenceBreak(input[index - 1]);
    const next_raw = sentenceBreak(input[index]);

    // SB3
    if (previous_raw == .CR and next_raw == .LF) return false;
    // SB4
    if (isParagraphSeparator(previous_raw)) return true;
    // SB5
    if (next_raw == .Extend or next_raw == .Format) return false;

    const previous_index = previousSentenceSignificant(input, index) orelse return false;
    const next_index = index;
    const previous_class = sentenceBreak(input[previous_index]);
    const next_class = sentenceBreak(input[next_index]);

    // SB6
    if (previous_class == .ATerm and next_class == .Numeric) return false;
    // SB7
    if (previous_class == .ATerm and next_class == .Upper) {
        const before = previousSentenceSignificant(input, previous_index) orelse return true;
        const before_class = sentenceBreak(input[before]);
        if (before_class == .Upper or before_class == .Lower) return false;
    }

    const context = terminatorContext(input, index);
    // SB8
    if (context) |term| {
        if (term.term == .ATerm and sentenceContinuesLower(input, next_index)) {
            return false;
        }
    }
    // SB8a
    if (context != null) {
        if (next_class == .SContinue or next_class == .STerm or next_class == .ATerm) {
            return false;
        }
    }
    // SB9
    if (context) |term| {
        if (!term.spaces and isSentenceCloseOrSp(next_class)) return false;
    }
    // SB10
    if (context != null and isSentenceSpOrPara(next_class)) return false;
    // SB11
    if (context != null) return true;
    // SB998
    return false;
}

/// Iterates grapheme clusters.
pub const Graphemes = struct {
    input: []const u21,
    index: usize = 0,

    pub fn next(self: *Graphemes) ?[]const u21 {
        if (self.index >= self.input.len) return null;
        const start = self.index;
        var end = start + 1;
        while (end < self.input.len and !isGraphemeBoundary(self.input, end)) : (end += 1) {}
        self.index = end;
        return self.input[start..end];
    }
};

/// Iterates words, as UAX #29 defines them, not whitespace-separated words.
pub const Words = struct {
    input: []const u21,
    index: usize = 0,

    pub fn next(self: *Words) ?[]const u21 {
        if (self.index >= self.input.len) return null;
        const start = self.index;
        var end = start + 1;
        while (end < self.input.len and !isWordBoundary(self.input, end)) : (end += 1) {}
        self.index = end;
        return self.input[start..end];
    }
};

/// Iterates sentences.
pub const Sentences = struct {
    input: []const u21,
    index: usize = 0,

    pub fn next(self: *Sentences) ?[]const u21 {
        if (self.index >= self.input.len) return null;
        const start = self.index;
        var end = start + 1;
        while (end < self.input.len and !isSentenceBoundary(self.input, end)) : (end += 1) {}
        self.index = end;
        return self.input[start..end];
    }
};

pub fn graphemes(input: []const u21) Graphemes {
    return .{ .input = input };
}

pub fn words(input: []const u21) Words {
    return .{ .input = input };
}

pub fn sentences(input: []const u21) Sentences {
    return .{ .input = input };
}

fn isGraphemeControl(value: GraphemeBreak) bool {
    return value == .Control or value == .CR or value == .LF;
}

/// GB9c: Linker Extend* × Consonant.
fn isIndicConjunctBoundary(input: []const u21, index: usize) bool {
    var position = index;
    while (position > 0) {
        position -= 1;
        switch (indicConjunctBreak(input[position])) {
            .Linker => return true,
            .Extend => {},
            else => return false,
        }
    }
    return false;
}

/// GB11: Extended_Pictographic Extend* ZWJ × Extended_Pictographic.
fn isEmojiSequenceBoundary(input: []const u21, index: usize) bool {
    if (index == 0) return false;
    if (graphemeBreak(input[index - 1]) != .ZWJ) return false;

    var position = index - 1;
    while (position > 0) {
        position -= 1;
        if (graphemeBreak(input[position]) == .Extend) continue;
        return isExtendedPictographic(input[position]);
    }
    return false;
}

fn countRegionalIndicators(input: []const u21, index: usize) usize {
    var count: usize = 0;
    var position = index;
    while (position > 0) {
        position -= 1;
        if (graphemeBreak(input[position]) != .Regional_Indicator) break;
        count += 1;
    }
    return count;
}

fn isWordNewline(value: WordBreak) bool {
    return value == .CR or value == .LF or value == .Newline;
}

fn isWordIgnorable(value: WordBreak) bool {
    return value == .Extend or value == .Format or value == .ZWJ;
}

fn isAhLetter(value: WordBreak) bool {
    return value == .ALetter or value == .Hebrew_Letter;
}

fn isMidLetterQ(value: WordBreak) bool {
    return value == .MidLetter or value == .MidNumLet or value == .Single_Quote;
}

fn isMidNumQ(value: WordBreak) bool {
    return value == .MidNum or value == .MidNumLet or value == .Single_Quote;
}

fn isWordExtendNumLetBase(value: WordBreak) bool {
    return isAhLetter(value) or value == .Numeric or value == .Katakana or
        value == .ExtendNumLet;
}

fn isExtendNumLetBase(value: WordBreak) bool {
    return isAhLetter(value) or value == .Numeric or value == .Katakana;
}

fn countWordRegionalIndicators(input: []const u21, previous_index: usize) usize {
    var count: usize = 0;
    var position = previous_index;
    while (true) {
        count += 1;
        const before = previousSignificant(input, position) orelse break;
        if (wordBreak(input[before]) != .Regional_Indicator) break;
        position = before;
    }
    return count;
}

fn isParagraphSeparator(value: SentenceBreak) bool {
    return value == .Sep or value == .CR or value == .LF;
}

fn isSentenceCloseOrSp(value: SentenceBreak) bool {
    return value == .Close or value == .Sp or value == .Sep or value == .CR or value == .LF;
}

fn isSentenceSpOrPara(value: SentenceBreak) bool {
    return value == .Sp or value == .Sep or value == .CR or value == .LF;
}

const TerminatorContext = struct {
    term: SentenceBreak,
    spaces: bool,
};

/// Matches `(STerm | ATerm) Close* Sp*` before `index`.
fn terminatorContext(input: []const u21, index: usize) ?TerminatorContext {
    var position = index;
    var spaces = false;

    while (previousSentenceSignificant(input, position)) |previous| {
        if (sentenceBreak(input[previous]) != .Sp) break;
        spaces = true;
        position = previous;
    }
    while (previousSentenceSignificant(input, position)) |previous| {
        if (sentenceBreak(input[previous]) != .Close) break;
        position = previous;
    }
    const terminator = previousSentenceSignificant(input, position) orelse return null;
    const value = sentenceBreak(input[terminator]);
    if (value != .ATerm and value != .STerm) return null;
    return .{ .term = value, .spaces = spaces };
}

/// SB8 lookahead: `(not (OLetter | Upper | Lower | Sep | CR | LF | STerm |
/// ATerm))* Lower`.
fn sentenceContinuesLower(input: []const u21, from: usize) bool {
    var position = from;
    while (nextSentenceSignificant(input, position)) |next| {
        switch (sentenceBreak(input[next])) {
            .Lower => return true,
            .OLetter, .Upper, .Sep, .CR, .LF, .STerm, .ATerm => return false,
            else => position = next + 1,
        }
    }
    return false;
}

fn previousSignificant(input: []const u21, index: usize) ?usize {
    var position = index;
    while (position > 0) {
        position -= 1;
        const value = wordBreak(input[position]);
        if (isWordIgnorable(value)) continue;
        return position;
    }
    return null;
}

fn nextSignificant(input: []const u21, from: usize) ?usize {
    var position = from;
    while (position < input.len) : (position += 1) {
        const value = wordBreak(input[position]);
        if (isWordIgnorable(value)) continue;
        return position;
    }
    return null;
}

fn isSentenceIgnorable(value: SentenceBreak) bool {
    return value == .Extend or value == .Format;
}

fn previousSentenceSignificant(input: []const u21, index: usize) ?usize {
    var position = index;
    while (position > 0) {
        position -= 1;
        const value = sentenceBreak(input[position]);
        if (isSentenceIgnorable(value)) continue;
        return position;
    }
    return null;
}

fn nextSentenceSignificant(input: []const u21, from: usize) ?usize {
    var position = from;
    while (position < input.len) : (position += 1) {
        const value = sentenceBreak(input[position]);
        if (isSentenceIgnorable(value)) continue;
        return position;
    }
    return null;
}

fn tagged(
    comptime T: type,
    ranges: []const tables.TaggedRange(T),
    cp: u21,
    default: T,
) T {
    var low: usize = 0;
    var high: usize = ranges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = ranges[mid];
        if (cp < range.start) {
            high = mid;
        } else if (cp > range.end) {
            low = mid + 1;
        } else {
            return range.value;
        }
    }
    return default;
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

const testing = std.testing;

test "grapheme clusters" {
    var iterator = graphemes(&.{ 'a', 0x0301, 'b' });
    try testing.expectEqualSlices(u21, &.{ 'a', 0x0301 }, iterator.next().?);
    try testing.expectEqualSlices(u21, &.{'b'}, iterator.next().?);
    try testing.expectEqual(@as(?[]const u21, null), iterator.next());
}

test "emoji ZWJ sequence stays together" {
    const input = [_]u21{ 0x1F469, 0x200D, 0x1F4BB };
    try testing.expect(!isGraphemeBoundary(&input, 1));
    try testing.expect(!isGraphemeBoundary(&input, 2));
    var iterator = graphemes(&input);
    try testing.expectEqualSlices(u21, &input, iterator.next().?);
}

test "regional indicators pair" {
    const input = [_]u21{ 0x1F1FA, 0x1F1F8 };
    try testing.expect(!isGraphemeBoundary(&input, 1));
}

test "words" {
    var iterator = words(&.{ 'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd' });
    try testing.expectEqualSlices(u21, &.{ 'h', 'e', 'l', 'l', 'o' }, iterator.next().?);
    try testing.expectEqualSlices(u21, &.{' '}, iterator.next().?);
    try testing.expectEqualSlices(u21, &.{ 'w', 'o', 'r', 'l', 'd' }, iterator.next().?);
}

test "sentences" {
    var iterator = sentences(&.{ 'O', 'n', 'e', '.', ' ', 'T', 'w', 'o', '.' });
    try testing.expectEqualSlices(u21, &.{ 'O', 'n', 'e', '.', ' ' }, iterator.next().?);
    try testing.expectEqualSlices(u21, &.{ 'T', 'w', 'o', '.' }, iterator.next().?);
}

test "GraphemeBreakTest.txt" {
    try runBreakTest("GraphemeBreakTest.txt", .grapheme);
}

test "WordBreakTest.txt" {
    try runBreakTest("WordBreakTest.txt", .word);
}

test "SentenceBreakTest.txt" {
    try runBreakTest("SentenceBreakTest.txt", .sentence);
}

const BreakKind = enum { grapheme, word, sentence };

const BreakCase = struct {
    code_points: []u21,
    boundaries: []bool,
};

fn runBreakTest(name: []const u8, kind: BreakKind) !void {
    const directory = build_options.conformance_dir;
    if (directory.len == 0) return error.SkipZigTest;

    const allocator = testing.allocator;
    const path = try std.Io.Dir.path.join(allocator, &.{ directory, "auxiliary", name });
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
        const parsed = try parseBreakLine(allocator, line[0..comment]);
        defer allocator.free(parsed.code_points);
        defer allocator.free(parsed.boundaries);

        for (parsed.boundaries, 0..) |expected, index| {
            const actual = switch (kind) {
                .grapheme => isGraphemeBoundary(parsed.code_points, index),
                .word => isWordBoundary(parsed.code_points, index),
                .sentence => isSentenceBoundary(parsed.code_points, index),
            };
            if (expected != actual) {
                std.debug.print(
                    "{s}: boundary {d} expected {} got {} in {any}\n",
                    .{ name, index, expected, actual, parsed.code_points },
                );
                return error.TestUnexpectedResult;
            }
        }
    }
}

fn parseBreakLine(allocator: std.mem.Allocator, text: []const u8) !BreakCase {
    var code_points: std.ArrayList(u21) = .empty;
    errdefer code_points.deinit(allocator);
    var boundaries: std.ArrayList(bool) = .empty;
    errdefer boundaries.deinit(allocator);

    var boundary = true;
    var tokens = std.mem.tokenizeAny(u8, text, " \t");
    while (tokens.next()) |token| {
        if (std.mem.eql(u8, token, "\u{00F7}")) {
            boundary = true;
        } else if (std.mem.eql(u8, token, "\u{00D7}")) {
            boundary = false;
        } else {
            const cp = try std.fmt.parseInt(u21, token, 16);
            try code_points.append(allocator, cp);
            try boundaries.append(allocator, boundary);
        }
    }
    // The trailing marker is the boundary after the last code point.
    try boundaries.append(allocator, true);

    return .{
        .code_points = try code_points.toOwnedSlice(allocator),
        .boundaries = try boundaries.toOwnedSlice(allocator),
    };
}
