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

const main_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<command>
    \\
);

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
        .terminating_positional = 0,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try help();
        return;
    }

    const command = res.positionals[0] orelse return error.MissingCommand;
    switch (command) {
        .help => try help(),
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

fn editTag(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;
    std.debug.print("Editing Tags\n", .{});

    const params = comptime clap.parseParamsComptime(
        \\-a, --add Add a tag to the note.
        \\-d, --delete Delete a tag from the note.
        \\-h, --help Display this help and exit.
        \\<str>...
        \\
    );
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    const note_inputs = res.positionals[0];
    var note_title: ?[]const u8 = null;
    var tag_add_or_remove_flag: ?bool = null;
    var new_tag_list = std.ArrayList([]const u8).init(gpa);
    defer new_tag_list.deinit();

    if (res.args.add != 0) {
        std.debug.print("--add\n", .{});
        tag_add_or_remove_flag = true;
    }
    if (res.args.delete != 0) {
        std.debug.print("--delete\n", .{});
        tag_add_or_remove_flag = false;
    }
    if (res.args.help != 0) {
        std.debug.print("--help!\n", .{});
        return;
    } else {
        if (note_inputs.len < 2) {
            std.debug.print("No tags provided\n", .{});
            return;
        } else {
            note_title = note_inputs[0];
            for (note_inputs[1..]) |tag| {
                try new_tag_list.append(tag);
            }
        }

        var database = try db.getDb(gpa);
        defer database.deinit();
        const row = try db.getTagsAndId(gpa, &database, note_title.?);
        var tagSet = std.StringHashMap(void).init(gpa);
        defer tagSet.deinit();
        var note_id: ?i32 = null;
        note_id = row.id;
        const tags_slice = row.tags[0..];

        const r_tag_list = try makeTagList(gpa, tags_slice);
        defer r_tag_list.deinit();
        for (r_tag_list.items) |tag| {
            try tagSet.put(tag, {});
        }
        for (new_tag_list.items) |tag| {
            if (tag_add_or_remove_flag.?) {
                try tagSet.put(tag, {});
            } else {
                _ = tagSet.remove(tag);
            }
        }
        var tagIter = tagSet.keyIterator();
        var uniqueTags = std.ArrayList([]const u8).init(gpa);
        defer uniqueTags.deinit();
        while (tagIter.next()) |arg| {
            try uniqueTags.append(arg.*);
        }

        const serialized_tags = try std.json.stringifyAlloc(gpa, uniqueTags.items, .{});
        defer gpa.free(serialized_tags);
        try db.updateTags(&database, serialized_tags, note_id.?);
    }
}

fn findNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    _ = main_args;

    var tags_list = std.ArrayList([]const u8).init(gpa);
    defer tags_list.deinit();
    while (iter.next()) |arg| {
        try tags_list.append(arg);
    }
    var database = try db.getDb(gpa);
    defer database.deinit();

    const rows = try db.getAllTitlesAndTags(gpa, &database);
    defer gpa.free(rows);

    for (rows) |r| {
        const name_ptr: [*:0]const u8 = &r.title;
        const tags_ptr: [*:0]const u8 = &r.tags;
        const update_at_ptr: [*:0]const u8 = &r.updated_at;
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

    // lets change temp path to ~/.scrap/tmp/noteName_ts
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
    const original_note_content = try original_file.readToEndAlloc(gpa, 1048576);
    defer gpa.free(original_note_content);

    const editor = std.process.getEnvVarOwned(gpa, "EDITOR") catch "/opt/homebrew/bin/nvim";
    var proc = std.process.Child.init(&[_][]const u8{ editor, tmp_path }, gpa);

    if (proc.spawnAndWait()) |_| {} else |err| {
        std.debug.print("Failed to launch editor: {s}, error: {}\n", .{ editor, err });
        return err;
    }
    const file_read_only = try std.fs.cwd().openFile(tmp_path, .{ .mode = .read_only });
    const contents = try file_read_only.readToEndAlloc(gpa, 1048576);
    defer gpa.free(contents);
    if (!std.mem.eql(u8, contents, original_note_content)) {
        try db.updateNote(&database, contents, note_id);
    }
}
fn help() !void {

    // add,
    // delete,
    // find,
    // open,
    // editTag,
    // help,
    var cli_writer = std.io.getStdOut().writer();
    try cli_writer.print("**************************************************************************\n", .{});
    try cli_writer.print("==========================================================================\n", .{});
    try cli_writer.print("Scrap Commands \n", .{});
    try cli_writer.print("==========================================================================\n", .{});
    try cli_writer.print("add     - Adds a new Note ex. `scrap add note_name tag_1 tag_2`\n", .{});
    try cli_writer.print("delete  - Deletes a note ex. `scrap delete note_name`\n", .{});
    try cli_writer.print("find    - Finds notes with matching tags ex. `scrap find tag_1 tag_2`\n", .{});
    try cli_writer.print("open    - Opens note and saves note if modified ex. `scrap open note_name`\n", .{});
    try cli_writer.print("editTag - Edits tags on said file ex. `scrap editTag -a note_name tag_3`\n", .{});
    try cli_writer.print("help    - Shows available commands ex. `scrap help`\n", .{});
    try cli_writer.print("**************************************************************************\n", .{});
}

fn addNote(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
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
    const note_content = getUserInput(gpa, note_name.?) catch |err| {
        std.debug.print("Error getting user input: {}\n", .{err});
        return err;
    };
    defer gpa.free(note_content);

    var database = try db.getDb(gpa);
    try db.insertNote(&database, note_name.?, note_content, serialized_tags);
}

fn getUserInput(gpa: std.mem.Allocator, note_name: []const u8) ![]const u8 {
    const tmp_path_base = "~/.scrap/temp/";
    const epoch_ts = std.time.milliTimestamp();

    const tmp_path = try std.fmt.allocPrint(gpa, "{s}{s}{d}.md", .{ tmp_path_base, note_name, epoch_ts });
    defer gpa.free(tmp_path);

    try std.fs.cwd().makePath(tmp_path_base);

    const editor = std.process.getEnvVarOwned(gpa, "EDITOR") catch "/opt/homebrew/bin/nvim";

    std.debug.print("Using editor: {s}\n", .{editor});

    var proc = std.process.Child.init(&[_][]const u8{ editor, tmp_path }, gpa);

    if (proc.spawnAndWait()) |_| {} else |err| {
        std.debug.print("Failed to launch editor: {s}, error: {}\n", .{ editor, err });
        return err;
    }

    const file = try std.fs.cwd().openFile(tmp_path, .{ .mode = .read_only });
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try file.readToEndAlloc(gpa, file_size);
    // const contents = try file.readToEndAlloc(gpa, 1048576);
    return contents;
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

const db = @import("db.zig");
const sqlite = @import("sqlite");
const clap = @import("clap");
const std = @import("std");
const lib = @import("scrap_lib");
