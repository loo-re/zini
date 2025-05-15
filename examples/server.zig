const server = @import("./server/server.zig");

pub fn main() !void {
    try server.start();
}
