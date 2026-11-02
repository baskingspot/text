//! Text primitives in Zig.
//!
//! `unicode` holds the character data: general categories, scripts, blocks,
//! UAX #31 identifiers, white space, and case mapping. `normalize` implements
//! the four normalization forms, `segment` implements UAX #29 grapheme, word,
//! and sentence boundaries, and `bidi` implements UAX #9. Every table comes
//! from the Unicode Character Database at the release `unicode.version` names.

const std = @import("std");
const testing = std.testing;

pub const unicode = @import("unicode.zig");
pub const normalize = @import("normalize.zig");
pub const segment = @import("segment.zig");
pub const bidi = @import("bidi.zig");

test {
    testing.refAllDecls(@This());
}
