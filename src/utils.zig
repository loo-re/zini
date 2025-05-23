const OutOfMemory = @import("./errors.zig").Error.OutOfMemory;
const std = @import("std");
/// Résout un chemin relatif ou absolu par rapport à un chemin de base.
/// Si `base_path` est un fichier, le chemin de base est son répertoire.
/// Si `base_path` est un répertoire, il est utilisé tel quel.
/// `target_path` peut être relatif ou absolu.
/// Retourne le chemin combiné et normalisé.
pub fn resolvePath(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    target_path: []const u8,
) ![]u8 {
    // Si le chemin cible est absolu, le normaliser directement.
    if (std.fs.path.isAbsolute(target_path)) {
        return std.fs.path.resolve(allocator, &.{target_path});
    }

    // Déterminer le répertoire de base.
    const base_dir = if (std.fs.path.isAbsolute(base_path)) base_path else try std.fs.path.resolve(allocator, &.{base_path});

    // Si `base_path` est un fichier, obtenir son répertoire.
    const base_is_dir = std.fs.path.isSep(base_path[base_path.len - 1]);
    const base_dir_path = if (base_is_dir)
        base_dir
    else
        std.fs.path.dirname(base_dir) orelse ".";

    // Combiner et normaliser les chemins.
    return std.fs.path.resolve(allocator, &.{ base_dir_path, target_path });
}
pub inline fn lower(
    value: []const u8,
) ![]const u8 {
    if (value.len > 4096) {
        return OutOfMemory;
    }
    var dst: [4096]u8 = undefined;
    for (value[0..value.len], 0..) |c, i| {
        dst[i] = std.ascii.toLower(c);
        //if (c >= 'A' and c <= 'Z') c + 32 else c;
    }
    return dst[0..value.len];
}
pub inline fn getEnum(comptime T: type, name: []const u8) ?T {
    const info = @typeInfo(T);
    switch (info) {
        .@"enum" => |enum_info| {
            inline for (enum_info.fields) |field| {
                if (eq(lower(name) catch name, lower(field.name[0..]) catch field.name[0..]) catch false) {
                    return @field(T, field.name);
                }
            }
        },
        else => {
            return null;
        },
    }
    return null;
}
pub inline fn eq(
    a: []const u8,
    b: []const u8,
) !bool {
    if (a.len > 4096 or b.len > 4096) {
        return OutOfMemory;
    }

    if (a.len != b.len) {
        return false;
    }
    for (a[0..a.len], 0..) |c, i| {
        if (c != b[i]) {
            return false;
        }
    }
    return true;
}
// **caractères spéciaux d’échappement** et leur représentation en **hexadécimal `0xXX` (u8)**
// | Zig escape | Caractère | Hex (u8) | Description               |
// | ---------- | --------- | -------- | ------------------------- |
// | `\0`       | NUL       | `0x00`   | Null character            |
// | `\a`       | BEL       | `0x07`   | Bell/alert (audible)      |
// | `\b`       | BS        | `0x08`   | Backspace                 |
// | `\t`       | TAB       | `0x09`   | Horizontal tab            |
// | `\r`       | CR        | `0x0D`   | Carriage return           |
// | `\n`       | LF        | `0x0A`   | Line feed (new line)      |
// | `\\`       | `\`       | `0x5C`   | Antislash (backslash)     |
// | `\'`       | `'`       | `0x27`   | Apostrophe (single quote) |
// | `\"`       | `"`       | `0x22`   | Double quote              |
// | `\;`       | `;`       | `0x3B`   | Point-virgule             |
// | `\#`       | `#`       | `0x23`   | Dièse / hash              |
// | `\=`       | `=`       | `0x3D`   | Signe égal                |
// | `\:`       | `:`       | `0x3A`   | Deux-points               |
// | `\xHHHH`   | 0xHHHH    | `0xHHHH` | UTF-8 Code point          |

pub inline fn escape(input: []const u8) !struct {
    value: []const u8,
    skip: usize,
} {
    if (input.len > 6) {
        return OutOfMemory;
    }
    const i: usize = 0;
    const b = input[i];

    return switch (b) {
        '0' => .{ .value = "\x00", .skip = 2 },
        'a' => .{ .value = "\x07", .skip = 2 },
        'b' => .{ .value = "\x08", .skip = 2 },
        't' => .{ .value = "\x09", .skip = 2 },
        'r' => .{ .value = "\x0D", .skip = 2 },
        'n' => .{ .value = "\x0A", .skip = 2 },
        '\\' => .{ .value = "\\", .skip = 2 },
        '"' => .{ .value = "\"", .skip = 2 },
        '\'' => .{ .value = "\'", .skip = 2 },
        'x' => blk: {
            // On attend 4 caractères hexadécimaux après '\x'
            if (i + 4 >= input.len) break :blk .{ .value = "", .skip = 2 };

            const hex = input[i + 1 .. i + 5];

            const cp = std.fmt.parseInt(u21, hex, 16) catch break :blk .{ .value = "", .skip = 2 };

            if (!std.unicode.utf8ValidCodepoint(cp))
                break :blk .{ .value = "", .skip = 2 };

            // encode en UTF-8
            var buffer: [2]u8 = .{ 0, 0 };
            const length: usize = @intCast(try std.unicode.utf8Encode(cp, &buffer));

            const copy = try std.heap.page_allocator.alloc(u8, length);
            std.mem.copyBackwards(u8, copy, buffer[0..length]);
            break :blk .{ .value = copy, .skip = 6 };
        },
        else => .{ .value = input[i .. i + 1], .skip = 2 },
    };
}

pub fn removeQuote(value: []const u8) ![]const u8 {
    var clean_value = std.mem.trim(u8, value, " \t");
    if (clean_value.len > 1 and clean_value[0] == '"' and clean_value[clean_value.len - 1] == '"') {
        clean_value = clean_value[1 .. clean_value.len - 1];
    }
    return clean_value;
}
pub fn unescapeChars(value: []const u8) ![]const u8 {
    const allocator = std.heap.page_allocator;
    var unescaped_value = std.ArrayList(u8).init(allocator);
    defer unescaped_value.deinit();

    const copy = try allocator.alloc(u8, value.len);
    std.mem.copyBackwards(u8, copy, value);
    var i: usize = 0;
    while (i < copy.len) {
        if (copy[i] == '\\' and i + 1 < copy.len) {
            const escaped = try escape(copy[i + 1 .. if (copy.len > i + 6) i + 6 else copy.len]);
            try unescaped_value.appendSlice(escaped.value);
            i += escaped.skip; // Skip the escape character and the quote
        } else {
            try unescaped_value.append(value[i]);
            i += 1;
        }
    }

    // // Allouer et copier
    const value_copy = try allocator.alloc(u8, unescaped_value.items.len);
    std.mem.copyBackwards(u8, value_copy, unescaped_value.items);
    return value_copy;
}
