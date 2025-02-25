// we should support Add, Edit, Find, View, Help P0
const SubCommands = enum {
    add,
    delete,
    find,
    open,
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
fn findNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;
    std.debug.print("Finding a note\n", .{});
    // Need to alter this to search for tags instead
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
    const query = "SELECT title, note, tags FROM notes WHERE title = ?";
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const row = try stmt.one(
        struct { title: [128:0]u8, note: [1024:0]u8, tags: [256:0]u8 },
        .{},
        .{ .title = note_name },
    );
    if (row) |r| {
        const name_ptr: [*:0]const u8 = &r.title;
        const note_ptr: [*:0]const u8 = &r.note;
        const tags_ptr: [*:0]const u8 = &r.tags;
        std.log.debug("name: {s}, note: {s}, tags: {s}", .{ std.mem.span(name_ptr), std.mem.span(note_ptr), std.mem.span(tags_ptr) });
    }

    std.debug.print("gpa allocator address: {}\n", .{gpa});
}
fn openNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;
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
    const query = "SELECT note FROM notes WHERE title = ?";
    var stmt = try db.prepare(query);
    defer stmt.deinit();

    const row = try stmt.oneAlloc(
        struct { note: []const u8 },
        gpa,
        .{},
        .{ .title = note_name },
    );
    if (row) |r| {
        defer gpa.free(r.note);
        // const note_ptr: [*:0]const u8 = &r.note;
        // const note_slice = std.mem.sliceTo(note_ptr, 0);
        // std.log.debug("note: {s}", .{std.mem.span(note_ptr)});
        const tmp_path = "/tmp/scrap_note.md";
        const file = try std.fs.cwd().createFile(tmp_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(r.note);
    }
    const tmp_path = "/tmp/scrap_note.md";

    const editor = std.process.getEnvVarOwned(gpa, "EDITOR") catch "/opt/homebrew/bin/nvim";
    var proc = std.process.Child.init(&[_][]const u8{ editor, tmp_path }, gpa);

    if (proc.spawnAndWait()) |_| {} else |err| {
        std.debug.print("Failed to launch editor: {s}, error: {}\n", .{ editor, err });
        return err;
    }
    std.debug.print("Viewing a note\n", .{});
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

    // Print note content safely
    std.debug.print("Note content: {s}\n", .{note_content});

    //Need to take note content and add into a sql record
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

    const contents = try file.readToEndAlloc(gpa, 1024); // Max 4KB input
    try std.fs.cwd().deleteFile(tmp_path);
    return contents;
}

fn getDb(gpa: std.mem.Allocator) anyerror!sqlite.Db {
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
const sqlite = @import("sqlite");
const clap = @import("clap");
const std = @import("std");
/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("scrap_lib");
