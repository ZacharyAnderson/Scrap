const types = @import("types.zig");
const help = @import("commands/help.zig");
const add = @import("commands/add.zig");
const delete = @import("commands/delete.zig");
const find = @import("commands/find.zig");
const open = @import("commands/open.zig");
const edit_tag = @import("commands/edit_tag.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    var iter = try std.process.ArgIterator.initWithAllocator(gpa);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &types.main_params, types.main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
        .terminating_positional = 0,
    }) catch {
        // Show custom error message instead of clap's diagnostic
        std.debug.print("Invalid command. Available commands:\n\n", .{});
        // Show help on invalid command
        try help.help();
        return;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try help.help();
        return;
    }

    const command = res.positionals[0] orelse {
        // Default to find command if no command is provided
        try find.findNote(gpa, &iter, res);
        return;
    };
    switch (command) {
        .help => try help.help(),
        .add => try add.addNote(gpa, &iter, res),
        .delete => try delete.deleteNote(gpa, &iter, res),
        .find => try find.findNote(gpa, &iter, res),
        .open => try open.openNote(gpa, &iter, res),
        .editTag => try edit_tag.editTag(gpa, &iter, res),
    }
}

const clap = @import("clap");
const std = @import("std");
