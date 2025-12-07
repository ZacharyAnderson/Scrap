const std = @import("std");
const clap = @import("clap");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const db = @import("../db.zig");

pub fn editTag(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: types.MainArgs) !void {
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

        const r_tag_list = try utils.makeTagList(gpa, tags_slice);
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