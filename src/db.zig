const std = @import("std");
const sqlite = @import("sqlite");

pub const Note = struct {
    id: i32,
    title: [128:0]u8,
    note: [16000:0]u8,
    tags: [256:0]u8,
    updated_at: [128:0]u8,
    created_at: [128:0]u8, // Another extra field
};

// A smaller struct that matches the specific query result
pub const NoteMetadata = struct {
    title: [128:0]u8,
    tags: [256:0]u8,
    updated_at: [128:0]u8,
};

pub const NoteSummary = struct {
    id: i32,
    note: [16000:0]u8,
};

pub const NoteTags = struct {
    id: i32,
    tags: [256:0]u8,
};

pub fn getDb(gpa: std.mem.Allocator) !sqlite.Db {
    const home_dir = try std.process.getEnvVarOwned(gpa, "HOME");
    defer gpa.free(home_dir);

    const db_path_unsent = try std.fmt.allocPrint(gpa, "{s}/.scrap/scrap.db", .{home_dir});
    defer gpa.free(db_path_unsent);

    const db_path = try std.mem.concatWithSentinel(gpa, u8, &[_][]const u8{db_path_unsent}, 0);
    defer gpa.free(db_path);

    const db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    return db;
}

pub fn getNote(gpa: std.mem.Allocator, database: *sqlite.Db, note_title: []const u8) !NoteSummary {
    const query = "SELECT id, note FROM notes WHERE title = ?";
    var stmt = try database.prepare(query);
    defer stmt.deinit();

    const row = try stmt.oneAlloc(
        NoteSummary,
        gpa,
        .{},
        .{ .title = note_title },
    );
    if (row) |note| {
        return note;
    } else {
        return error.NoteNotFound;
    }
}

pub fn getAllTitlesAndTags(gpa: std.mem.Allocator, database: *sqlite.Db) ![]NoteMetadata {
    const query = "SELECT title, tags, updated_at as created_at FROM notes;";

    var stmt = try database.prepare(query);
    defer stmt.deinit();

    const rows = try stmt.all(
        NoteMetadata,
        gpa,
        .{},
        .{},
    );
    return rows;
}

pub fn getTagsAndId(gpa: std.mem.Allocator, database: *sqlite.Db, note_title: []const u8) !NoteTags {
    const query = "SELECT id, tags FROM notes WHERE title = ?";

    var stmt = try database.prepare(query);
    defer stmt.deinit();

    const row = try stmt.oneAlloc(
        NoteTags,
        gpa,
        .{},
        .{ .title = note_title },
    );
    if (row) |note| {
        return note;
    } else {
        return error.NoteNotFound;
    }
}

pub fn updateNote(database: *sqlite.Db, contents: []const u8, id: i32) !void {
    const update_query =
        \\UPDATE notes SET note = ?  where id = ?
    ;

    var update_stmt = try database.prepare(update_query);
    defer update_stmt.deinit();

    try update_stmt.exec(.{}, .{ contents, id });
}

pub fn updateTags(database: *sqlite.Db, tags: []const u8, id: i32) !void {
    const update_query =
        \\UPDATE notes SET tags = ?  where id = ?
    ;

    var update_stmt = try database.prepare(update_query);
    defer update_stmt.deinit();

    try update_stmt.exec(.{}, .{ tags, id });
}

pub fn deleteNote(database: *sqlite.Db, id: i32) !void {
    const delete_query =
        \\DELETE FROM notes where id = ?
    ;

    var update_stmt = try database.prepare(delete_query);
    defer update_stmt.deinit();

    try update_stmt.exec(.{}, .{id});
}

pub fn insertNote(database: *sqlite.Db, note_name: []const u8, note_content: []const u8, tags: []u8) !void {
    const query =
        \\INSERT INTO notes(title, note, tags) VALUES(?, ?, ?)
    ;

    var stmt = try database.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .title = note_name,
        .note = note_content,
        .tags = tags,
    });
}
