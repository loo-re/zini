const std = @import("std");
const Parser = @import("zini").Parser;
const errors = @import("zini").errors;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = try Parser.init(allocator);
    defer parser.deinit();

    // Load INI text
    const ini_text =
        \\[section]
        \\key = value
        \\multiline_key = "line1 \
        \\                 lin\x0065e2 \
        \\                 line3"
        \\[section sub]
        \\key = sub section
    ;

    parser.loadText(ini_text) catch |e| {
        switch (e) {
            errors.InvalidFormat => {
                std.debug.print("Error InvalidFormat \n[{any}] {s}\n", .{
                    parser.line.number,
                    parser.line.content,
                });
                std.process.exit(2);
            },
            else => {
                std.debug.print("Error {any}\n", .{e});
                std.process.exit(1);
            },
        }
    };

    // Accessing values
    if (parser.section("section")) |section| {
        const value = section.getString("key", "");
        std.debug.print("key: {s}\n", .{value});

        const multiline_value = section.getString("multiline_key", "");
        std.debug.print("multiline_key: {s}\n", .{multiline_value});
        if (section.section("sub")) |sub| {
            const sub_value = sub.getString("key", "");
            std.debug.print("section.sub.key: {s}\n", .{sub_value});
        }
    }
}
