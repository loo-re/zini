
###   `parser.zig`

This file contains the `Parser` struct and its methods for parsing INI files.

* **`Parser` struct:**
    * `allocator: std.mem.Allocator`:  The allocator used for memory management.
    * `mutex: std.Thread.Mutex`: A mutex for thread safety.
    * `properties: std.StringHashMap(std.StringHashMap([]const u8))`: A hash map storing the sections and their properties. The outer hash map's key is the section name, and the inner hash map's key is the property key.
    * `enable_include: bool`:  A flag to enable or disable include processing.

* **`init(allocator: mem.Allocator) !Parser`**
    * Initializes the `Parser` struct.
    * Creates the global section (section with an empty name).
    * Returns a `Parser` or an error.

* **`deinit(self: \*Parser) void`**
    * Deinitializes the `Parser`.
    * Frees all allocated memory for sections, keys, and values.
    * Destroys the mutex.

* **`loadText(self: \*Parser, text: \[\]const u8) !void`**
    * Parses INI formatted text from a string.
    * Disables include processing during text parsing.
    * Copies the input text and calls `parseContent`.

* **`loadFile(self: \*Parser, filePath: \[\]const u8) !void`**
    * Parses an INI file from the given file path.
    * Calls `processIncludes` to handle any include directives.
    * Calls `parseContent` to parse the file content.

* **`processIncludes(self: \*Parser, filePath: \[\]const u8) !\[\]const u8`**
    * Recursively processes `include` directives in the INI file.
    * Uses `readFileAndProcessIncludes` to read and process files.
    * Handles circular includes to prevent infinite loops.

* **`readFileAndProcessIncludes(...) ![]const u8`**
    * Reads the content of a file and processes include directives within it.
    * Uses a buffer to read the file in chunks.
    * Recursively calls itself to process included files.

* **`parseContent(self: \*Parser, content: \[\]const u8) !void`**
    * This is where the main parsing logic resides (See the code for detailed comments).
    * It handles sections, properties, comments, and multiline values.

* **`addSection`, `section`, `hasSection`, `global`**: Methods for section management.

###   `sections.zig`

This file defines the `Section` struct, which represents a section in the INI file.

* **`Section` struct:**
    * `properties: \*std.StringHashMap(\[\]const u8)`:  A pointer to the hash map that stores the properties within the section.
    * `allocator: mem.Allocator`:  The allocator used by the `Section`.

* **Methods:**
    * Methods to get property values as strings, integers, booleans, floats, and lists of these types.
    * Methods to check for the existence of a key.
    * Methods to iterate over keys and entries.

###   `errors.zig`

This file defines the `Error` enum used for error handling in the parser.

* **`Error` enum:**
    * Defines various error types that can occur during parsing, such as `FileNotFound`, `InvalidFormat`, `CircularInclude`, etc.

###   `ini_test.zig`

This file contains the unit tests for the INI parser.

* It uses the Zig testing framework (`std.testing`).
* It includes various test cases to cover different aspects of the parser, such as:
    * Loading from string and file.
    * Handling sections, properties, comments.
    * Include directives.
    * Error handling.
    * Data type conversion.
    * Multiline values.
