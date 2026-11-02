//! Text primitives in Zig.
//!
//! `unicode` holds the character data: general categories, UAX #31
//! identifiers, white space, and the simple case mappings. Every table comes
//! from the Unicode Character Database at the release `unicode.version`
//! names.

const std = @import("std");
const testing = std.testing;

pub const unicode = @import("unicode.zig");

test {
    testing.refAllDecls(@This());
}
