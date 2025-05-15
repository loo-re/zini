const SemanticVersion = @import("std").SemanticVersion;
pub const VERSION = SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 0,
};
pub const Parser = @import("./parser.zig").Parser;
pub const Section = @import("./sections.zig").Section;
pub const utils = @import("./utils.zig");
pub const errors = @import("./errors.zig").Error;
