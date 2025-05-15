const Section = @import("./sections.zig").Section;
const utils = @import("./utils.zig");
const errors = @import("./errors.zig").Error;
const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const HashMap = std.StringHashMap;
const ascii = std.ascii;
///
/// PARSER
///
pub const Parser = struct {
    allocator: mem.Allocator,
    mutex: std.Thread.Mutex,
    cursor: usize,
    current_line: usize,
    eof: bool,
    properties: std.StringHashMap(std.StringHashMap([]const u8)),
    links: std.StringHashMap(std.StringHashMap([]const u8)),
    enable_include: bool,
    line: struct {
        number: usize,
        content: []const u8,
    },

    pub fn init(allocator: mem.Allocator) !Parser {
        var self = Parser{
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
            .cursor = 0,
            .current_line = 1,
            .eof = false,
            .line = .{ .number = 0, .content = "" },
            .links = std.StringHashMap(std.StringHashMap([]const u8)).init(allocator),
            .properties = std.StringHashMap(std.StringHashMap([]const u8)).init(allocator),
            .enable_include = true,
        };
        // init global section
        _ = self.addSection("") catch |e| {
            return e;
        };
        return self;
    }

    pub fn deinit(self: *Parser) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        var sections = self.properties.iterator();
        while (sections.next()) |entry| {
            var it = entry.value_ptr.*.iterator();
            while (it.next()) |e| {
                std.heap.page_allocator.free(e.key_ptr.*);
                std.heap.page_allocator.free(e.value_ptr.*);
            }
            entry.value_ptr.*.deinit();
            std.heap.page_allocator.free(entry.key_ptr.*);
        }
        self.properties.deinit();

        var links = self.links.iterator();
        while (links.next()) |entry| {
            var it = entry.value_ptr.*.iterator();
            while (it.next()) |e| {
                std.heap.page_allocator.free(e.key_ptr.*);
                std.heap.page_allocator.free(e.value_ptr.*);
            }
            entry.value_ptr.*.deinit();
            std.heap.page_allocator.free(entry.key_ptr.*);
        }
        self.links.deinit();
    }

    pub fn loadText(self: *Parser, text: []const u8) !void {
        self.enable_include = false; // Disable include processing
        defer {
            self.enable_include = true; // Re-enable for potential subsequent file loads
        }
        if (self.allocator.dupe(u8, text)) |c| {
            defer self.allocator.free(c);
            try self.parseContent(c);
        } else |_| {}
    }

    pub fn toString(self: *Parser) []const u8 {
        var builder = std.ArrayList(u8).init(self.allocator);
        defer builder.deinit();
        var iterator = (&self.properties).iterator();
        while (iterator.next()) |parent| {
            var it = parent.value_ptr.iterator();
            const sec = parent.key_ptr.*;
            if (sec.len > 0) {
                builder.append('[') catch {};
                builder.appendSlice(sec) catch {};
                builder.append(']') catch {};
                builder.append('\n') catch {};
            }
            while (it.next()) |entry| {
                // builder.appendSlice(if (sec.len > 0) "  " else "") catch {};
                builder.appendSlice(entry.key_ptr.*) catch {};
                builder.appendSlice(" = ") catch {};
                builder.appendSlice(entry.value_ptr.*) catch {};
                builder.append('\n') catch {};
            }
        }
        return builder.toOwnedSlice() catch "";
    }

    pub fn loadFile(self: *Parser, filePath: []const u8) !void {
        self.mutex.lock();
        var unlock = true;
        defer {
            if (unlock) {
                self.mutex.unlock();
            }
        }
        const content = try self.processIncludes(filePath);
        defer self.allocator.free(content);
        self.cursor = 0;
        self.current_line = 1;
        self.eof = false;
        unlock = false;
        self.mutex.unlock();
        try self.parseContent(content);
    }
    fn processIncludes(self: *Parser, filePath: []const u8) ![]const u8 {
        const includesFiles: *const std.StringHashMap(bool) = &std.StringHashMap(bool).init(self.allocator);
        defer @constCast(includesFiles).deinit();
        return try self.readFileAndProcessIncludes(filePath, @constCast(includesFiles));
    }

    fn readFileAndProcessIncludes(
        self: *Parser,
        filePath: []const u8,
        includedFiles: *std.StringHashMap(bool),
    ) ![]const u8 {
        const currentData: *std.ArrayList(u8) = @constCast(&std.ArrayList(u8).init(self.allocator));
        defer currentData.deinit();
        const current_file_path = try fs.cwd().realpathAlloc(self.allocator, filePath);
        defer self.allocator.free(current_file_path);
        const file = fs.cwd().openFile(filePath, .{ .mode = .read_only }) catch |err| {
            return err;
        };
        if (!self.enable_include) {
            defer file.close();
            const a = try file.reader().readAllAlloc(self.allocator, std.math.maxInt(usize));
            const _copy = try self.allocator.alloc(u8, a.len);
            std.mem.copyBackwards(u8, _copy, a);
            try currentData.appendSlice(a);
            return currentData.toOwnedSlice();
        }
        if (includedFiles.contains(filePath)) {
            return errors.CircularInclude;
        }
        try includedFiles.put(filePath, true);
        defer file.close();
        const reader = file.reader();
        var buffer: [4096]u8 = undefined;
        while (true) {
            var bytesRead = try reader.read(&buffer);
            if (bytesRead == 0) break;
            if (bytesRead < 4096) {
                buffer[bytesRead] = '\n';
                bytesRead += 1;
            }
            var start: usize = 0;
            for (buffer[0..bytesRead], 0..) |byte, i| {
                if (byte == '\n') {
                    const line = buffer[start..i];
                    const trimmedLine = mem.trim(u8, line, " \t");
                    const lowerTrimmedLine = utils.lower(trimmedLine) catch unreachable;
                    if (mem.startsWith(u8, lowerTrimmedLine, "include ")) {
                        var content_end_index: usize = trimmedLine.len;
                        for (trimmedLine, 0..) |c, _i| {
                            if ((c == ';' or c == '#') and (_i > 0 and trimmedLine[_i - 1] != '\\')) {
                                content_end_index = _i;
                                break;
                            }
                        }

                        const includePathWithWhitespace = try utils.unescapeChars(trimmedLine["include ".len..content_end_index]);

                        const trimmedIncludePath = mem.trim(u8, includePathWithWhitespace, " \t\"");
                        const resolvedPath = try utils.resolvePath(self.allocator, current_file_path, trimmedIncludePath);

                        const a = try self.readFileAndProcessIncludes(
                            resolvedPath,
                            includedFiles,
                        );
                        const _copy = try self.allocator.alloc(u8, a.len);
                        std.mem.copyBackwards(u8, _copy, a);
                        try currentData.appendSlice(a);
                    } else {
                        // if (combinedContent != null) {
                        // Allouer et copier la clé
                        const _copy = try self.allocator.alloc(u8, line.len);
                        std.mem.copyBackwards(u8, _copy, line);
                        try currentData.appendSlice(_copy);
                        try currentData.append('\n');

                        // }
                    }
                    start = i + 1;
                }
            }
            if (start < bytesRead) {
                // if (combinedContent != null) {
                const _copy = try self.allocator.alloc(u8, bytesRead - start);
                std.mem.copyBackwards(u8, _copy, buffer[start..bytesRead]);
                try currentData.appendSlice(_copy);
                // }
            }
        }
        _ = includedFiles.remove(filePath);
        return currentData.toOwnedSlice();
    }

    fn resolvePath(self: *Parser, basePath: []const u8, includePath: []const u8) ![]const u8 {
        if (mem.startsWith(u8, includePath, "/")) {
            return self.allocator.dupe(u8, includePath);
        } else {
            const baseDirEnd = mem.lastIndexOf(u8, basePath, "/") orelse 0;
            const baseDir = basePath[0..baseDirEnd];
            const resolvedPath = try self.allocator.alloc(u8, baseDir.len + 1 + includePath.len);
            defer self.allocator.free(resolvedPath);
            mem.copyBackwards(u8, resolvedPath[0..baseDir.len], baseDir);
            resolvedPath[baseDir.len] = '/';
            mem.copyBackwards(u8, resolvedPath[baseDir.len + 1 ..], includePath);
            return resolvedPath[0 .. baseDir.len + 1 + includePath.len];
        }
    }
    fn parseContent(self: *Parser, content: []const u8) !void {
        var current_section_name: []const u8 = "";
        var cursor: usize = 0;
        var line_start: usize = 0;
        var line_number: usize = 1;
        self.line = .{ .number = 0, .content = "" };
        var current_content = try std.ArrayList(u8).initCapacity(self.allocator, content.len + 1);
        defer current_content.deinit();
        try current_content.appendSlice(content);
        try current_content.append('\n');

        while (cursor < current_content.items.len) {
            const char = current_content.items[cursor];
            cursor += 1;
            if (char == '\n') {
                const line = current_content.items[line_start..cursor];
                var trimmedLine = mem.trim(u8, line, " \t\r\n");
                const trimmedLine_copy = try std.heap.page_allocator.alloc(u8, trimmedLine.len);
                std.mem.copyBackwards(u8, trimmedLine_copy, trimmedLine);

                self.line = .{ .number = line_number, .content = trimmedLine_copy };
                if (trimmedLine.len == 0) {
                    line_start = cursor;
                    line_number += 1;
                    continue;
                }

                // Remove comments
                var comment_index: ?usize = null;
                if (mem.indexOfScalar(u8, trimmedLine, ';')) |index| {
                    comment_index = index;
                } else if (mem.indexOfScalar(u8, trimmedLine, '#')) |index| {
                    comment_index = index;
                }
                if (comment_index != null) {
                    var content_end_index: ?usize = null;
                    var in_quotes: bool = false;
                    var has_value: bool = false;
                    for (trimmedLine, 0..) |c, i| {
                        if (i > 0 and c == '=') {
                            has_value = true;
                        } else if (has_value and c == '"') {
                            in_quotes = !in_quotes; // Toggle in_quotes state
                        } else if (!in_quotes and (c == ';' or c == '#')) {
                            content_end_index = i;
                            break;
                        }
                    }
                    comment_index = content_end_index;
                }

                const line_without_comment = if (comment_index) |index| trimmedLine[0..index] else trimmedLine;
                trimmedLine = mem.trim(u8, line_without_comment, "\t\r\n");
                const fullTrimmedLine = mem.trim(u8, line_without_comment, " \t\r\n");
                var names = try std.ArrayList([]const u8).initCapacity(self.allocator, content.len + 1);
                defer names.deinit();
                var names_link = try std.ArrayList(u8).initCapacity(self.allocator, content.len + 1);
                defer names_link.deinit();

                if (trimmedLine.len == 0) {
                    line_start = cursor;
                    line_number += 1;
                    continue;
                }

                if (fullTrimmedLine[0] == '[' and fullTrimmedLine[fullTrimmedLine.len - 1] == ']') {
                    // Section
                    current_section_name = fullTrimmedLine[1 .. fullTrimmedLine.len - 1];
                    var name_end_index: usize = 0;
                    var sklip: usize = 0;
                    var in_quotes = false;
                    for (current_section_name, 0..) |c, i| {
                        if (sklip > 0) {
                            continue;
                        }
                        if (c == '"' and (!in_quotes or (in_quotes and current_section_name[i - 1] != '\\'))) {
                            in_quotes = !in_quotes; // Toggle in_quotes state
                        }
                        if (!in_quotes and (c == ' ' or c == '.' or c == '"')) {
                            const n = current_section_name[name_end_index..(if (c == '"') i + 1 else i)];
                            if (n.len > 0) {
                                try names.append(try utils.unescapeChars(try utils.removeQuote(n)));
                            }
                            name_end_index = i + 1;
                            if (c == '"') {
                                sklip = sklip + 1;
                            }
                        }
                    }
                    // add last name
                    if (name_end_index < current_section_name.len) {
                        try names.append(try utils.unescapeChars(try utils.removeQuote(current_section_name[name_end_index..])));
                    }
                    var currentSection: ?Section = self.global();
                    for (names.items, 0..) |name, i| {
                        if (i > 0) {
                            currentSection = self.getOrCreateSection(names_link.items);
                            try names_link.append(' ');
                        }
                        try names_link.appendSlice(name);
                        if (!self.hasSection(names_link.items)) {
                            _ = try self.addSection(names_link.items);
                        }
                        // Create links
                        if (currentSection) |c| {
                            if (self.links.getPtr(c.name)) |link| {
                                // Allouer et copier la clé
                                const name_copy = try std.heap.page_allocator.alloc(u8, name.len);
                                std.mem.copyBackwards(u8, name_copy, name);
                                const link_copy = try std.heap.page_allocator.alloc(u8, names_link.items.len);
                                std.mem.copyBackwards(u8, link_copy, names_link.items);
                                try link.put(name, link_copy);
                            }
                        }
                    }
                    if (names_link.items.len > 0) {
                        const key_copy = try std.heap.page_allocator.alloc(u8, names_link.items.len);
                        std.mem.copyBackwards(u8, key_copy, names_link.items);
                        current_section_name = key_copy;
                    }
                } else if (fullTrimmedLine[0] != ';' and fullTrimmedLine[0] != '#') {
                    if (mem.indexOfScalar(u8, fullTrimmedLine, '=') != null) { // Property
                        const equals_index = mem.indexOf(u8, trimmedLine, "=").?;
                        var key = mem.trim(u8, trimmedLine[0..equals_index], " \t");
                        var value = mem.trim(u8, trimmedLine[equals_index + 1 ..], "\t");
                        // Handle multiline values
                        var multiline_buffer = std.ArrayList(u8).init(self.allocator);
                        defer multiline_buffer.deinit();
                        try multiline_buffer.appendSlice(value);

                        while (value.len > 0 and value[value.len - 1] == '\\') {
                            // Remove the backslash and any trailing whitespace from the buffer
                            while (multiline_buffer.items.len > 0 and multiline_buffer.items[multiline_buffer.items.len - 1] == '\\') {
                                // while (multiline_buffer.items.len > 0 and (multiline_buffer.items[multiline_buffer.items.len - 1] == '\\' or mem.indexOfScalar(u8, " \t", multiline_buffer.items[multiline_buffer.items.len - 1]) != null)) {
                                _ = multiline_buffer.pop();
                            }

                            // Read the next line
                            if (cursor < current_content.items.len) {
                                line_start = cursor;
                                // Find the next newline

                                while (cursor < current_content.items.len and current_content.items[cursor] != '\n') {
                                    cursor += 1;
                                }
                                if (cursor < current_content.items.len) {
                                    cursor += 1; // Consume the newline
                                }

                                line_number += 1;
                                const next_line = current_content.items[line_start .. cursor - 1];
                                const trimmed_next_line = mem.trimRight(u8, mem.trimLeft(u8, next_line, " "), "\t\r\n");
                                // Append the next line to the multiline buffer
                                try multiline_buffer.appendSlice(trimmed_next_line);
                                if (trimmed_next_line[trimmed_next_line.len - 1] != '\\') {
                                    break;
                                }
                            } else {
                                // End of content, but backslash continuation
                                break; // Or you might want to throw an error here
                            }
                        }
                        value = multiline_buffer.items;

                        // clean value
                        value = mem.trim(u8, value, " ");
                        // Remove outer quotes and handle escaped quotes
                        if (value.len > 1 and value[0] == '"') {
                            var content_end_index: usize = value.len;
                            var in_quotes: bool = false;
                            for (value, 0..) |c, i| {
                                if (c == '"') {
                                    in_quotes = !in_quotes; // Toggle in_quotes state
                                } else if (!in_quotes and (c == ';' or c == '#')) {
                                    content_end_index = i;
                                    break;
                                }
                            }
                            value = mem.trim(u8, value[0..content_end_index], " ");
                        }

                        // Allocate and copy key and value
                        key = try utils.unescapeChars(try utils.removeQuote(try utils.lower(key)));
                        const key_copy = try std.heap.page_allocator.alloc(u8, key.len);
                        std.mem.copyBackwards(u8, key_copy, key);

                        value = try utils.removeQuote(value);
                        value = try utils.unescapeChars(value);

                        const value_copy = try std.heap.page_allocator.alloc(u8, value.len);
                        std.mem.copyBackwards(u8, value_copy, value);
                        // std.debug.print("ADD KEY {s} {s} {s}\n", .{ current_section_name, key_copy, value_copy });
                        try self.put(current_section_name, key_copy, value_copy);
                    } else {
                        return errors.InvalidFormat;
                    }
                }

                line_start = cursor;
                line_number += 1;
            }
        }
    }

    pub fn section(self: *Parser, name: []const u8) ?Section {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.properties.getEntry(name)) |s| {
            if (self.links.getEntry(name)) |l| {
                return Section.init(self, s.value_ptr, l.value_ptr, name);
            } else {
                return null;
            }
        } else {
            return null;
        }
    }
    pub fn global(self: *Parser) Section {
        return self.getOrCreateSection("");
    }
    pub fn getOrCreateSection(self: *Parser, name: []const u8) Section {
        if (!self.hasSection(name)) {
            _ = self.addSection(name) catch null;
        }
        return self.section(name).?;
    }
    pub fn addSection(self: *Parser, name: []const u8) !Section {
        self.mutex.lock();
        {
            defer self.mutex.unlock();
            if (!self.hasSection(name)) {
                // Allouer et copier la clé
                const name_copy = try std.heap.page_allocator.alloc(u8, name.len);
                std.mem.copyBackwards(u8, name_copy, name);

                try self.properties.put(name_copy, std.StringHashMap([]const u8).init(self.allocator));
                // create links
                if (!self.links.contains(name_copy)) {
                    const link_copy = try std.heap.page_allocator.alloc(u8, name.len);
                    std.mem.copyBackwards(u8, link_copy, name);
                    try self.links.put(link_copy, std.StringHashMap([]const u8).init(self.allocator));
                }
            }
        }
        if (self.section(name)) |s| {
            return s;
        } else {
            return errors.MissingSection;
        }
    }
    pub fn hasSection(self: *const Parser, name: []const u8) bool {
        return self.properties.contains(name);
    }

    pub fn count(self: *Parser) u32 {
        return self.global().sectionsCount();
    }

    fn put(self: *Parser, section_name: []const u8, key: []const u8, value: []const u8) !void {
        _ = try self.addSection(section_name);
        try self.properties.getEntry(section_name).?.value_ptr.*.put(key, value);
    }
};

pub const Error = error{
    UnexpectedToken,
    CircularInclude,
};
