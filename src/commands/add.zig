const std = @import("std");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const db = @import("../db.zig");

pub fn addNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: types.MainArgs) !void {
    _ = main_args;
    std.debug.print("Adding a note\n", .{});

    var note_name: ?[]const u8 = null;
    var json_list = std.ArrayList([]const u8).init(gpa);
    defer json_list.deinit();
    if (iter.next()) |arg| {
        note_name = arg;
    }
    while (iter.next()) |arg| {
        try json_list.append(arg);
    }
    const serialized_tags = try std.json.stringifyAlloc(gpa, json_list.items, .{});
    defer gpa.free(serialized_tags);
    std.debug.print("Note Name: {?s}, Note Tags: {s}\n", .{ note_name, serialized_tags });
    const note_content = utils.getUserInput(gpa, note_name.?) catch |err| {
        std.debug.print("Error getting user input: {}\n", .{err});
        return err;
    };
    defer gpa.free(note_content);

    var database = try db.getDb(gpa);
    try db.insertNote(&database, note_name.?, note_content, serialized_tags);
}