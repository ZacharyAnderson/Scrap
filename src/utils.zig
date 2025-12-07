const std = @import("std");

pub fn getUserInput(gpa: std.mem.Allocator, note_name: []const u8) ![]const u8 {
    const home_dir = std.process.getEnvVarOwned(gpa, "HOME") catch return error.NoHomeDir;
    defer gpa.free(home_dir);
    const tmp_path_base = try std.fs.path.join(gpa, &[_][]const u8{ home_dir, ".scrap", "temp/" });
    defer gpa.free(tmp_path_base);
    const epoch_ts = std.time.milliTimestamp();

    const tmp_path = try std.fmt.allocPrint(gpa, "{s}{s}_{d}.md", .{ tmp_path_base, note_name, epoch_ts });
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
    return contents;
}

pub fn makeTagList(gpa: std.mem.Allocator, tags_ref: *const [256:0]u8) !std.ArrayList([]const u8) {
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