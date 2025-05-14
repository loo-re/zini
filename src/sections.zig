const std = @import("std");
pub const Parser = @import("./parser.zig").Parser;
pub const utils = @import("./utils.zig");

const mem = std.mem;
const PutFn: type = fn ([]const u8, []const u8) void;
///
/// SECTION
///
pub const Section = struct {
    properties: *std.StringHashMap([]const u8),
    links: *std.StringHashMap([]const u8),
    name: []const u8,
    parser: *const Parser,

    //////////////// PRIVATE

    fn get(self: *const Section, name: []const u8) ?[]const u8 {
        const n = utils.lower(self.parser.allocator, name) catch name;
        if (self.properties.*.get(n)) |value| {
            return value;
        }
        return null;
    }

    //////////////// PUBLIC

    pub fn init(
        parser: *const Parser,
        properties: *std.StringHashMap([]const u8),
        links: *std.StringHashMap([]const u8),
        name: []const u8,
    ) Section {
        return .{
            .name = name,
            .properties = properties,
            .links = links,
            .parser = parser,
        };
    }

    pub fn has(self: *const Section, key: []const u8) bool {
        return self.properties.*.contains(key);
    }

    pub fn sectionsCount(self: *const Section) u32 {
        return self.links.count();
    }

    pub fn hasSection(self: *const Section, name: []const u8) bool {
        if (self.links.getEntry(name)) |l| {
            return self.parser.hasSection(l.value_ptr.*);
        } else {
            return false;
        }
    }
    pub fn section(self: *const Section, name: []const u8) ?Section {
        if (self.links.getEntry(name)) |l| {
            return self.parser.section(l.value_ptr.*);
        } else {
            return null;
        }
    }

    pub fn sectionAt(self: *const Section, index: u32) ?Section {
        if (index > 0 and self.links.count() < index) {
            const it = self.links.iterator();
            var i: u32 = 0;
            while (it.next()) |l| {
                if (i == index) {
                    return self.section(l.value_ptr.*);
                }
                i += 1;
            }
            return null;
        } else {
            return null;
        }
    }
    pub fn sectionIterator(self: *const Section) std.StringHashMap([]const u8).KeyIterator {
        return self.links.*.keyIterator();
    }
    pub fn keyIterator(self: *const Section) std.StringHashMap([]const u8).KeyIterator {
        return self.properties.*.keyIterator();
    }
    pub fn entryIterator(self: *const Section) std.StringHashMap([]const u8).Iterator {
        return self.properties.*.iterator();
    }

    pub fn getString(self: *const Section, name: []const u8, defValue: []const u8) []const u8 {
        return self.getOptionalString(name) orelse defValue;
    }

    pub fn getOptionalString(self: *const Section, name: []const u8) ?[]const u8 {
        return self.get(name);
    }

    pub fn getInt(self: *const Section, name: []const u8, defValue: i64) i64 {
        return self.getOptionalInt(name) orelse defValue;
    }

    pub fn getOptionalInt(self: *const Section, name: []const u8) ?i64 {
        if (self.get(name)) |value_str| {
            return std.fmt.parseInt(i64, value_str, 10) catch null;
        }
        return null;
    }

    pub fn getBool(self: *const Section, name: []const u8, defValue: bool) bool {
        return self.getOptionalBool(name) orelse defValue;
    }

    pub fn getOptionalBool(self: *const Section, name: []const u8) ?bool {
        if (self.get(name)) |value_str| {
            const lower_value_slice = utils.lower(self.parser.allocator, value_str) catch value_str;
            defer self.parser.allocator.free(lower_value_slice);
            if (mem.eql(u8, lower_value_slice, "true") or
                mem.eql(u8, lower_value_slice, "on") or
                mem.eql(u8, lower_value_slice, "enable") or
                mem.eql(u8, lower_value_slice, "enabled") or
                mem.eql(u8, lower_value_slice, "1") or
                mem.eql(u8, lower_value_slice, "y") or
                mem.eql(u8, lower_value_slice, "yes"))
            {
                return true;
            } else if (mem.eql(u8, lower_value_slice, "false") or
                mem.eql(u8, lower_value_slice, "off") or
                mem.eql(u8, lower_value_slice, "disable") or
                mem.eql(u8, lower_value_slice, "disabled") or
                mem.eql(u8, lower_value_slice, "0") or
                mem.eql(u8, lower_value_slice, "n") or
                mem.eql(u8, lower_value_slice, "no"))
            {
                return false;
            }
        }
        return null;
    }

    pub fn getStringList(self: *const Section, name: []const u8, separator: u8, defValue: []const []const u8) []const []const u8 {
        return self.getOptionalStringList(name, separator) orelse {
            var list = std.ArrayList([]const u8).init(self.parser.allocator);
            defer list.deinit();
            list.appendSlice(defValue) catch {};
            return list.toOwnedSlice() catch &.{};
        };
    }

    pub fn getOptionalStringList(self: *const Section, name: []const u8, separator: u8) ?[]const []const u8 {
        if (self.get(name)) |value_str| {
            var list = std.ArrayList([]const u8).init(self.parser.allocator);
            defer list.deinit();
            var it = mem.splitScalar(u8, value_str, separator);
            while (it.next()) |item| {
                list.append(mem.trim(u8, item, " ")) catch {
                    return null;
                };
            }
            return list.toOwnedSlice() catch null;
        }
        return null;
    }

    pub fn getIntList(self: *const Section, name: []const u8, separator: u8, defValue: []const i64) []const i64 {
        return self.getOptionalIntList(name, separator) orelse {
            var list = std.ArrayList(i64).init(self.parser.allocator);
            defer list.deinit();
            list.appendSlice(defValue) catch {};
            return list.toOwnedSlice() catch &.{};
        };
    }

    pub fn getOptionalIntList(self: *const Section, name: []const u8, separator: u8) ?[]const i64 {
        if (self.get(name)) |value_str| {
            var list = std.ArrayList(i64).init(self.parser.allocator);
            defer list.deinit();
            var it = mem.splitScalar(u8, value_str, separator);
            while (it.next()) |item_str| {
                if (std.fmt.parseInt(i64, mem.trim(u8, item_str, " "), 10) catch null) |item_int| {
                    list.append(item_int) catch {};
                }
            }
            return list.toOwnedSlice() catch null;
        }
        return null;
    }

    pub fn getFloat(self: *const Section, name: []const u8, defValue: f64) f64 {
        return self.getOptionalFloat(name) orelse defValue;
    }

    pub fn getOptionalFloat(self: *const Section, name: []const u8) ?f64 {
        if (self.get(name)) |value_str| {
            return std.fmt.parseFloat(f64, value_str) catch null;
        }
        return null;
    }

    pub fn getFloatList(self: *const Section, name: []const u8, separator: u8, defValue: []const f64) []const f64 {
        return self.getOptionalFloatList(name, separator) orelse {
            var list = std.ArrayList(f64).init(self.parser.allocator);
            defer list.deinit();
            list.appendSlice(defValue) catch {};
            return list.toOwnedSlice() catch &.{};
        };
    }

    pub fn getOptionalFloatList(self: *const Section, name: []const u8, separator: u8) ?[]const f64 {
        if (self.get(name)) |value_str| {
            var list = std.ArrayList(f64).init(self.parser.allocator);
            defer list.deinit();
            var it = mem.splitScalar(u8, value_str, separator);
            while (it.next()) |item_str| {
                if (std.fmt.parseFloat(f64, mem.trim(u8, item_str, " ")) catch null) |item_float| {
                    list.append(item_float) catch {};
                }
            }
            return list.toOwnedSlice() catch null;
        }
        return null;
    }
};
