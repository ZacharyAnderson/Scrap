const std = @import("std");
const types = @import("../types.zig");
const db = @import("../db.zig");

pub fn deleteNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: types.MainArgs) !void {
    _ = main_args;

    var note_name: ?[]const u8 = null;
    while (iter.next()) |arg| {
        note_name = arg;
    }

    if (note_name == null) {
        std.debug.print("Error: No note name provided\n", .{});
        return;
    }

    std.debug.print("Attempting to delete Note: {s}\n", .{note_name.?});
    var database = try db.getDb(gpa);
    
    const row = db.getNote(gpa, &database, note_name.?) catch |err| {
        switch (err) {
            error.NoteNotFound => {
                std.debug.print("Note '{s}' does not exist\n", .{note_name.?});
                return;
            },
            else => return err,
        }
    };

    const note_id = row.id;
    try db.deleteNote(&database, note_id);
    std.debug.print("Note '{s}' deleted successfully\n", .{note_name.?});
}