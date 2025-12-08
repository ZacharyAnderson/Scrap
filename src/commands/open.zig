const std = @import("std");
const types = @import("../types.zig");
const db = @import("../db.zig");

pub fn openNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: types.MainArgs) !void {
    _ = main_args;

    const tmp_path = "/tmp/scrap_note.md";
    var note_name: ?[]const u8 = null;
    while (iter.next()) |arg| {
        note_name = arg;
    }
    var database = try db.getDb(gpa);
    defer database.deinit();
    const row = try db.getNote(gpa, &database, note_name.?);

    const note_id = row.id;
    const file = try std.fs.cwd().createFile(tmp_path, .{ .truncate = true, .read = true });
    defer file.close();

    const note_length = std.mem.indexOfScalar(u8, &row.note, 0) orelse row.note.len;
    try file.writeAll(row.note[0..note_length]);
    const original_file = try std.fs.cwd().openFile(tmp_path, .{ .mode = .read_only });
    const file_size = try original_file.getEndPos();
    const original_note_content = try original_file.readToEndAlloc(gpa, file_size);
    defer gpa.free(original_note_content);

    const editor = std.process.getEnvVarOwned(gpa, "EDITOR") catch "/opt/homebrew/bin/nvim";
    var proc = std.process.Child.init(&[_][]const u8{ editor, tmp_path }, gpa);

    if (proc.spawnAndWait()) |_| {} else |err| {
        std.debug.print("Failed to launch editor: {s}, error: {}\n", .{ editor, err });
        return err;
    }
    const file_read_only = try std.fs.cwd().openFile(tmp_path, .{ .mode = .read_only });
    const updated_file_size = try file_read_only.getEndPos();
    const contents = try file_read_only.readToEndAlloc(gpa, updated_file_size);
    defer gpa.free(contents);
    if (!std.mem.eql(u8, contents, original_note_content)) {
        try db.updateNote(&database, contents, note_id);
    }
}

