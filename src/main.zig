// we should support Add, Edit, Find, View, Help P0
const SubCommands = enum {
    add,
    delete,
    find,
    open,
    editTag,
    help,
};

const main_parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
};

// The parameters for `main`. Parameters for the subcommands are specified further down.
const main_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<command>
    \\
);

// To pass around arguments returned by clap, `clap.Result` and `clap.ResultEx` can be used to
// get the return type of `clap.parse` and `clap.parseEx`.
const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    var iter = try std.process.ArgIterator.initWithAllocator(gpa);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = gpa,

        // Terminate the parsing of arguments after parsing the first positional (0 is passed
        // here because parsed positionals are, like slices and arrays, indexed starting at 0).
        //
        // This will terminate the parsing after parsing the subcommand enum and leave `iter`
        // not fully consumed. It can then be reused to parse the arguments for subcommands.
        .terminating_positional = 0,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        std.debug.print("--help\n", .{});

    const command = res.positionals[0] orelse return error.MissingCommand;
    switch (command) {
        .help => try help(gpa, &iter, res),
        .add => try addNote(gpa, &iter, res),
        .delete => try deleteNote(gpa, &iter, res),
        .find => try findNote(gpa, &iter, res),
        .open => try openNote(gpa, &iter, res),
        .editTag => try editTag(gpa, &iter, res),
    }
}

fn deleteNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    // Need to implement delete functionality
    _ = main_args;
    std.debug.print("Editing a note\n", .{});
    std.debug.print("gpa allocator address: {}\n", .{gpa});
    while (iter.next()) |arg| {
        std.debug.print("Arg: {s}\n", .{arg});
    }
}

fn editTag(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;
    std.debug.print("Editing Tags\n", .{});

    var note_title: ?[]const u8 = null;
    var new_tag_list = std.ArrayList([]const u8).init(gpa);
    defer new_tag_list.deinit();

    if (iter.next()) |arg| {
        note_title = arg;
    }
    while (iter.next()) |arg| {
        try new_tag_list.append(arg);
    }
    var db = try getDb(gpa);

    const query = "SELECT id, tags FROM notes WHERE title = ?";

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const row = try stmt.one(
        struct { id: i32, tags: [256:0]u8 },
        .{},
        .{ .title = note_title },
    );
    var tagSet = std.StringHashMap(void).init(gpa);
    defer tagSet.deinit();
    var note_id: ?i32 = null;
    if (row) |r| {
        note_id = r.id;
        const tags_slice = r.tags[0..];

        const r_tag_list = try makeTagList(gpa, tags_slice);
        defer r_tag_list.deinit();
        for (r_tag_list.items) |tag| {
            try tagSet.put(tag, {});
        }
    }
    for (new_tag_list.items) |tag| {
        try tagSet.put(tag, {});
    }
    var tagIter = tagSet.keyIterator();
    var uniqueTags = std.ArrayList([]const u8).init(gpa);
    defer uniqueTags.deinit();
    while (tagIter.next()) |arg| {
        try uniqueTags.append(arg.*);
    }

    const serialized_tags = try std.json.stringifyAlloc(gpa, uniqueTags.items, .{});
    defer gpa.free(serialized_tags);

    const update_query =
        \\UPDATE notes SET tags = ?  where id = ?
    ;

    var update_stmt = try db.prepare(update_query);
    defer update_stmt.deinit();

    try update_stmt.exec(.{}, .{ serialized_tags, note_id });
}

fn findNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;

    var tags_list = std.ArrayList([]const u8).init(gpa);
    defer tags_list.deinit();
    while (iter.next()) |arg| {
        try tags_list.append(arg);
    }
    const home_dir = try std.process.getEnvVarOwned(gpa, "HOME");
    defer gpa.free(home_dir);

    const db_path_unsent = try std.fmt.allocPrint(gpa, "{s}/.scrap/scrap.db", .{home_dir});
    defer gpa.free(db_path_unsent);

    const db_path = try std.mem.concatWithSentinel(gpa, u8, &[_][]const u8{db_path_unsent}, 0);
    defer gpa.free(db_path);

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });

    const query = "SELECT title, tags, updated_at FROM notes;";

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const rows = try stmt.all(
        struct { title: [128:0]u8, tags: [256:0]u8, update_at: [128:0]u8 },
        gpa,
        .{},
        .{},
    );
    defer gpa.free(rows);
    for (rows) |r| {
        const name_ptr: [*:0]const u8 = &r.title;
        const tags_ptr: [*:0]const u8 = &r.tags;
        const update_at_ptr: [*:0]const u8 = &r.update_at;
        const tags_slice = r.tags[0..];

        const r_tag_list = try makeTagList(gpa, tags_slice);
        defer r_tag_list.deinit();

        var map = std.StringHashMap(bool).init(gpa);
        defer map.deinit();

        for (r_tag_list.items) |tag| {
            try map.put(tag, true);
        }
        var tag_match: bool = true;
        for (tags_list.items) |tag| {
            if (map.get(tag)) |_| {} else {
                tag_match = false;
                break;
            }
        }
        if (tag_match) {
            std.debug.print("name: {s},  tags: {s}, last_updated: {s}\n", .{ std.mem.span(name_ptr), std.mem.span(tags_ptr), std.mem.span(update_at_ptr) });
        }
    }
}
fn openNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;

    const tmp_path = "/tmp/scrap_note.md";
    var note_name: ?[]const u8 = null;
    while (iter.next()) |arg| {
        std.debug.print("Arg: {s}\n", .{arg});
        note_name = arg;
    }
    const home_dir = try std.process.getEnvVarOwned(gpa, "HOME");
    defer gpa.free(home_dir);

    const db_path_unsent = try std.fmt.allocPrint(gpa, "{s}/.scrap/scrap.db", .{home_dir});
    defer gpa.free(db_path_unsent);

    const db_path = try std.mem.concatWithSentinel(gpa, u8, &[_][]const u8{db_path_unsent}, 0);
    defer gpa.free(db_path);

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    const query = "SELECT id, note FROM notes WHERE title = ?";
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const row = try stmt.oneAlloc(
        struct { id: i32, note: []const u8 },
        gpa,
        .{},
        .{ .title = note_name },
    );
    var note_id: ?i32 = null;
    if (row) |r| {
        note_id = r.id;
        defer gpa.free(r.note);
        const file = try std.fs.cwd().createFile(tmp_path, .{ .truncate = true, .read = true });
        defer file.close();
        try file.writeAll(r.note);
    }
    const original_file = try std.fs.cwd().openFile(tmp_path, .{ .mode = .read_only });
    const original_note_content = try original_file.readToEndAlloc(gpa, 1048576);
    defer gpa.free(original_note_content);

    const editor = std.process.getEnvVarOwned(gpa, "EDITOR") catch "/opt/homebrew/bin/nvim";
    var proc = std.process.Child.init(&[_][]const u8{ editor, tmp_path }, gpa);

    if (proc.spawnAndWait()) |_| {} else |err| {
        std.debug.print("Failed to launch editor: {s}, error: {}\n", .{ editor, err });
        return err;
    }
    const file = try std.fs.cwd().openFile(tmp_path, .{ .mode = .read_only });
    const contents = try file.readToEndAlloc(gpa, 1048576);
    defer gpa.free(contents);
    if (!std.mem.eql(u8, contents, original_note_content)) {
        const update_query =
            \\UPDATE notes SET note = ?  where id = ?
        ;

        var update_stmt = try db.prepare(update_query);
        defer update_stmt.deinit();

        try update_stmt.exec(.{}, .{ contents, note_id });
    }
    try std.fs.cwd().deleteFile(tmp_path);
}
fn help(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;
    std.debug.print("Help!\n", .{});
    std.debug.print("gpa allocator address: {}\n", .{gpa});
    while (iter.next()) |arg| {
        std.debug.print("Arg: {s}\n", .{arg});
    }
}

fn addNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;
    std.debug.print("Adding a note\n", .{});

    var note_name: ?[]const u8 = null;
    var json_list = std.ArrayList([]const u8).init(gpa);
    defer json_list.deinit();
    if (iter.next()) |arg| {
        std.debug.print("Arg: {s}\n", .{arg});
        note_name = arg;
    }
    while (iter.next()) |arg| {
        std.debug.print("Arg: {s}\n", .{arg});
        try json_list.append(arg);
    }
    const serialized_tags = try std.json.stringifyAlloc(gpa, json_list.items, .{});
    defer gpa.free(serialized_tags);
    std.debug.print("Note Name: {?s}, Note Tags: {s}\n", .{ note_name, serialized_tags });
    const note_content = getUserInput(gpa) catch |err| {
        std.debug.print("Error getting user input: {}\n", .{err});
        return err;
    };
    defer gpa.free(note_content);

    const home_dir = try std.process.getEnvVarOwned(gpa, "HOME");
    defer gpa.free(home_dir);

    const db_path_unsent = try std.fmt.allocPrint(gpa, "{s}/.scrap/scrap.db", .{home_dir});
    defer gpa.free(db_path_unsent);

    const db_path = try std.mem.concatWithSentinel(gpa, u8, &[_][]const u8{db_path_unsent}, 0);
    defer gpa.free(db_path);

    var db = try sqlite.Db.init(.{
        .mode = sqlite.Db.Mode{ .File = db_path },
        .open_flags = .{
            .write = true,
            .create = true,
        },
        .threading_mode = .MultiThread,
    });
    const query =
        \\INSERT INTO notes(title, note, tags) VALUES(?, ?, ?)
    ;

    var stmt = try db.prepare(query);
    defer stmt.deinit();

    try stmt.exec(.{}, .{
        .title = note_name,
        .note = note_content,
        .tags = serialized_tags,
    });
}

fn getUserInput(gpa: std.mem.Allocator) ![]const u8 {
    const tmp_path = "/tmp/scrap_note.md";

    const editor = std.process.getEnvVarOwned(gpa, "EDITOR") catch "/opt/homebrew/bin/nvim";

    std.debug.print("Using editor: {s}\n", .{editor});

    var proc = std.process.Child.init(&[_][]const u8{ editor, tmp_path }, gpa);

    if (proc.spawnAndWait()) |_| {} else |err| {
        std.debug.print("Failed to launch editor: {s}, error: {}\n", .{ editor, err });
        return err;
    }

    const file = try std.fs.cwd().openFile(tmp_path, .{ .mode = .read_only });
    defer file.close();

    const contents = try file.readToEndAlloc(gpa, 1048576);
    try std.fs.cwd().deleteFile(tmp_path);
    return contents;
}

fn getDb(gpa: std.mem.Allocator) !sqlite.Db {
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

fn makeTagList(gpa: std.mem.Allocator, tags_ref: *const [256:0]u8) !std.ArrayList([]const u8) {
    const tags_slice = tags_ref[0..];

    const tag_length = std.mem.indexOf(u8, tags_slice, "\x00") orelse tags_slice.len;
    const raw_tags = tags_slice[0..tag_length];
    var tags_str = raw_tags;
    if (tags_str.len > 0 and tags_str[0] == '[') {
        tags_str = tags_str[1..];
    }
    if (tags_str.len > 0 and tags_str[tags_str.len - 1] == ']') {
        tags_str = tags_str[0 .. tags_str.len - 1];
    }

    var r_tag_list = std.ArrayList([]const u8).init(gpa);

    var start: usize = 0;
    while (start <= tags_str.len) {
        var token_end: usize = start;
        while (token_end < tags_str.len and tags_str[token_end] != ',') {
            token_end += 1;
        }
        const token = tags_str[start..token_end];
        const trimmed = std.mem.trim(u8, token, " \"");
        try r_tag_list.append(trimmed);
        if (token_end >= tags_str.len) break;
        start = token_end + 1;
    }
    return r_tag_list;
}

const sqlite = @import("sqlite");
const clap = @import("clap");
const std = @import("std");
/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("scrap_lib");
