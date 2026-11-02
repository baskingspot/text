//! Benchmarks for text. Run with `just bench` (ReleaseFast).
//!
//! Property lookups run over a deterministic sample of code points from the
//! whole range. Segmentation, normalization, casing, and bidi run over the
//! same mixed UTF-8 corpus compiled into this file.
//!
//! Output is the testingx benchmark format, so `benchstat` compares runs.

const std = @import("std");
const testingx = @import("testingx");
const text = @import("text");

pub fn benchmarkMain(b: *testingx.B) !void {
    try b.add("Unicode/Category", benchmarkCategory);
    try b.add("Unicode/Script", benchmarkScript);
    try b.add("Unicode/Block", benchmarkBlock);
    try b.add("Unicode/ToUpper", benchmarkToUpper);
    try b.add("Unicode/Combined", benchmarkCombined);
    try b.add("Segment/Graphemes", benchmarkGraphemes);
    try b.add("Segment/Words", benchmarkWords);
    try b.add("Segment/Sentences", benchmarkSentences);
    try b.add("Normalize/NFC", benchmarkNfc);
    try b.add("Normalize/NFD", benchmarkNfd);
    try b.add("Normalize/NFKC", benchmarkNfkc);
    try b.add("Case/Upper", benchmarkUpper);
    try b.add("Case/Lower", benchmarkLower);
    try b.add("Case/Fold", benchmarkFold);
    try b.add("Bidi/Resolve", benchmarkBidi);
}

const samples_len = 64 * 1024;

const mixed_utf8 =
    "The quick brown fox jumps over the lazy dog. 0123456789\n" ++
    "Grüße, façade, naïve, coöperate.\n" ++
    "Σίσυφος ἔπεα, Ἀθῆναι, ΐ.\n" ++
    "Кириллица, ёжик, Щука.\n" ++
    "مرحبا بالعالم، العربية.\n" ++
    "שלום עולם, עברית.\n" ++
    "क्षत्रिय, कर्म, हिन्दी.\n" ++
    "한글, 조선어, 서울.\n" ++
    "漢字, 日本語, 中文.\n" ++
    "👩🏽‍🚀🇨🇭👨🏻‍🍼🏳️‍🌈\n";

fn sampleCodePoints(allocator: std.mem.Allocator) ![]u21 {
    const code_points = try allocator.alloc(u21, samples_len);
    var index: usize = 0;
    var cp: u21 = 0;
    while (index < code_points.len) : (index += 1) {
        code_points[index] = cp;
        cp = @intCast((@as(u32, cp) + 0x9E37) % 0x110000);
    }
    return code_points;
}

fn decode(allocator: std.mem.Allocator, bytes: []const u8) ![]u21 {
    var out: std.ArrayList(u21) = .empty;
    errdefer out.deinit(allocator);
    var iterator: std.unicode.Utf8Iterator = .{ .bytes = bytes, .i = 0 };
    while (iterator.nextCodepoint()) |cp| {
        try out.append(allocator, cp);
    }
    return out.toOwnedSlice(allocator);
}

fn mixedCorpus(allocator: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var index: usize = 0;
    while (index < 256) : (index += 1) {
        try out.appendSlice(allocator, mixed_utf8);
    }
    return out.toOwnedSlice(allocator);
}

fn benchmarkCategory(b: *testingx.B) !void {
    const code_points = try sampleCodePoints(b.allocator);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        for (code_points) |cp| sink +%= @backingInt(text.unicode.category(cp));
    }
}

fn benchmarkScript(b: *testingx.B) !void {
    const code_points = try sampleCodePoints(b.allocator);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        for (code_points) |cp| sink +%= @backingInt(text.unicode.script(cp));
    }
}

fn benchmarkBlock(b: *testingx.B) !void {
    const code_points = try sampleCodePoints(b.allocator);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        for (code_points) |cp| sink +%= @backingInt(text.unicode.block(cp));
    }
}

fn benchmarkToUpper(b: *testingx.B) !void {
    const code_points = try sampleCodePoints(b.allocator);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        for (code_points) |cp| sink +%= text.unicode.toUpper(cp);
    }
}

fn benchmarkCombined(b: *testingx.B) !void {
    const code_points = try sampleCodePoints(b.allocator);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        for (code_points) |cp| {
            sink +%= @backingInt(text.unicode.category(cp));
            sink +%= @backingInt(text.unicode.script(cp));
            sink +%= @backingInt(text.unicode.block(cp));
            sink +%= text.unicode.toUpper(cp);
        }
    }
}

fn benchmarkGraphemes(b: *testingx.B) !void {
    const bytes = try mixedCorpus(b.allocator);
    defer b.allocator.free(bytes);
    const code_points = try decode(b.allocator, bytes);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(bytes.len));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        var iterator = text.segment.graphemes(code_points);
        while (iterator.next()) |cluster| sink +%= cluster.len;
    }
}

fn benchmarkWords(b: *testingx.B) !void {
    const bytes = try mixedCorpus(b.allocator);
    defer b.allocator.free(bytes);
    const code_points = try decode(b.allocator, bytes);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(bytes.len));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        var iterator = text.segment.words(code_points);
        while (iterator.next()) |word| sink +%= word.len;
    }
}

fn benchmarkSentences(b: *testingx.B) !void {
    const bytes = try mixedCorpus(b.allocator);
    defer b.allocator.free(bytes);
    const code_points = try decode(b.allocator, bytes);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(bytes.len));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        var iterator = text.segment.sentences(code_points);
        while (iterator.next()) |sentence| sink +%= sentence.len;
    }
}

const normalization_corpus =
    "A\u{030A} \u{00C5} café naïve ﬁ ǆ ẛ ﬃ \u{212B} \u{1E0A} \u{1E0C}" ++
    " \u{AC01} \u{D55C} \u{1100}\u{1161}\u{11A8}" ++
    " \u{03D3} \u{03D4} \u{1F82} \u{FDFA}";

fn normalizationCodePoints(b: *testingx.B) ![]u21 {
    const bytes = try mixedCorpus(b.allocator);
    defer b.allocator.free(bytes);
    const mixed = try decode(b.allocator, bytes);
    defer b.allocator.free(mixed);
    const extra = try decode(b.allocator, normalization_corpus);
    defer b.allocator.free(extra);

    const all = try b.allocator.alloc(u21, mixed.len + extra.len);
    @memcpy(all[0..mixed.len], mixed);
    @memcpy(all[mixed.len..], extra);
    return all;
}

fn benchmarkNfc(b: *testingx.B) !void {
    const code_points = try normalizationCodePoints(b);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        const normalized = try text.normalize.normalize(b.allocator, .nfc, code_points);
        defer b.allocator.free(normalized);
        sink +%= normalized.len;
    }
}

fn benchmarkNfd(b: *testingx.B) !void {
    const code_points = try normalizationCodePoints(b);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        const normalized = try text.normalize.normalize(b.allocator, .nfd, code_points);
        defer b.allocator.free(normalized);
        sink +%= normalized.len;
    }
}

fn benchmarkNfkc(b: *testingx.B) !void {
    const code_points = try normalizationCodePoints(b);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        const normalized = try text.normalize.normalize(b.allocator, .nfkc, code_points);
        defer b.allocator.free(normalized);
        sink +%= normalized.len;
    }
}

fn caseCorpus(b: *testingx.B) ![]u21 {
    return decode(b.allocator, "Straße GROSSẞ İIıi Σίσυφος ОН она ǅ ǆ Ǆ");
}

fn benchmarkUpper(b: *testingx.B) !void {
    const code_points = try caseCorpus(b);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        const mapped = try text.unicode.upper(b.allocator, code_points);
        defer b.allocator.free(mapped);
        sink +%= mapped.len;
    }
}

fn benchmarkLower(b: *testingx.B) !void {
    const code_points = try caseCorpus(b);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        const mapped = try text.unicode.lower(b.allocator, code_points);
        defer b.allocator.free(mapped);
        sink +%= mapped.len;
    }
}

fn benchmarkFold(b: *testingx.B) !void {
    const code_points = try caseCorpus(b);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        const mapped = try text.unicode.fold(b.allocator, code_points);
        defer b.allocator.free(mapped);
        sink +%= mapped.len;
    }
}

const bidi_text =
    "Hello עולם, هذا نص عربي، and a little more English. " ++
    "אבגד (efgh) [ijkl] مرحبا 1234. " ++
    "👩🏽‍🚀 mixed with 👨🏻‍🍼 and more.";

fn benchmarkBidi(b: *testingx.B) !void {
    const code_points = try decode(b.allocator, bidi_text);
    defer b.allocator.free(code_points);
    b.setBytes(@intCast(code_points.len * @sizeOf(u21)));

    var sink: usize = 0;
    defer b.keepAlive(sink);
    while (try b.loop()) {
        const resolved = try text.bidi.resolve(b.allocator, code_points, .auto);
        defer resolved.deinit(b.allocator);
        sink +%= resolved.order.len;
    }
}
