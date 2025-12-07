const std = @import("std");
const types = @import("../types.zig");

pub fn findNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: types.MainArgs) !void {
    _ = main_args;

    // Get the path to the explorer script relative to this executable
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = std.fs.selfExeDirPath(&exe_dir_buf) catch {
        std.debug.print("Failed to get executable directory\n", .{});
        return;
    };

    const script_path = try std.fmt.allocPrint(gpa, "{s}/../../src/scripts/explorer.sh", .{exe_dir});
    defer gpa.free(script_path);

    // Collect any search arguments
    var args_list = std.ArrayList([]const u8).init(gpa);
    defer args_list.deinit();
    
    try args_list.append(script_path);
    
    // Add any search query arguments
    if (iter.next()) |search_query| {
        try args_list.append(search_query);
    }

    // Execute the explorer script with arguments
    var proc = std.process.Child.init(args_list.items, gpa);

    if (proc.spawnAndWait()) |_| {} else |err| {
        std.debug.print("Failed to launch explorer script: {}, trying fallback...\n", .{err});

        // Fallback: try to run from current directory
        var fallback_args = std.ArrayList([]const u8).init(gpa);
        defer fallback_args.deinit();
        
        try fallback_args.append("src/scripts/explorer.sh");
        
        // Add search query to fallback too
        if (args_list.items.len > 1) {
            try fallback_args.append(args_list.items[1]);
        }
        
        var fallback_proc = std.process.Child.init(fallback_args.items, gpa);

        if (fallback_proc.spawnAndWait()) |_| {} else |fallback_err| {
            std.debug.print("Failed to launch explorer script: {}\n", .{fallback_err});
            std.debug.print("Make sure explorer.sh exists and is executable\n", .{});
        }
    }
}