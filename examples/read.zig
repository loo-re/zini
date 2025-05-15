const std = @import("std");
const zini = @import("zini");
const Parser = zini.Parser;
const errors = zini.errors;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = try Parser.init(allocator);
    defer parser.deinit();
    var query: struct {
        data: []const u8,
        file: []const u8,
        isFile: bool,
        hasData: bool,
        section: []const u8,
        key: []const u8,
    } = .{ .hasData = false, .isFile = false, .file = "", .data = "", .section = "", .key = "" };

    const stdin = std.io.getStdIn().reader();
    var buffer: [4096]u8 = undefined;
    var read: u32 = 0;
    const is_pipe = !std.io.getStdIn().isTty();
    while (is_pipe and true) {
        const bytes_read = try stdin.read(&buffer);
        if (bytes_read < 1) break; // EOF
        read += @intCast(bytes_read);
    }
    if (read > 0) {
        query.hasData = true;
        query.data = buffer[0..read];
    }
    var args = try std.process.argsWithAllocator(allocator);
    var i: usize = 0;
    var j: usize = 0;
    while (args.next()) |arg| {
        i += 1;
        if (i == 2) {
            if (checkIfPathExists(arg)) {
                query.file = arg;
                query.isFile = true;
            } else {
                j += 1;
                query.section = arg;
                query.key = arg;
            }
        } else if (i == 3) {
            if (!query.isFile and checkIfPathExists(arg)) {
                query.file = arg;
                query.isFile = true;
            } else {
                j += 1;
                query.section = arg;
                if (j == 1) {
                    query.key = arg;
                }
            }
        } else if (i == 4) {
            if (!query.isFile and checkIfPathExists(arg)) {
                query.file = arg;
                query.isFile = true;
            } else {
                query.section = arg;
            }
        }
    }
    if (j == 1) {
        query.section = "";
    }
    if (query.hasData) {
        parser.loadText(query.data) catch |e| {
            switch (e) {
                errors.InvalidFormat => {
                    const message_line = try std.fmt.allocPrint(std.heap.page_allocator, "Error InvalidFormat \n[{any}] {s}\n", .{ parser.line.number, parser.line.content });
                    defer std.heap.page_allocator.free(message_line);
                    _ = try std.io.getStdErr().write(message_line);
                    std.process.exit(2);
                },
                else => {
                    const message_line = try std.fmt.allocPrint(std.heap.page_allocator, "Error {any}\n", .{e});
                    defer std.heap.page_allocator.free(message_line);
                    _ = try std.io.getStdErr().write(message_line);
                    std.process.exit(1);
                },
            }
        };
    }
    // // Chargement du fichier
    if (query.isFile) {
        parser.loadFile(query.file) catch |e| {
            switch (e) {
                errors.InvalidFormat => {
                    const message_line = try std.fmt.allocPrint(std.heap.page_allocator, "Error InvalidFormat \n[{any}] {s}\n", .{ parser.line.number, parser.line.content });
                    defer std.heap.page_allocator.free(message_line);
                    _ = try std.io.getStdErr().write(message_line);
                    std.process.exit(2);
                },
                else => {
                    const message_line = try std.fmt.allocPrint(std.heap.page_allocator, "Error {any}\n", .{e});
                    defer std.heap.page_allocator.free(message_line);
                    _ = try std.io.getStdErr().write(message_line);
                    std.process.exit(1);
                },
            }
        };
    }

    // // Ou charger depuis un fichier :
    // // try parser.loadFile("config.ini");

    // // Accès aux données :
    // std.debug.print("# SECTION GLOBALE\n", .{});
    // const port = parser.global().getIntList("port", ',', &.{@as(i64, 80)});
    // const host = parser.global().getString("host", "127.0.0.1");
    // std.debug.print("PORT: {any}\n", .{port});
    // std.debug.print("HOST: {s}\n", .{host});
    // if (parser.global().getBool("debug", false)) {
    //     std.debug.print("DEBUG: actif\n", .{});
    // } else {
    //     std.debug.print("DEBUG: innactif\n", .{});
    // }

    // if (parser.section("section")) |section| {
    //     std.debug.print("\n[SECTION]\n", .{});
    //     if (section.getBool("debug", false)) {
    //         std.debug.print("DEBUG: actif\n", .{});
    //     } else {
    //         std.debug.print("DEBUG: innactif\n", .{});
    //     }
    // }
    // // Accès aux sous section données
    // if (parser.section("page")) |route| {
    //     std.debug.print("\n[page notFound]\n", .{});
    //     if (route.section("notFound")) |notFound| {
    //         std.debug.print("file = {s}\n", .{notFound.getString("file", "404.html")});
    //     }
    // }
    // // Accès aux sous sections
    // if (parser.section("route")) |route| {
    //     std.debug.print("\n[route]\n", .{});
    //     var sections_name_it = route.sectionIterator();
    //     while (sections_name_it.next()) |section_name| {
    //         if (route.section(section_name.*)) |url| {
    //             std.debug.print("  {s}\n", .{section_name.*});
    //             std.debug.print("    sous section = {any}\n", .{url.sectionsCount()});
    //             std.debug.print("    file = {s}\n", .{url.getString("file", "404.html")});
    //         }
    //     }
    // }
    // // acces direct a une sous section
    if (parser.section(query.section)) |route| {
        // Accès aux sous section données
        if (route.getOptionalString(query.key)) |value| {
            std.debug.print("{s}\n", .{value});
            std.process.exit(0);
            return;
        }

        std.debug.print("entry.notFound `{s}`\n", .{query.key});
        std.process.exit(4);
        return;
    }
    std.debug.print("section.notFound `{s}`\n", .{query.section});
    std.process.exit(3);
}

fn checkIfPathExists(path: []const u8) bool {
    const fs = std.fs.cwd();
    const file = fs.openFile(path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return false,
    };
    defer file.close();
    return true;
}
