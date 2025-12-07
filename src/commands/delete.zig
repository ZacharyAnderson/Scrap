const std = @import("std");
const types = @import("../types.zig");
const db = @import("../db.zig");

pub fn deleteNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: types.MainArgs) !void {
    _ = main_args;

    var note_name: ?[]const u8 = null;
    while (iter.next()) |arg| {
        note_name = arg;
    }

    std.debug.print("Attempting to delete Note: {s}\n", .{note_name.?});
    var database = try db.getDb(gpa);
    const row = try db.getNote(gpa, &database, note_name.?);

    const note_id = row.id;

    try db.deleteNote(&database, note_id);
}