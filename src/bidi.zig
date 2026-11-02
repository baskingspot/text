//! The Unicode Bidirectional Algorithm from UAX #9.
//!
//! `resolve` runs one paragraph and returns the resolved embedding level of
//! every code point plus the visual order of the characters that survive rule
//! X9. The caller chooses the paragraph direction or asks for the automatic
//! direction from rules P2 and P3.
//!
//! Rules L3 (combining marks) and L4 (mirrored glyphs) belong to rendering.
//! `isMirrored` and `mirror` expose the data L4 needs.

const std = @import("std");
const tables = @import("tables.zig");
const build_options = @import("build_options");

/// The Bidi_Class property.
pub const Class = tables.BidiClass;

/// The paragraph direction.
pub const Direction = enum {
    /// Rules P2 and P3: the first strong character decides.
    auto,
    /// Left-to-right, embedding level 0.
    ltr,
    /// Right-to-left, embedding level 1.
    rtl,
};

/// One resolved paragraph. The caller frees `levels` and `order` with
/// `deinit`.
pub const Resolved = struct {
    /// The paragraph embedding level, 0 or 1.
    paragraph_level: u8,
    /// The resolved level of each input code point. Code points removed by
    /// rule X9 keep the level the explicit phase gave them and are absent
    /// from `order`.
    levels: []u8,
    /// The visual order, left to right, as indexes into the input.
    order: []usize,

    pub fn deinit(self: Resolved, allocator: std.mem.Allocator) void {
        allocator.free(self.levels);
        allocator.free(self.order);
    }
};

const Char = struct {
    cp: u21,
    class: Class,
    original: Class,
    level: u8,
    index: usize,
};

const Run = struct {
    start: usize,
    end: usize,
};

/// The Bidi_Class property of `cp`.
pub fn class(cp: u21) Class {
    var low: usize = 0;
    var high: usize = tables.bidi_ranges.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = tables.bidi_ranges[mid];
        if (cp < range.start) {
            high = mid;
        } else if (cp > range.end) {
            low = mid + 1;
        } else {
            return range.value;
        }
    }

    // Unassigned code points take the @missing default for their range. The
    // first default covers every code point, so skip it and fall back to L.
    low = 1;
    high = tables.bidi_defaults.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = tables.bidi_defaults[mid];
        if (cp < range.start) {
            high = mid;
        } else if (cp > range.end) {
            low = mid + 1;
        } else {
            return range.value;
        }
    }
    return .L;
}

/// The Bidi_Mirrored property. A renderer mirrors the glyph when this is true
/// and the resolved direction is right-to-left.
pub fn isMirrored(cp: u21) bool {
    return inRanges(&tables.bidi_mirrored, cp);
}

/// The mirrored glyph for `cp`, when `BidiMirroring.txt` names one.
pub fn mirror(cp: u21) ?u21 {
    var low: usize = 0;
    var high: usize = tables.mirrors.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const entry = tables.mirrors[mid];
        if (cp < entry.from) {
            high = mid;
        } else if (cp > entry.from) {
            low = mid + 1;
        } else {
            return entry.to;
        }
    }
    return null;
}

/// The paragraph level rules P2 and P3 would pick for `input`.
pub fn paragraphLevel(input: []const u21) u8 {
    var isolate_depth: usize = 0;
    for (input) |cp| {
        switch (class(cp)) {
            .LRI, .RLI, .FSI => isolate_depth += 1,
            .PDI => if (isolate_depth > 0) {
                isolate_depth -= 1;
            },
            .L => if (isolate_depth == 0) return 0,
            .R, .AL => if (isolate_depth == 0) return 1,
            else => {},
        }
    }
    return 0;
}

/// Resolve one paragraph. The caller frees the result with `deinit`.
pub fn resolve(
    allocator: std.mem.Allocator,
    input: []const u21,
    direction: Direction,
) !Resolved {
    const paragraph_level: u8 = switch (direction) {
        .ltr => 0,
        .rtl => 1,
        .auto => paragraphLevel(input),
    };

    const levels = try allocator.alloc(u8, input.len);
    errdefer allocator.free(levels);
    const effective = try allocator.alloc(Class, input.len);
    defer allocator.free(effective);

    // X1-X8: explicit levels, overrides, and isolates.
    const StackEntry = struct { level: u8, isolate: bool, override: ?Class };
    var stack: [126]StackEntry = undefined;
    stack[0] = .{ .level = paragraph_level, .isolate = false, .override = null };
    var stack_top: usize = 0;
    var current_level = paragraph_level;
    var overflow_isolate: u32 = 0;
    var overflow_embedding: u32 = 0;
    var valid_isolate: u32 = 0;
    var override: ?Class = null;

    for (input, 0..) |cp, index| {
        const c = class(cp);
        // X6 applies the override to every type except the formatting
        // characters, B, BN, and PDI. X5a and X5b reset the isolate
        // initiators themselves when an override is active.
        effective[index] = switch (c) {
            .B, .BN, .LRE, .RLE, .LRO, .RLO, .PDF, .PDI => c,
            else => override orelse c,
        };
        switch (c) {
            .RLE, .LRE, .RLO, .LRO => {
                levels[index] = current_level;
                if (stack_top < 125 and overflow_isolate == 0 and overflow_embedding == 0) {
                    const new_level = nextLevel(current_level, c == .RLE or c == .RLO);
                    if (new_level <= 125) {
                        stack_top += 1;
                        stack[stack_top] = .{
                            .level = new_level,
                            .isolate = false,
                            .override = if (c == .RLO) .R else if (c == .LRO) .L else null,
                        };
                        current_level = new_level;
                        override = stack[stack_top].override;
                    } else if (overflow_isolate == 0) {
                        overflow_embedding += 1;
                    }
                } else if (overflow_isolate == 0) {
                    overflow_embedding += 1;
                }
            },
            .RLI, .LRI, .FSI => {
                levels[index] = current_level;
                if (stack_top < 125 and overflow_isolate == 0 and overflow_embedding == 0) {
                    const rtl = switch (c) {
                        .RLI => true,
                        .LRI => false,
                        else => isolateIsRtl(input, index),
                    };
                    const new_level = nextLevel(current_level, rtl);
                    if (new_level <= 125) {
                        stack_top += 1;
                        stack[stack_top] = .{
                            .level = new_level,
                            .isolate = true,
                            .override = null,
                        };
                        current_level = new_level;
                        override = null;
                        valid_isolate += 1;
                    } else {
                        overflow_isolate += 1;
                    }
                } else {
                    overflow_isolate += 1;
                }
            },
            .PDI => {
                if (overflow_isolate > 0) {
                    overflow_isolate -= 1;
                } else if (valid_isolate > 0) {
                    overflow_embedding = 0;
                    while (stack_top > 0 and !stack[stack_top].isolate) stack_top -= 1;
                    if (stack_top > 0) stack_top -= 1;
                    current_level = stack[stack_top].level;
                    override = stack[stack_top].override;
                    valid_isolate -= 1;
                }
                levels[index] = current_level;
            },
            .PDF => {
                levels[index] = current_level;
                if (overflow_isolate > 0) {
                    // An overflow isolate swallows the PDF.
                } else if (overflow_embedding > 0) {
                    overflow_embedding -= 1;
                } else if (stack_top > 0 and !stack[stack_top].isolate) {
                    stack_top -= 1;
                    current_level = stack[stack_top].level;
                    override = stack[stack_top].override;
                }
            },
            .B => {
                levels[index] = paragraph_level;
                stack_top = 0;
                current_level = paragraph_level;
                override = null;
                overflow_isolate = 0;
                overflow_embedding = 0;
                valid_isolate = 0;
            },
            else => levels[index] = current_level,
        }
    }

    // X9: remove the explicit formatting characters from the sequence. Keep
    // their levels for the result, but not for the rules below.
    var kept: std.ArrayList(Char) = .empty;
    defer kept.deinit(allocator);
    for (input, 0..) |cp, index| {
        const c = class(cp);
        if (isRemoved(c)) continue;
        try kept.append(allocator, .{
            .cp = cp,
            .class = effective[index],
            .original = c,
            .level = levels[index],
            .index = index,
        });
    }

    const order = try resolveSequence(allocator, kept.items, levels, paragraph_level);
    errdefer allocator.free(order);

    return .{
        .paragraph_level = paragraph_level,
        .levels = levels,
        .order = order,
    };
}

fn resolveSequence(
    allocator: std.mem.Allocator,
    chars: []const Char,
    levels: []u8,
    paragraph_level: u8,
) ![]usize {
    if (chars.len == 0) return allocator.alloc(usize, 0);

    const matching_pdi = try allocator.alloc(?usize, chars.len);
    defer allocator.free(matching_pdi);
    @memset(matching_pdi, null);
    try matchIsolates(allocator, chars, matching_pdi);

    const runs = try collectRuns(allocator, chars);
    defer allocator.free(runs);

    const run_of = try allocator.alloc(usize, chars.len);
    defer allocator.free(run_of);
    for (runs, 0..) |run, index| {
        for (run.start..run.end) |position| run_of[position] = index;
    }

    const next_run = try allocator.alloc(?usize, runs.len);
    defer allocator.free(next_run);
    @memset(next_run, null);
    const has_previous = try allocator.alloc(bool, runs.len);
    defer allocator.free(has_previous);
    @memset(has_previous, false);

    for (runs, 0..) |run, index| {
        const last = run.end - 1;
        if (!isIsolateInitiator(chars[last].original)) continue;
        const pdi = matching_pdi[last] orelse continue;
        const target = run_of[pdi];
        next_run[index] = target;
        has_previous[target] = true;
    }

    const final_levels = try allocator.alloc(u8, chars.len);
    defer allocator.free(final_levels);
    for (chars, 0..) |char, index| final_levels[index] = char.level;

    var sequence: std.ArrayList(usize) = .empty;
    defer sequence.deinit(allocator);

    for (runs, 0..) |_, run_index| {
        if (has_previous[run_index]) continue;
        sequence.clearRetainingCapacity();
        var current: ?usize = run_index;
        while (current) |index| {
            const run = runs[index];
            for (run.start..run.end) |position| {
                try sequence.append(allocator, position);
            }
            current = next_run[index];
        }
        const last = sequence.items[sequence.items.len - 1];
        const unmatched_isolate = isIsolateInitiator(chars[last].original) and
            matching_pdi[last] == null;
        try processSequence(
            allocator,
            chars,
            sequence.items,
            final_levels,
            paragraph_level,
            unmatched_isolate,
        );
    }

    // L1: reset separators and trailing whitespace to the paragraph level.
    resetWhitespaceLevels(chars, final_levels, paragraph_level);

    // L2: reorder from the highest level down to the lowest odd level.
    const order = try allocator.alloc(usize, chars.len);
    errdefer allocator.free(order);
    for (order, 0..) |*entry, index| entry.* = index;
    reorder(order, final_levels);
    for (order) |*entry| entry.* = chars[entry.*].index;

    for (chars, 0..) |char, index| levels[char.index] = final_levels[index];
    return order;
}

fn matchIsolates(
    allocator: std.mem.Allocator,
    chars: []const Char,
    matching_pdi: []?usize,
) !void {
    var stack: std.ArrayList(usize) = .empty;
    defer stack.deinit(allocator);
    for (chars, 0..) |char, index| {
        if (isIsolateInitiator(char.original)) {
            try stack.append(allocator, index);
        } else if (char.original == .PDI) {
            if (stack.pop()) |initiator| matching_pdi[initiator] = index;
        }
    }
}

fn collectRuns(allocator: std.mem.Allocator, chars: []const Char) ![]Run {
    var runs: std.ArrayList(Run) = .empty;
    defer runs.deinit(allocator);
    var start: usize = 0;
    while (start < chars.len) {
        var end = start + 1;
        while (end < chars.len and chars[end].level == chars[start].level) : (end += 1) {}
        try runs.append(allocator, .{ .start = start, .end = end });
        start = end;
    }
    return runs.toOwnedSlice(allocator);
}

fn processSequence(
    allocator: std.mem.Allocator,
    chars: []const Char,
    sequence: []const usize,
    final_levels: []u8,
    paragraph_level: u8,
    unmatched_isolate: bool,
) !void {
    if (sequence.len == 0) return;

    const level = chars[sequence[0]].level;
    const first = sequence[0];
    const last = sequence[sequence.len - 1];
    const before_level = if (first == 0)
        paragraph_level
    else
        chars[first - 1].level;
    const after_level = if (unmatched_isolate or last + 1 == chars.len)
        paragraph_level
    else
        chars[last + 1].level;
    const sos = typeForLevel(@max(level, before_level));
    const eos = typeForLevel(@max(level, after_level));

    const types = try allocator.alloc(Class, sequence.len);
    defer allocator.free(types);
    for (sequence, types) |position, *value| value.* = chars[position].class;

    resolveWeak(types, sos, eos);
    try resolveBrackets(allocator, types, chars, sequence, sos, level);
    resolveNeutrals(types, sos, eos, level);
    resolveImplicit(types, chars, sequence, level, final_levels);
}

fn resolveWeak(types: []Class, sos: Class, eos: Class) void {
    // W1: NSM takes the type of the previous character, or ON after an
    // isolate initiator or PDI.
    for (types, 0..) |*value, index| {
        if (value.* != .NSM) continue;
        value.* = if (index == 0) sos else switch (types[index - 1]) {
            .LRI, .RLI, .FSI, .PDI => .ON,
            else => types[index - 1],
        };
    }

    // W2: EN becomes AN when the previous strong type is AL.
    var last_strong: Class = sos;
    for (types) |*value| {
        switch (value.*) {
            .L, .R, .AL => last_strong = value.*,
            .EN => if (last_strong == .AL) {
                value.* = .AN;
            },
            else => {},
        }
    }

    // W3: AL becomes R.
    for (types) |*value| {
        if (value.* == .AL) value.* = .R;
    }

    // W4: ES between EN, CS between EN or AN.
    var index: usize = 1;
    while (index + 1 < types.len) : (index += 1) {
        if (types[index] == .ES and types[index - 1] == .EN and types[index + 1] == .EN) {
            types[index] = .EN;
        } else if (types[index] == .CS) {
            if (types[index - 1] == .EN and types[index + 1] == .EN) {
                types[index] = .EN;
            } else if (types[index - 1] == .AN and types[index + 1] == .AN) {
                types[index] = .AN;
            }
        }
    }

    // W5: a run of ET adjacent to EN becomes EN.
    index = 0;
    while (index < types.len) {
        if (types[index] != .ET) {
            index += 1;
            continue;
        }
        var end = index;
        while (end < types.len and types[end] == .ET) : (end += 1) {}
        const before = if (index == 0) sos else types[index - 1];
        const after = if (end == types.len) eos else types[end];
        if (before == .EN or after == .EN) {
            for (types[index..end]) |*value| value.* = .EN;
        }
        index = end;
    }

    // W6: the remaining separators and terminators become ON.
    for (types) |*value| {
        if (value.* == .ET or value.* == .ES or value.* == .CS) value.* = .ON;
    }

    // W7: EN becomes L when the previous strong type is L.
    last_strong = sos;
    for (types) |*value| {
        switch (value.*) {
            .L, .R => last_strong = value.*,
            .EN => if (last_strong == .L) {
                value.* = .L;
            },
            else => {},
        }
    }
}

const BracketPair = struct {
    open: usize,
    close: usize,
};

fn resolveBrackets(
    allocator: std.mem.Allocator,
    types: []Class,
    chars: []const Char,
    sequence: []const usize,
    sos: Class,
    level: u8,
) !void {
    const Open = struct { index: usize, cp: u21 };
    var stack: std.ArrayList(Open) = .empty;
    defer stack.deinit(allocator);
    var pairs: std.ArrayList(BracketPair) = .empty;
    defer pairs.deinit(allocator);

    for (sequence, 0..) |position, index| {
        if (types[index] != .ON) continue;
        const bracket = findBracket(chars[position].cp) orelse continue;
        switch (bracket.kind) {
            .open => {
                if (stack.items.len == 63) {
                    pairs.clearRetainingCapacity();
                    break;
                }
                try stack.append(allocator, .{ .index = index, .cp = chars[position].cp });
            },
            .close => {
                var found: ?usize = null;
                var cursor = stack.items.len;
                while (cursor > 0) {
                    cursor -= 1;
                    const open = stack.items[cursor];
                    if (bracketMatches(open.cp, chars[position].cp)) {
                        found = cursor;
                        break;
                    }
                }
                if (found) |open_index| {
                    const open = stack.items[open_index];
                    try pairs.append(allocator, .{ .open = open.index, .close = index });
                    stack.shrinkRetainingCapacity(open_index);
                }
                // No matching opener: BD16 leaves the stack alone.
            },
        }
    }

    std.mem.sort(BracketPair, pairs.items, {}, lessBracketPair);

    const embedding: Class = if (level % 2 == 0) .L else .R;
    const opposite: Class = if (embedding == .L) .R else .L;

    for (pairs.items) |pair| {
        // N0: inspect the enclosed strong types first. With none enclosed,
        // leave the brackets alone; N1 and N2 resolve them individually.
        const inside = classifyInside(types, pair.open, pair.close, embedding);
        if (inside == null) continue;

        const direction = if (inside.? == embedding)
            embedding
        else if (strongBefore(types, pair.open, sos) == opposite)
            opposite
        else
            embedding;

        types[pair.open] = direction;
        types[pair.close] = direction;
        propagateToMarks(types, chars, sequence, pair.open, direction);
        propagateToMarks(types, chars, sequence, pair.close, direction);
    }
}

fn propagateToMarks(
    types: []Class,
    chars: []const Char,
    sequence: []const usize,
    from: usize,
    direction: Class,
) void {
    var index = from + 1;
    while (index < types.len and chars[sequence[index]].class == .NSM) : (index += 1) {
        types[index] = direction;
    }
}

fn lessBracketPair(_: void, a: BracketPair, b: BracketPair) bool {
    return a.open < b.open;
}

fn strongBefore(types: []const Class, index: usize, sos: Class) Class {
    var position = index;
    while (position > 0) {
        position -= 1;
        switch (types[position]) {
            .L => return .L,
            .R, .EN, .AN => return .R,
            else => {},
        }
    }
    return sos;
}

/// The strong type enclosed by a bracket pair. The embedding direction wins
/// when both directions appear, the opposite direction is returned when that
/// is the only strong type, and null means the pair encloses no strong type.
fn classifyInside(types: []const Class, open: usize, close: usize, embedding: Class) ?Class {
    const opposite: Class = if (embedding == .L) .R else .L;
    var found = false;
    var position = open + 1;
    while (position < close) : (position += 1) {
        const value = switch (types[position]) {
            .L => Class.L,
            .R, .EN, .AN => Class.R,
            else => continue,
        };
        if (value == embedding) return embedding;
        found = true;
    }
    return if (found) opposite else null;
}

fn resolveNeutrals(types: []Class, sos: Class, eos: Class, level: u8) void {
    const embedding: Class = if (level % 2 == 0) .L else .R;
    var index: usize = 0;
    while (index < types.len) {
        if (!isNeutral(types[index])) {
            index += 1;
            continue;
        }
        var end = index;
        while (end < types.len and isNeutral(types[end])) : (end += 1) {}

        const before = if (index == 0) sos else strongForNeutral(types[index - 1]);
        const after = if (end == types.len) eos else strongForNeutral(types[end]);
        const direction = if (before == after) before else embedding;
        for (types[index..end]) |*value| value.* = direction;
        index = end;
    }
}

fn strongForNeutral(value: Class) Class {
    return switch (value) {
        .L => .L,
        .R, .EN, .AN => .R,
        else => .ON,
    };
}

fn resolveImplicit(
    types: []const Class,
    chars: []const Char,
    sequence: []const usize,
    level: u8,
    final_levels: []u8,
) void {
    for (types, sequence) |value, position| {
        var resolved = chars[position].level;
        if (level % 2 == 0) {
            switch (value) {
                .R => resolved += 1,
                .EN, .AN => resolved += 2,
                else => {},
            }
        } else {
            switch (value) {
                .L, .EN, .AN => resolved += 1,
                else => {},
            }
        }
        final_levels[position] = resolved;
    }
}

fn resetWhitespaceLevels(
    chars: []const Char,
    final_levels: []u8,
    paragraph_level: u8,
) void {
    for (chars, 0..) |char, index| {
        if (char.original != .B and char.original != .S) continue;
        final_levels[index] = paragraph_level;
        var previous = index;
        while (previous > 0 and isLineWhitespace(chars[previous - 1].original)) {
            previous -= 1;
            final_levels[previous] = paragraph_level;
        }
    }

    var trailing = chars.len;
    while (trailing > 0 and isLineWhitespace(chars[trailing - 1].original)) {
        trailing -= 1;
        final_levels[trailing] = paragraph_level;
    }
}

fn reorder(order: []usize, levels: []const u8) void {
    if (order.len == 0) return;
    var highest: u8 = 0;
    var lowest: u8 = 255;
    for (levels) |level| {
        highest = @max(highest, level);
        lowest = @min(lowest, level);
    }
    const lowest_odd = if (lowest % 2 == 0) lowest + 1 else lowest;

    var level = highest;
    while (level >= lowest_odd and level > 0) : (level -= 1) {
        var index: usize = 0;
        while (index < order.len) {
            if (levels[order[index]] < level) {
                index += 1;
                continue;
            }
            var end = index;
            while (end < order.len and levels[order[end]] >= level) : (end += 1) {}
            std.mem.reverse(usize, order[index..end]);
            index = end;
        }
    }
}

fn nextLevel(level: u8, rtl: bool) u8 {
    if (rtl) return if (level % 2 == 1) level + 2 else level + 1;
    return if (level % 2 == 0) level + 2 else level + 1;
}

fn typeForLevel(level: u8) Class {
    return if (level % 2 == 0) .L else .R;
}

fn isolateIsRtl(input: []const u21, fsi_index: usize) bool {
    var depth: usize = 1;
    var index = fsi_index + 1;
    while (index < input.len) : (index += 1) {
        switch (class(input[index])) {
            .LRI, .RLI, .FSI => depth += 1,
            .PDI => {
                depth -= 1;
                if (depth == 0) return false;
            },
            .L => if (depth == 1) return false,
            .R, .AL => if (depth == 1) return true,
            else => {},
        }
    }
    return false;
}

fn isRemoved(value: Class) bool {
    return switch (value) {
        .RLE, .LRE, .RLO, .LRO, .PDF, .BN => true,
        else => false,
    };
}

fn isIsolateInitiator(value: Class) bool {
    return value == .LRI or value == .RLI or value == .FSI;
}

fn isNeutral(value: Class) bool {
    return switch (value) {
        .B, .S, .WS, .ON, .LRI, .RLI, .FSI, .PDI => true,
        else => false,
    };
}

fn isLineWhitespace(value: Class) bool {
    return switch (value) {
        .WS, .B, .S, .LRI, .RLI, .FSI, .PDI => true,
        else => false,
    };
}

fn findBracket(cp: u21) ?tables.Bracket {
    var low: usize = 0;
    var high: usize = tables.brackets.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const entry = tables.brackets[mid];
        if (cp < entry.cp) {
            high = mid;
        } else if (cp > entry.cp) {
            low = mid + 1;
        } else {
            return entry;
        }
    }
    return null;
}

fn bracketMatches(open: u21, close: u21) bool {
    const bracket = findBracket(open) orelse return false;
    return canonicalBracket(bracket.pair) == canonicalBracket(close);
}

/// U+2329 and U+232A are canonically equivalent to U+3008 and U+3009.
fn canonicalBracket(cp: u21) u21 {
    return switch (cp) {
        0x2329 => 0x3008,
        0x232A => 0x3009,
        else => cp,
    };
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

test "paragraph direction" {
    try testing.expectEqual(@as(u8, 0), paragraphLevel(&.{'a'}));
    try testing.expectEqual(@as(u8, 1), paragraphLevel(&.{0x05D0}));
    try testing.expectEqual(@as(u8, 0), paragraphLevel(&.{ 0x2067, 0x05D0, 0x2069 }));
}

test "a right-to-left paragraph reverses" {
    const resolved = try resolve(testing.allocator, &.{ 0x05D0, 0x05D1 }, .auto);
    defer resolved.deinit(testing.allocator);
    try testing.expectEqual(@as(u8, 1), resolved.paragraph_level);
    try testing.expectEqualSlices(u8, &.{ 1, 1 }, resolved.levels);
    try testing.expectEqualSlices(usize, &.{ 1, 0 }, resolved.order);
}

test "numbers in a right-to-left paragraph take two levels" {
    const resolved = try resolve(testing.allocator, &.{ 0x05D0, '1', '2' }, .rtl);
    defer resolved.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 2 }, resolved.levels);
    try testing.expectEqualSlices(usize, &.{ 1, 2, 0 }, resolved.order);
}

test "an isolate keeps its own direction" {
    const input = [_]u21{ 'a', 0x2067, 0x05D0, 0x2069, 'b' };
    const resolved = try resolve(testing.allocator, &input, .ltr);
    defer resolved.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 1, 0, 0 }, resolved.levels);
    try testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4 }, resolved.order);
}

test "mirrored glyphs" {
    try testing.expect(isMirrored('('));
    try testing.expectEqual(@as(?u21, ')'), mirror('('));
    try testing.expectEqual(@as(?u21, null), mirror('a'));
}

test "BidiTest.txt" {
    const directory = build_options.conformance_dir;
    if (directory.len == 0) return error.SkipZigTest;

    const allocator = testing.allocator;
    const path = try std.Io.Dir.path.join(allocator, &.{ directory, "BidiTest.txt" });
    defer allocator.free(path);
    const data = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        path,
        allocator,
        .limited(64 << 20),
    );
    defer allocator.free(data);

    var expected_levels = try allocator.alloc(?u8, 0);
    defer allocator.free(expected_levels);
    var expected_order = try allocator.alloc(usize, 0);
    defer allocator.free(expected_order);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "@Levels:")) {
            allocator.free(expected_levels);
            expected_levels = try parseLevelList(allocator, line["@Levels:".len..]);
            continue;
        }
        if (std.mem.startsWith(u8, line, "@Reorder:")) {
            allocator.free(expected_order);
            expected_order = try parseOrder(allocator, line["@Reorder:".len..]);
            continue;
        }
        if (line[0] == '#') continue;
        if (line[0] == '@') continue;

        const comment = std.mem.findScalar(u8, line, '#') orelse line.len;
        const body = std.mem.trim(u8, line[0..comment], " \t");
        const semicolon = std.mem.findScalar(u8, body, ';') orelse continue;
        const bitset = try std.fmt.parseInt(
            u8,
            std.mem.trim(u8, body[semicolon + 1 ..], " \t"),
            16,
        );

        var code_points: std.ArrayList(u21) = .empty;
        defer code_points.deinit(allocator);
        var names = std.mem.tokenizeAny(u8, body[0..semicolon], " \t");
        while (names.next()) |name| {
            try code_points.append(allocator, representative(name) orelse {
                std.debug.print("unknown class {s}\n", .{name});
                return error.TestUnexpectedResult;
            });
        }

        const direction_bits = [_]struct { bit: u8, direction: Direction }{
            .{ .bit = 1, .direction = .auto },
            .{ .bit = 2, .direction = .ltr },
            .{ .bit = 4, .direction = .rtl },
        };
        for (direction_bits) |entry| {
            if (bitset & entry.bit == 0) continue;
            const resolved = try resolve(allocator, code_points.items, entry.direction);
            defer resolved.deinit(allocator);
            expectLevels(expected_levels, resolved.levels) catch {
                std.debug.print("BidiTest levels: {s}; {any} expected {any} got {any}\n", .{
                    body[0..semicolon], code_points.items, expected_levels, resolved.levels,
                });
                return error.TestUnexpectedResult;
            };
            testing.expectEqualSlices(usize, expected_order, resolved.order) catch {
                std.debug.print("BidiTest order: {s}; {any} expected {any} got {any}\n", .{
                    body[0..semicolon], code_points.items, expected_order, resolved.order,
                });
                return error.TestUnexpectedResult;
            };
        }
    }
}

test "BidiCharacterTest.txt" {
    const directory = build_options.conformance_dir;
    if (directory.len == 0) return error.SkipZigTest;

    const allocator = testing.allocator;
    const path = try std.Io.Dir.path.join(allocator, &.{ directory, "BidiCharacterTest.txt" });
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
        if (line.len == 0 or line[0] == '#') continue;

        var fields: [5][]const u8 = @splat("");
        var parts = std.mem.splitScalar(u8, line, ';');
        var count: usize = 0;
        while (parts.next()) |part| {
            if (count == fields.len) break;
            fields[count] = std.mem.trim(u8, part, " \t");
            count += 1;
        }
        if (count < 5) continue;

        var code_points: std.ArrayList(u21) = .empty;
        defer code_points.deinit(allocator);
        var numbers = std.mem.tokenizeAny(u8, fields[0], " \t");
        while (numbers.next()) |number| {
            try code_points.append(allocator, try std.fmt.parseInt(u21, number, 16));
        }

        const direction = switch (try std.fmt.parseInt(u8, fields[1], 10)) {
            0 => Direction.ltr,
            1 => Direction.rtl,
            2 => Direction.auto,
            else => return error.TestUnexpectedResult,
        };
        const paragraph_level = try std.fmt.parseInt(u8, fields[2], 10);
        const expected_levels = try parseLevelList(allocator, fields[3]);
        defer allocator.free(expected_levels);
        const expected_order = try parseOrder(allocator, fields[4]);
        defer allocator.free(expected_order);

        const resolved = try resolve(allocator, code_points.items, direction);
        defer resolved.deinit(allocator);
        testing.expectEqual(paragraph_level, resolved.paragraph_level) catch {
            std.debug.print("BidiCharacter paragraph: {s} expected {d} got {d}\n", .{
                line, paragraph_level, resolved.paragraph_level,
            });
            return error.TestUnexpectedResult;
        };
        expectLevels(expected_levels, resolved.levels) catch {
            std.debug.print("BidiCharacter levels: {s} expected {any} got {any}\n", .{
                line, expected_levels, resolved.levels,
            });
            return error.TestUnexpectedResult;
        };
        testing.expectEqualSlices(usize, expected_order, resolved.order) catch {
            std.debug.print("BidiCharacter order: {s} expected {any} got {any}\n", .{
                line, expected_order, resolved.order,
            });
            return error.TestUnexpectedResult;
        };
    }
}

fn parseLevelList(allocator: std.mem.Allocator, text: []const u8) ![]?u8 {
    var levels: std.ArrayList(?u8) = .empty;
    errdefer levels.deinit(allocator);
    var tokens = std.mem.tokenizeAny(u8, text, " \t\r");
    while (tokens.next()) |token| {
        if (std.mem.eql(u8, token, "x")) {
            try levels.append(allocator, null);
        } else {
            try levels.append(allocator, try std.fmt.parseInt(u8, token, 10));
        }
    }
    return levels.toOwnedSlice(allocator);
}

fn parseOrder(allocator: std.mem.Allocator, text: []const u8) ![]usize {
    var order: std.ArrayList(usize) = .empty;
    errdefer order.deinit(allocator);
    var tokens = std.mem.tokenizeAny(u8, text, " \t\r");
    while (tokens.next()) |token| {
        try order.append(allocator, try std.fmt.parseInt(usize, token, 10));
    }
    return order.toOwnedSlice(allocator);
}

fn expectLevels(expected: []const ?u8, actual: []const u8) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |wanted, got| {
        if (wanted) |value| try testing.expectEqual(value, got);
    }
}

fn representative(name: []const u8) ?u21 {
    const entries = [_]struct { name: []const u8, cp: u21 }{
        .{ .name = "L", .cp = 'a' },
        .{ .name = "R", .cp = 0x05D0 },
        .{ .name = "AL", .cp = 0x0627 },
        .{ .name = "EN", .cp = '0' },
        .{ .name = "ES", .cp = '+' },
        .{ .name = "ET", .cp = '#' },
        .{ .name = "AN", .cp = 0x0660 },
        .{ .name = "CS", .cp = ',' },
        .{ .name = "NSM", .cp = 0x0300 },
        .{ .name = "BN", .cp = 0x00AD },
        .{ .name = "B", .cp = 0x2029 },
        .{ .name = "S", .cp = 0x0009 },
        .{ .name = "WS", .cp = ' ' },
        .{ .name = "ON", .cp = '!' },
        .{ .name = "LRE", .cp = 0x202A },
        .{ .name = "LRO", .cp = 0x202D },
        .{ .name = "RLE", .cp = 0x202B },
        .{ .name = "RLO", .cp = 0x202E },
        .{ .name = "PDF", .cp = 0x202C },
        .{ .name = "LRI", .cp = 0x2066 },
        .{ .name = "RLI", .cp = 0x2067 },
        .{ .name = "FSI", .cp = 0x2068 },
        .{ .name = "PDI", .cp = 0x2069 },
    };
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry.cp;
    }
    return null;
}
