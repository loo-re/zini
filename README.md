#  ZINI - Yet Another Zig INI Parser 

**ZINI** is the most consistent INI file parser library written in ZIG. The parser is designed to be robust and handle various INI file formats.

##   Features

* **Comments:** Ignores lines starting with `;` or `#`. 
* **Includes:** Supports including other INI files using the `include` directive. 
* **Sections:** Parses sections denoted by `[section_name]`. 
* **Section nesting:** Handles nested sections (sub sections)  in the format `[section.subsection]` `[section subsection sub]` or `[section subsection]`. 
* **Key-Value Pairs:** Extracts key-value pairs from sections (`key = value`). 
* **Multiline Values:** Supports multiline values using escaped newlines within double quotes. 
* **Character Escaping:** Handles escaped characters within values.
* **Value type:** bool,[]const bool, i64, []const i64, f64, []const f64, []const u8, []const []const u8.
* **Read Support:** Read from File, and Strings.

## Installation

Developers tend to either use
* The latest tagged release of Zig
* The latest build of Zigs master branch

Depending on which developer you are, you need to run different `zig fetch` commands:

```sh
# Version of zini that works with a tagged release of Zig
# Replace `<REPLACE ME>` with the version of zini that you want to use
# See: https://github.com/loo-re/zini/releases
zig fetch --save https://github.com/loo-re/zini/archive/refs/tags/<REPLACE ME>.tar.gz

# Version of zini that works with latest build of Zigs master branch
zig fetch --save git+https://github.com/loo-re/zini
```

Then add the following to `build.zig`:

```zig
const zini = b.dependency("zini", .{});
exe.root_module.addImport("zini", zini.module("zini"));
```


##   Example

```zig
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
        \\                 line2 \
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
````

## API Reference

### `Parser`

The `Parser` struct is the main entry point for parsing INI data. 

#### `Parser.init(allocator: std.mem.Allocator) !Parser`

Initializes a new `Parser` instance.  It takes an allocator for memory management. 

  * `allocator`:  The allocator to use for memory allocation.
  * Returns: A `!Parser` which is either a `Parser` on success or an error.

#### `Parser.deinit(self: *Parser) void`

Deinitializes the `Parser`, freeing all allocated memory. 

  * `self`:  A pointer to the `Parser` instance.

#### `Parser.loadText(self: *Parser, text: []const u8) !void`

Parses INI data from a string. 

  * `self`: A pointer to the `Parser` instance.
  * `text`: The INI formatted text to parse.
  * Returns: `!void` which is void on success or an error.

#### `Parser.loadFile(self: *Parser, file_path: []const u8) !void`

Parses INI data from a file. 

  * `self`: A pointer to the `Parser` instance.
  * `file_path`: The path to the INI file.
  * Returns: `!void` which is void on success or an error.

#### `Parser.section(self: *Parser, name: []const u8) ?Section`

Retrieves a `Section` by name. 

  * `self`: A pointer to the `Parser` instance.
  * `name`: The name of the section.
  * Returns: An optional `Section` (`?Section`).

#### `Parser.hasSection(self: *const Parser, name: []const u8) bool`

Checks if a section exists. 

  * `self`: A pointer to the `Parser` instance.
  * `name`: The name of the section.
  * Returns: `true` if the section exists, `false` otherwise.

#### `Parser.global(self: *Parser) Section`

Gets the global section. 

  * `self`: A pointer to the `Parser` instance.
  * Returns: The global `Section`.

### `Section`

The `Section` struct provides methods for accessing data within a section. 

#### `Section.has(self: *const Section, key: []const u8) bool`

Checks if a key exists in the section. 

  * `self`: A pointer to the `Section` instance.
  * `key`: The key to check for.
  * Returns: `true` if the key exists, `false` otherwise.

#### `Section.getString(self: *const Section, name: []const u8, defValue: []const u8) []const u8`

Gets a string value for a key. If the key is not found, returns a default value. 

  * `self`: A pointer to the `Section` instance.
  * `name`: The name of the key.
  * `defValue`: The default string value to return if the key is not found.
  * Returns: The string value.

#### `Section.getOptionalString(self: *const Section, name: []const u8) ?[]const u8`

Gets an optional string value for a key. Returns `null` if the key is not found. 

  * `self`: A pointer to the `Section` instance.
  * `name`: The name of the key.
  * Returns: An optional string (`?[]const u8`).

#### Other `Section` methods

The `Section` struct also provides methods for retrieving boolean, integer, float, and lists of these types. Please refer to the code for the full API. 

### `Error`

The `Error` enum defines the possible errors that can occur during parsing. 

```zig
pub const Error = error{
    InvalidFormat,
    MissingSection,
    CircularInclude
};
```

## INI Format Support

The parser supports the following [INI format](https://en.wikipedia.org/wiki/INI_file) the folowed features:

  * **Sections:** `[section_name]`
  * **Nested sections:** `[section.subsection]` or `[section subsection]`
  * **Key-value pairs:** `key = value`
  * **Comments:** Lines starting with `;` or `#`
  * **Includes:** `include other_file.ini`
  * **Multiline values:**
    ```ini
    key = "line1\
           line2\
           line3"
    ```
  * **Character Escaping:** The parser handles escaped characters within values.

### Escape characters 
 
 | escape     | Char      | Hex (u8) | Description               |
 | ---------- | --------- | -------- | ------------------------- |
 | `\0`       | NUL       | `0x00`   | Null character            |
 | `\a`       | BEL       | `0x07`   | Bell/alert (audible)      |
 | `\b`       | BS        | `0x08`   | Backspace                 |
 | `\t`       | TAB       | `0x09`   | Horizontal tab            |
 | `\r`       | CR        | `0x0D`   | Carriage return           |
 | `\n`       | LF        | `0x0A`   | Line feed (new line)      |
 | `\\`       | `\`       | `0x5C`   | Antislash (backslash)     |
 | `\'`       | `'`       | `0x27`   | Apostrophe (single quote) |
 | `\"`       | `"`       | `0x22`   | Double quote              |
 | `\;`       | `;`       | `0x3B`   | Semi-colon                |
 | `\#`       | `#`       | `0x23`   | hash                      |
 | `\=`       | `=`       | `0x3D`   | Equals sign               |
 | `\:`       | `:`       | `0x3A`   | Colon                     |
 | `\xHHHH`   | 0xHHHH    | `0xHHHH` | UTF-8 Code point          |

## Testing

The code includes comprehensive tests in `ini_test.zig`.  To run the tests, use the command:

```bash
zig test ini_test.zig
```

## Dependencies

  * Zig standard library

## 📄 License

This project is dual-licensed:

- 🆓 **GPL-3.0**: For open-source use with full code sharing.
- 💼 **Commercial License**: For proprietary, embedded, or closed-source usage.

For commercial licensing options, please visit:
👉 badinga.ulrich@gmail.com


## Contributing

Contributions are welcome\! Please submit pull requests or issues on the project's repository.
