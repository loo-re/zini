const std = @import("std");
const zini = @import("zini");
const Parser = zini.Parser;
const Section = zini.Section;
const errors = zini.errors;

pub fn start() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var parser = try Parser.init(allocator);
    defer parser.deinit();
    var args = try std.process.argsWithAllocator(allocator);
    var i: usize = 0;
    while (args.next()) |arg| {
        i += 1;
        if (i == 2) {
            if (checkIfPathExists(arg)) {
                parser.loadFile(arg) catch |e| {
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
                break;
            } else {
                _ = try std.io.getStdErr().write("Config file not found");
                std.process.exit(3);
            }
        }
    }

    const address = try std.net.Address.parseIp4(
        parser.global().getString("host", "127.0.0.1"),
        @intCast(parser.global().getInt("port", 3000)),
    );

    var bind = try address.listen(std.net.Address.ListenOptions{
        .reuse_port = true,
        .reuse_address = true,
    });
    defer bind.deinit();

    _ = try std.io.getStdOut().write(parser.global().getString("banner", "Server started"));
    while (true) {
        handleConnection(&parser, try bind.accept()) catch |err| switch (err) {
            else => {
                std.debug.print("Error {any}", .{err});
                std.process.exit(20);
            },
        };
    }
}

fn handleConnection(parser: *Parser, conn: std.net.Server.Connection) !void {
    defer conn.stream.close();

    var buffer: [1024]u8 = undefined;
    var http_server = std.http.Server.init(conn, &buffer);
    var req = try http_server.receiveHead();

    if (parser.section("url")) |r| {
        if (r.section(req.head.target)) |url| {
            var opt = std.http.Server.Request.RespondOptions{
                .status = .ok,
            };
            var headers = std.ArrayList(std.http.Header).init(std.heap.smp_allocator);
            defer headers.deinit();

            if (url.getOptionalEnum(std.http.Status, "status")) |status| {
                opt.status = status;
            }
            if (url.getOptionalString("statustext")) |reason| {
                opt.reason = reason;
            }

            if (url.getOptionalString("content-type")) |reason| {
                try headers.append(std.http.Header{
                    .name = "Content-Type",
                    .value = reason,
                });
            }

            if (url.section("headers")) |h| {
                var it = h.entryIterator();
                while (it.next()) |header| {
                    headers.append(std.http.Header{
                        .name = header.key_ptr.*,
                        .value = header.value_ptr.*,
                    }) catch |err| switch (err) {
                        else => {
                            std.debug.print("Error {any}", .{err});
                            std.process.exit(21);
                        },
                    };
                }
            }

            if (headers.items.len > 0) {
                if (headers.toOwnedSlice()) |h| {
                    opt.extra_headers = h;
                } else |_| {}
            }

            if (url.getOptionalString("respond")) |respond| {
                try req.respond(respond, opt);
                return;
            } else if (url.getOptionalString("file")) |file_path| {
                try serveFile(&req, "", file_path, .{});
                return;
            }
        }
    }
    // Fichier statique si le chemin commence par "/assets/"
    const public = parser.global().getString("public", "/assets/");
    try serveFile(&req, public, req.head.target, .{});
}

fn serveFile(req: *std.http.Server.Request, root: []const u8, path: []const u8, opt: std.http.Server.Request.RespondOptions) !void {
    const allocator = std.heap.page_allocator;

    var full_path = std.ArrayList(u8).init(allocator);
    defer full_path.deinit();
    try full_path.appendSlice(root);
    if (root.len > 0 and root[root.len - 1] != '/' and (path.len == 0 or path.len > 0 and path[path.len - 1] != '/')) {
        try full_path.append('/');
    }
    try full_path.appendSlice(path);

    var file = std.fs.cwd().openFile(full_path.items, .{}) catch {
        return req.respond("404 - Fichier non trouvé\n", .{});
    };
    defer file.close();

    const stat = try file.stat();
    var buffer: [4096]u8 = undefined;
    var send_buffer: [4096]u8 = undefined;
    var res: std.http.Server.Response = req.respondStreaming(.{
        .content_length = stat.size,
        .respond_options = opt,
        .send_buffer = &send_buffer,
    });

    const reader = file.reader();
    while (true) {
        const bytesRead = try reader.read(&buffer);
        if (bytesRead == 0) break;
        _ = try res.write(buffer[0..bytesRead]);
    }
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
