const std = @import("std");

pub fn help() !void {
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
    try cli_writer.print("todo    - Manage todos ex. `scrap todo add \"task\" --priority high`\n", .{});
    try cli_writer.print("          scrap todo list [-a] [-i] | scrap todo done \"task\"\n", .{});
    try cli_writer.print("          scrap todo edit \"task\" --priority med | scrap todo rm \"task\"\n", .{});
    try cli_writer.print("help    - Shows available commands ex. `scrap help`\n", .{});
    try cli_writer.print("**************************************************************************\n", .{});
}