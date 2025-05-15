const std = @import("std");
const zini = @import("./zini.zig");
const mem = std.mem;
const testing = std.testing;
const Parser = zini.Parser;
const errors = zini.errors;
const Section = zini.Section;
const TesttError = error{
    MissingSection,
    MissingKey,
};
const MyEnum = enum {
    Yes,
    MayBe,
    No,
};

fn createParserWithContent(allocator: mem.Allocator, content: []const u8) !Parser {
    var parser = Parser.init(allocator) catch |err| {
        return err;
    };
    if (parser.loadText(content)) {} else |err| {
        return err;
    }
    return parser;
}
fn createParser(allocator: std.mem.Allocator) !Parser {
    return Parser.init(allocator) catch |err| {
        return err;
    };
}

fn assertSectionExists(parser: *Parser, name: []const u8) bool {
    return parser.hasSection(name);
}
fn assertSubSectionExists(parser: *Parser, name: []const u8, sub_section: []const u8) bool {
    if (parser.section(name)) |section| {
        return section.hasSection(sub_section);
    }
    return false;
}

fn getSubSectionPropertyValue(parser: *Parser, section: []const u8, sub_section: []const u8, key: []const u8) ?[]const u8 {
    if (parser.section(section)) |s| {
        if (s.section(sub_section)) |sub| {
            return sub.getOptionalString(key);
        }
    }
    return null;
}
fn assertPropertyExists(parser: *Parser, section: []const u8, key: []const u8) bool {
    if (parser.section(section)) |s| {
        return s.has(key);
    }
    return false;
}

fn getPropertyValue(parser: *Parser, section: []const u8, key: []const u8) ?[]const u8 {
    if (parser.section(section)) |s| {
        return s.getOptionalString(key);
    }
    return null;
}
fn assertMultilineValue(parser: *Parser, section: []const u8, key: []const u8, expected_value: []const u8) !void {
    const s = parser.section(section) orelse return TesttError.MissingSection;
    const actual_value = s.getOptionalString(key) orelse return TesttError.MissingKey;
    try testing.expectEqualStrings(expected_value, actual_value);
}

test "loadText - with multiline value" {
    const allocator = std.heap.page_allocator;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const ini_text =
        \\
        \\[section1]
        \\ multiline_key = "; First line \
        \\               ; Second line \
        \\               # Third line" ; commentaire 
    ;

    try parser.loadText(ini_text);

    try assertMultilineValue(&parser, "section1", "multiline_key", "; First line ; Second line # Third line");
}

test "loadFile - with multiline value" {
    const allocator = std.heap.page_allocator;
    var parser = try Parser.init(allocator);
    defer parser.deinit();

    const ini_file_content =
        \\
        \\[section2]
        \\multiline_key = "Another first line \
        \\               Another second line \
        \\               Another third line \
        \\               With escaped quote: \"quote\" "
    ;

    // Create a temporary file
    const temp_file_path = "temp_ini_test.ini";
    {
        const file = try std.fs.cwd().createFile(temp_file_path, .{});
        defer file.close();
        try file.writeAll(ini_file_content);
    }

    try parser.loadFile(temp_file_path);
    defer std.fs.cwd().deleteFile(temp_file_path) catch {}; // Clean up the temp file

    try assertMultilineValue(&parser, "section2", "multiline_key", "Another first line Another second line Another third line With escaped quote: \"quote\" ");
}

test "loadFile - fichier inexistant" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "non_existent.ini";
    if (parser.loadFile(filename)) {
        // Ici `ok` est `void`, donc tu n’as rien à faire
        @panic("Expected an error, but got a result");
    } else |err| {
        switch (err) {
            error.FileNotFound => {},
            else => {
                return err;
            },
        }
    }
    // testing.expectError(error.FileNotFound, result); // Assuming you have FileNotFound error
}

test "loadFile - fichier vide" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "empty.ini";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = "" });
    defer std.fs.cwd().deleteFile(filename) catch {};

    try parser.loadFile(filename);
    try testing.expectEqual(parser.count(), 0); // Section globale vide
    try testing.expect(assertSectionExists(&parser, ""));
}

test "loadFile - fichier avec une section et une propriété" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "simple.ini";
    const content = "[section1]\nkey1 = value1\n";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    try parser.loadFile(filename);
    try testing.expectEqual(parser.count(), 1);
    try testing.expect(assertSectionExists(&parser, "section1"));
    try testing.expect(assertPropertyExists(&parser, "section1", "key1"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "section1", "key1").?, "value1");
}

test "loadFile - fichier avec plusieurs sections et propriétés" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "multiple.ini";
    const content = "[sectionA]\nkeyA1 = valueA1\nkeyA2 = valueA2\n\n[sectionB]\nkeyB1 = valueB1\n";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    try parser.loadFile(filename);
    try testing.expectEqual(parser.count(), 2);
    try testing.expect(assertSectionExists(&parser, "sectionA"));
    try testing.expect(assertPropertyExists(&parser, "sectionA", "keyA1"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "sectionA", "keyA1").?, "valueA1");
    try testing.expect(assertSectionExists(&parser, "sectionB"));
    try testing.expect(assertPropertyExists(&parser, "sectionB", "keyB1"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "sectionB", "keyB1").?, "valueB1");
}

test "loadFile - fichier avec sous sections et propriétés" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "multiple.ini";
    const content = "[section A]\nkeyA1 = valueA1\nkeyA2 = valueA2\n\n[section B]\nkeyB1 = valueB1\n";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    try parser.loadFile(filename);
    try testing.expectEqual(parser.count(), 1);
    try testing.expect(assertSectionExists(&parser, "section A"));
    try testing.expect(assertSubSectionExists(&parser, "section", "A"));
    try testing.expectEqualStrings(getSubSectionPropertyValue(&parser, "section", "A", "keyA1").?, "valueA1");
    try testing.expect(assertSectionExists(&parser, "section B"));
    try testing.expect(assertPropertyExists(&parser, "section B", "keyB1"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "section B", "keyB1").?, "valueB1");
}

test "loadFile - fichier avec commentaires" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "comments.ini";
    const content = "; commentaire global\n[section2] ; commentaire de section\nkey2 = value2 ; commentaire de propriété\n; autre commentaire\n";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    try parser.loadFile(filename);
    try testing.expectEqual(parser.count(), 1);
    try testing.expect(assertSectionExists(&parser, "section2"));
    try testing.expect(assertPropertyExists(&parser, "section2", "key2"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "section2", "key2").?, "value2");
}

test "loadFile - fichier avec propriétés dans la section globale" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "global_properties.ini";
    const content = "global_key = global_value\n[section3]\nkey3 = value3\n";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    try parser.loadFile(filename);
    try testing.expectEqual(parser.count(), 1);
    try testing.expect(assertPropertyExists(&parser, "", "global_key"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "", "global_key").?, "global_value");
    try testing.expect(assertSectionExists(&parser, "section3"));
    try testing.expect(assertPropertyExists(&parser, "section3", "key3"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "section3", "key3").?, "value3");
}

test "loadFile - fichier avec des espaces autour des clés et des valeurs" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "spaces.ini";
    const content = "[section4]\n  key4  =  value 4  \n";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    try parser.loadFile(filename);
    try testing.expect(assertPropertyExists(&parser, "section4", "key4"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "section4", "key4").?, "value 4");
}

test "loadFile - fichier avec des guillemets autour des valeurs" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "quotes.ini";
    const content = "[section5]\nkey5 = \"value with spaces\"\n";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    try parser.loadFile(filename);
    try testing.expect(assertPropertyExists(&parser, "section5", "key5"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "section5", "key5").?, "value with spaces");
}

test "loadFile - fichier avec des lignes vides" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "empty_lines.ini";
    const content = "\n[section6]\n\nkey6 = value6\n\n";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    defer std.fs.cwd().deleteFile(filename) catch {};

    try parser.loadFile(filename);
    try testing.expectEqual(parser.count(), 1);
    try testing.expect(assertSectionExists(&parser, "section6"));
    try testing.expect(assertPropertyExists(&parser, "section6", "key6"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "section6", "key6").?, "value6");
}

test "loadFile - fichier avec une erreur de format (ligne invalide)" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const filename = "invalid_format.ini";
    const content = "[section7]\ninvalid line\nkey7 = value7\n";
    try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
    defer std.fs.cwd().deleteFile(filename) catch {};
    parser.loadFile(filename) catch |err| {
        switch (err) {
            errors.InvalidFormat => {
                return;
            },
            else => {
                @panic("Expected errors.InvalidFormat, but got another error");
            },
        }
    };
    @panic("Expected an error, but got a result");
}

test "loadFile - fichier avec includes" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const main_filename = "main.ini";
    const include_filename = "include.ini";

    try std.fs.cwd().writeFile(.{ .sub_path = include_filename, .data = "included_key = included_value\n" });
    defer std.fs.cwd().deleteFile(include_filename) catch {};

    const main_content = "[main_section]\nmain_key = main_value\ninclude include.ini\n";
    try std.fs.cwd().writeFile(.{ .sub_path = main_filename, .data = main_content });
    defer std.fs.cwd().deleteFile(main_filename) catch {};

    try parser.loadFile(main_filename);
    try testing.expectEqual(parser.count(), 1);
    try testing.expect(assertSectionExists(&parser, "main_section"));
    try testing.expect(assertPropertyExists(&parser, "main_section", "main_key"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "main_section", "main_key").?, "main_value");
    try testing.expect(assertPropertyExists(&parser, "main_section", "included_key"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "main_section", "included_key").?, "included_value");
}

test "loadFile - fichier avec includes + echapement " {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = try createParser(allocator);
    defer parser.deinit();

    const main_filename = "main.ini";
    const include_filename = "includ#e.ini";

    try std.fs.cwd().writeFile(.{ .sub_path = include_filename, .data = "included_key = included_value\n" });
    defer std.fs.cwd().deleteFile(include_filename) catch {};

    const main_content = "[main_section]\nmain_key = main_value\ninclude includ\\#e.ini; inlcude super keys...\n";
    try std.fs.cwd().writeFile(.{ .sub_path = main_filename, .data = main_content });
    defer std.fs.cwd().deleteFile(main_filename) catch {};

    try parser.loadFile(main_filename);
    try testing.expectEqual(parser.count(), 1);
    try testing.expect(assertSectionExists(&parser, "main_section"));
    try testing.expect(assertPropertyExists(&parser, "main_section", "main_key"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "main_section", "main_key").?, "main_value");
    try testing.expect(assertPropertyExists(&parser, "main_section", "included_key"));
    try testing.expectEqualStrings(getPropertyValue(&parser, "main_section", "included_key").?, "included_value");
}

test "loadText - create" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = value\n[toto]\nkey = value2\n";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    const ini_content = parser.toString();
    defer parser.allocator.free(ini_content);
    try testing.expectEqualSlices(u8, content, ini_content);
}

test "getString - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = value\n[toto]\nkey=value2";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    try testing.expectEqualSlices(u8, "value", parser.global().getString("key", "default"));
}

test "getString - not exists - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqualSlices(u8, "default", parser.global().getString("key", "default"));
}

test "getOptionalString - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = value";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    const value = parser.global().getOptionalString("key");
    try testing.expectEqualSlices(u8, "value", value.?);
}

test "getOptionalString - not exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(null, parser.global().getOptionalString("key"));
}

test "getInt - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 123";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(@as(i64, 123), parser.global().getInt("key", 0));
}

test "getInt - not exists - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(@as(i64, 0), parser.global().getInt("key", 0));
}

test "getInt - invalid - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = abc";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(@as(i64, 0), parser.global().getInt("key", 0));
}

test "getOptionalInt - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 123";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(@as(i64, 123), parser.global().getOptionalInt("key").?);
}

test "getOptionalInt - not exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(null, parser.global().getOptionalInt("key"));
}

test "getOptionalInt - invalid" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = abc";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(null, parser.global().getOptionalInt("key"));
}

test "getFloat - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 3.14";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(@as(f64, 3.14), parser.global().getFloat("key", 0.0));
}

test "getFloat - not exists - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(@as(f64, 0.0), parser.global().getFloat("key", 0.0));
}

test "getFloat - invalid - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = abc";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(@as(f64, 0.0), parser.global().getFloat("key", 0.0));
}

test "getOptionalFloat - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 3.14";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(@as(f64, 3.14), parser.global().getOptionalFloat("key").?);
}

test "getOptionalFloat - not exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(null, parser.global().getOptionalFloat("key"));
}

test "getOptionalFloat - invalid" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = abc";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(null, parser.global().getOptionalFloat("key"));
}

test "getBool - true values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = TRUE\nkey2 = ON\nkey3 = ENABLE\nkey4 = ENABLED\nkey5 = 1\nkey6 = YES";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expect(parser.global().getBool("key", false));
    try testing.expect(parser.global().getBool("key2", false));
    try testing.expect(parser.global().getBool("key3", false));
    try testing.expect(parser.global().getBool("key4", false));
    try testing.expect(parser.global().getBool("key5", false));
    try testing.expect(parser.global().getBool("key6", false));
}

test "getBool - false values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = FALSE\nkey2 = OFF\nkey3 = DISABLE\nkey4 = DISABLED\nkey5 = 0\nkey6 = NO";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expect(!parser.global().getBool("key", true));
    try testing.expect(!parser.global().getBool("key2", true));
    try testing.expect(!parser.global().getBool("key3", true));
    try testing.expect(!parser.global().getBool("key4", true));
    try testing.expect(!parser.global().getBool("key5", true));
    try testing.expect(!parser.global().getBool("key6", true));
}

test "getBool - not exists - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expect(parser.global().getBool("key", true));
    try testing.expect(!parser.global().getBool("key", false));
}

test "getOptionalBool - true values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = TRUE";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expect(parser.global().getOptionalBool("key").?);
}

test "getOptionalBool - false values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = FALSE";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expect(parser.global().getOptionalBool("key").? == false);
}

test "getOptionalBool - not exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(null, parser.global().getOptionalBool("key"));
}

test "getOptionalBool - invalid" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = invalid";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(null, parser.global().getOptionalBool("key"));
}

test "getStringList - comma separated" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = item1, item2,  item3";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const []const u8 = &.{ "item1", "item2", "item3" };
    const s = parser.global().getStringList("key", ',', &.{});
    defer parser.allocator.free(s);
    try testing.expectEqual(expected.len, s.len);
    for (expected, 0..) |value, i| {
        try testing.expectEqualSlices(u8, value, s[i]);
    }
}

test "getStringList - pipe separated" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = valA | valB |valC";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const []const u8 = &.{ "valA", "valB", "valC" };
    const s = parser.global().getStringList("key", '|', &.{});
    defer parser.allocator.free(s);
    try testing.expectEqual(expected.len, s.len);
    for (expected, 0..) |value, i| {
        try testing.expectEqualSlices(u8, value, s[i]);
    }
}

test "getStringList - not exists - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const []const u8 = &.{"default"};
    const s = parser.global().getStringList("key", ',', &.{"default"});
    defer parser.allocator.free(s);
    try testing.expectEqual(expected.len, s.len);
    for (expected, 0..) |value, i| {
        try testing.expectEqualSlices(u8, value, s[i]);
    }
}

test "getOptionalStringList - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = item1, item2";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const []const u8 = &.{ "item1", "item2" };
    const s = parser.global().getOptionalStringList("key", ',').?;
    defer parser.allocator.free(s);
    try testing.expectEqual(expected.len, s.len);
    for (expected, 0..) |value, i| {
        try testing.expectEqualSlices(u8, value, s[i]);
    }
}

test "getOptionalStringList - not exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    const s = parser.global().getOptionalStringList("key", ',');
    if (s) |_s| {
        defer parser.allocator.free(_s);
    }
    try testing.expectEqual(null, s);
}

test "getIntList - comma separated" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 10, -20, 30";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const i64 = &.{ @as(i64, 10), -20, 30 };
    const list = parser.global().getIntList("key", ',', &.{});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(i64, expected, list);
}

test "getIntList - pipe separated" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 1|2| 3 | -4";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const i64 = &.{ @as(i64, 1), 2, 3, -4 };
    const list = parser.global().getIntList("key", '|', &.{});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(i64, expected, list);
}

test "getIntList - not exists - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const i64 = &.{@as(i64, 99)};
    const list = parser.global().getIntList("key", ',', &.{99});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(i64, expected, list);
}

test "getIntList - invalid entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 10, abc, 30";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const i64 = &.{ @as(i64, 10), 30 }; // Invalid entry is skipped
    const list = parser.global().getIntList("key", ',', &.{});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(i64, expected, list);
}

test "getOptionalIntList - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 1, 2, 3";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected = &.{ @as(i64, 1), 2, 3 };

    const list = parser.global().getOptionalIntList("key", ',');
    defer {
        if (list) |l| {
            defer parser.allocator.free(l);
        }
    }
    try testing.expectEqualSlices(i64, expected, list.?);
}

test "getOptionalIntList - not exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    const list = parser.global().getOptionalIntList("key", ',');
    defer {
        if (list) |l| {
            defer parser.allocator.free(l);
        }
    }

    try testing.expectEqual(null, list);
}

test "getOptionalIntList - invalid entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 1, abc, 3";
    const expected: []const i64 = &.{ @as(i64, 1), 3 }; // Invalid entry is skipped
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    const list = parser.global().getOptionalIntList("key", ',');
    defer {
        if (list) |l| {
            defer parser.allocator.free(l);
        }
    }
    try testing.expectEqualSlices(i64, expected, list.?); // Returns null if any parsing fails
}

test "getFloatList - comma separated" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 1.2, -3.4, 5.67";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected = &.{ @as(f64, 1.2), -3.4, 5.67 };
    const list = parser.global().getFloatList("key", ',', &.{});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(f64, expected, list);
}

test "getFloatList - pipe separated" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 0.1 | 2.0 | -3.14";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected = &.{ @as(f64, 0.1), 2.0, -3.14 };
    const list = parser.global().getFloatList("key", '|', &.{});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(f64, expected, list);
}

test "getFloatList - not exists - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected = &.{@as(f64, 99.9)};
    const list = parser.global().getFloatList("key", ',', &.{99.9});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(f64, expected, list);
}

test "getFloatList - invalid entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 1.2, abc, 3.4";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected = &.{ @as(f64, 1.2), 3.4 }; // Invalid entry is skipped
    const list = parser.global().getFloatList("key", ',', &.{});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(f64, expected, list);
}

test "getOptionalFloatList - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 1.1, 2.2, 3.3";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected = &.{ @as(f64, 1.1), 2.2, 3.3 };
    const list = parser.global().getOptionalFloatList("key", ',').?;
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(f64, expected, list);
}

test "getOptionalFloatList - not exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    const list = parser.global().getOptionalFloatList("key", ',');
    defer {
        if (list) |l| {
            defer parser.allocator.free(l);
        }
    }
    try testing.expectEqual(null, list);
}

test "getOptionalFloatList - invalid entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = 1.1, abc, 3.3\nkey2 = 1.1, abc, 3.3\n";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    const expected: []const f64 = &.{ @as(f64, 1.1), 3.3 }; // Invalid entry is skipped
    const list = parser.global().getOptionalFloatList("key", ',');
    defer {
        if (list) |l| {
            defer parser.allocator.free(l);
        }
    }
    try testing.expect(list != null); //  parsing fails if null
    try testing.expectEqualSlices(f64, expected, list.?); // Returns null if any parsing fails
}
test "getEnum - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const content = "key = no";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(MyEnum.No, parser.global().getEnum(MyEnum, "key", .Yes));
}

test "getEnum - not exists - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(MyEnum.MayBe, parser.global().getEnum(MyEnum, "key", .MayBe));
}

test "getEnum - invalid - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = abc";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(MyEnum.Yes, parser.global().getEnum(MyEnum, "key", .Yes));
}
test "getEnum - escaped entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = Y\\x0065s\n";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    try testing.expectEqual(.Yes, parser.global().getOptionalEnum(MyEnum, "key").?); //  parsing fails if not debug

}

test "getOptionalEnum - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = maybe";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(MyEnum.MayBe, parser.global().getOptionalEnum(MyEnum, "key").?);
}

test "getOptionalEnum - not exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(null, parser.global().getOptionalEnum(MyEnum, "key"));
}

test "getOptionalEnum - invalid" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = abc";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    try testing.expectEqual(null, parser.global().getOptionalEnum(MyEnum, "key"));
}

test "getOptionalEnum - escaped entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = MayB\\x0065\n";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    try testing.expectEqual(.MayBe, parser.global().getOptionalEnum(MyEnum, "key").?); //  parsing fails if not debug
}

test "getEnumList - comma separated" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = no,yes,no";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const MyEnum = &.{ .No, .Yes, .No };
    const list = parser.global().getEnumList(MyEnum, "key", ',', &.{});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(MyEnum, expected, list);
}

test "getEnumList - pipe separated" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = no | yes | no";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const MyEnum = &.{ .No, .Yes, .No };
    const list = parser.global().getEnumList(MyEnum, "key", '|', &.{});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(MyEnum, expected, list);
}

test "getEnumList - not exists - default" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const MyEnum = &.{MyEnum.MayBe};
    const list = parser.global().getEnumList(MyEnum, "key", ',', &.{MyEnum.MayBe});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(MyEnum, expected, list);
}

test "getEnumList - invalid entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = yes, abc, no";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const MyEnum = &.{ .Yes, .No };
    const list = parser.global().getEnumList(MyEnum, "key", ',', &.{});
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(MyEnum, expected, list);
}

test "getOptionalEnumList - exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = no, Yes, mayBe";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();

    const expected: []const MyEnum = &.{ .No, .Yes, .MayBe };
    const list = parser.global().getOptionalEnumList(MyEnum, "key", ',').?;
    defer parser.allocator.free(list);
    try testing.expectEqualSlices(MyEnum, expected, list);
}

test "getOptionalEnumList - not exists" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    const list = parser.global().getOptionalEnumList(MyEnum, "key", ',');
    defer {
        if (list) |l| {
            defer parser.allocator.free(l);
        }
    }
    try testing.expectEqual(null, list);
}

test "getOptionalEnumList - invalid entry" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const content = "key = yes, abc, no\nkey2 = 1.1, abc, 3.3\n";
    var parser = try createParserWithContent(allocator, content);
    defer parser.deinit();
    const expected: []const MyEnum = &.{ .Yes, .No }; // Invalid entry is skipped
    const list = parser.global().getOptionalEnumList(MyEnum, "key", ',');
    defer {
        if (list) |l| {
            defer parser.allocator.free(l);
        }
    }
    try testing.expect(list != null); //  parsing fails if null
    try testing.expectEqualSlices(MyEnum, expected, list.?); // Returns null if any parsing fails
}
