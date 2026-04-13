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

pub fn parseNotifyTime(input: []const u8) !i64 {
    const now = std.time.timestamp();

    // Try relative duration: 30m, 2h, 1d
    if (input.len >= 2) {
        const last_char = input[input.len - 1];
        if (last_char == 'm' or last_char == 'h' or last_char == 'd') {
            const num_str = input[0 .. input.len - 1];
            const num = std.fmt.parseInt(i64, num_str, 10) catch return error.InvalidNotifyTime;
            const seconds: i64 = switch (last_char) {
                'm' => num * 60,
                'h' => num * 3600,
                'd' => num * 86400,
                else => unreachable,
            };
            return now + seconds;
        }
    }

    // Try absolute time: "9:00am", "14:30", "9:00pm"
    return parseAbsoluteTime(input, now);
}

fn parseAbsoluteTime(input: []const u8, now: i64) !i64 {
    var hour: i64 = 0;
    var minute: i64 = 0;
    var is_pm = false;
    var is_12h = false;

    // Strip am/pm suffix
    var time_str = input;
    if (std.mem.endsWith(u8, input, "am")) {
        time_str = input[0 .. input.len - 2];
        is_12h = true;
    } else if (std.mem.endsWith(u8, input, "pm")) {
        time_str = input[0 .. input.len - 2];
        is_pm = true;
        is_12h = true;
    }

    // Parse HH:MM
    if (std.mem.indexOf(u8, time_str, ":")) |colon_pos| {
        hour = std.fmt.parseInt(i64, time_str[0..colon_pos], 10) catch return error.InvalidNotifyTime;
        minute = std.fmt.parseInt(i64, time_str[colon_pos + 1 ..], 10) catch return error.InvalidNotifyTime;
    } else {
        // Just an hour like "9am"
        hour = std.fmt.parseInt(i64, time_str, 10) catch return error.InvalidNotifyTime;
    }

    if (is_12h) {
        if (is_pm and hour != 12) hour += 12;
        if (!is_pm and hour == 12) hour = 0;
    }

    if (hour < 0 or hour > 23 or minute < 0 or minute > 59) return error.InvalidNotifyTime;

    // Calculate target timestamp: get today's start, add hours+minutes
    const secs_into_day = @mod(now, 86400);
    const today_start = now - secs_into_day;
    var target = today_start + (hour * 3600) + (minute * 60);

    // If the time has already passed today, schedule for tomorrow
    if (target <= now) {
        target += 86400;
    }

    return target;
}

pub fn formatTimestamp(gpa: std.mem.Allocator, epoch: i64) ![]const u8 {
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(epoch) };
    const ed = es.getEpochDay();
    const yd = ed.calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();

    return try std.fmt.allocPrint(gpa, "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
        yd.year,
        @as(u16, @intFromEnum(md.month)),
        @as(u16, md.day_index) + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    });
}

test "parseNotifyTime relative minutes" {
    const before = std.time.timestamp();
    const result = try parseNotifyTime("30m");
    const after = std.time.timestamp();
    try std.testing.expect(result >= before + 1800);
    try std.testing.expect(result <= after + 1800);
}

test "parseNotifyTime relative hours" {
    const before = std.time.timestamp();
    const result = try parseNotifyTime("2h");
    const after = std.time.timestamp();
    try std.testing.expect(result >= before + 7200);
    try std.testing.expect(result <= after + 7200);
}

test "parseNotifyTime relative days" {
    const before = std.time.timestamp();
    const result = try parseNotifyTime("1d");
    const after = std.time.timestamp();
    try std.testing.expect(result >= before + 86400);
    try std.testing.expect(result <= after + 86400);
}

test "parseNotifyTime invalid input" {
    const result = parseNotifyTime("abc");
    try std.testing.expectError(error.InvalidNotifyTime, result);
}