const std = @import("std");
const clap = @import("clap");
const types = @import("../types.zig");
const utils = @import("../utils.zig");
const db = @import("../db.zig");

const TodoAction = enum {
    add,
    list,
    done,
    edit,
    rm,
};

pub fn todo(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: types.MainArgs) !void {
    _ = main_args;

    const action_str = iter.next() orelse {
        std.debug.print("Error: Missing todo sub-command. Usage: scrap todo <add|list|done|edit|rm>\n", .{});
        return;
    };

    const action = std.meta.stringToEnum(TodoAction, action_str) orelse {
        std.debug.print("Error: Unknown todo sub-command '{s}'. Available: add, list, done, edit, rm\n", .{action_str});
        return;
    };

    switch (action) {
        .add => try todoAdd(gpa, iter),
        .list => try todoList(gpa, iter),
        .done => try todoDone(gpa, iter),
        .edit => try todoEdit(gpa, iter),
        .rm => try todoRm(gpa, iter),
    }
}

fn todoAdd(gpa: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-p, --priority <str>  Priority: low, med, high (default: med)
        \\-t, --tags <str>...   Tags for the todo
        \\-n, --notify <str>    Notify time (e.g. 30m, 2h, 1d, 9:00am)
        \\-h, --help            Display this help and exit.
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

    if (res.args.help != 0) {
        std.debug.print("Usage: scrap todo add \"title\" [--priority low|med|high] [--tags tag1 tag2] [--notify 30m]\n", .{});
        return;
    }

    const positionals = res.positionals[0];
    if (positionals.len == 0) {
        std.debug.print("Error: No todo title provided\n", .{});
        return;
    }
    const title = positionals[0];

    // Validate priority
    const priority = res.args.priority orelse "med";
    if (!std.mem.eql(u8, priority, "low") and !std.mem.eql(u8, priority, "med") and !std.mem.eql(u8, priority, "high")) {
        std.debug.print("Error: Invalid priority '{s}'. Must be low, med, or high\n", .{priority});
        return;
    }

    // Serialize tags as JSON
    const tags_args = res.args.tags;
    var json_list = std.ArrayList([]const u8).init(gpa);
    defer json_list.deinit();
    for (tags_args) |tag| {
        try json_list.append(tag);
    }
    // Also treat extra positionals (after title) as tags
    for (positionals[1..]) |tag| {
        try json_list.append(tag);
    }
    const serialized_tags = try std.json.stringifyAlloc(gpa, json_list.items, .{});
    defer gpa.free(serialized_tags);

    // Parse notify time if provided
    var notify_str: ?[]const u8 = null;
    var notify_str_owned: ?[]const u8 = null;
    defer if (notify_str_owned) |s| gpa.free(s);

    if (res.args.notify) |notify_input| {
        const epoch = utils.parseNotifyTime(notify_input) catch {
            std.debug.print("Error: Invalid notify time '{s}'. Use formats like 30m, 2h, 1d, 9:00am, 14:30\n", .{notify_input});
            return;
        };
        notify_str_owned = try utils.formatTimestamp(gpa, epoch);
        notify_str = notify_str_owned;
    }

    var database = try db.getDb(gpa);
    defer database.deinit();

    db.insertTodo(&database, title, priority, serialized_tags, notify_str) catch |err| {
        switch (err) {
            error.SQLiteError => {
                std.debug.print("Error: A todo with title '{s}' may already exist\n", .{title});
                return;
            },
            else => return err,
        }
    };

    std.debug.print("Todo '{s}' added (priority: {s})\n", .{ title, priority });
}

fn todoList(gpa: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-a, --all             Include done todos
        \\-t, --tag <str>       Filter by tag
        \\-p, --priority <str>  Filter by priority
        \\-i, --interactive     Launch interactive todo explorer
        \\-h, --help            Display this help and exit.
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

    if (res.args.help != 0) {
        std.debug.print("Usage: scrap todo list [-a] [-t tag] [-p priority] [-i]\n", .{});
        return;
    }

    // Interactive mode
    if (res.args.interactive != 0) {
        try launchTodoExplorer(gpa);
        return;
    }

    const include_done = res.args.all != 0;
    const filter_tag = res.args.tag;
    const filter_priority = res.args.priority;

    var database = try db.getDb(gpa);
    defer database.deinit();

    const rows = try db.listTodos(gpa, &database, include_done);
    defer gpa.free(rows);

    if (rows.len == 0) {
        std.debug.print("No todos found.\n", .{});
        return;
    }

    var cli_writer = std.io.getStdOut().writer();

    // Print header
    try cli_writer.print(" #   Title                          Priority  Tags                 Notify\n", .{});
    try cli_writer.print(" --- ------------------------------ --------  -------------------- ----------\n", .{});

    var count: usize = 0;
    for (rows) |row| {
        const title_slice = std.mem.sliceTo(&row.title, 0);
        const status_slice = std.mem.sliceTo(&row.status, 0);
        const priority_slice = std.mem.sliceTo(&row.priority, 0);
        const tags_slice = std.mem.sliceTo(&row.tags, 0);
        const notify_slice = std.mem.sliceTo(&row.notify_at, 0);

        // Apply tag filter
        if (filter_tag) |tag| {
            if (std.mem.indexOf(u8, tags_slice, tag) == null) {
                continue;
            }
        }

        // Apply priority filter
        if (filter_priority) |pri| {
            if (!std.mem.eql(u8, priority_slice, pri)) {
                continue;
            }
        }

        count += 1;
        const is_done = std.mem.eql(u8, status_slice, "done");
        const prefix: []const u8 = if (is_done) "x" else " ";

        const notify_display: []const u8 = if (notify_slice.len == 0) "--" else notify_slice;

        try cli_writer.print("{s}{d: >3}  {s:<30} {s:<8}  {s:<20} {s}\n", .{
            prefix,
            count,
            title_slice,
            priority_slice,
            tags_slice,
            notify_display,
        });
    }

    if (count == 0) {
        std.debug.print("No todos match the filter criteria.\n", .{});
    }
}

fn todoDone(gpa: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    const title = iter.next() orelse {
        std.debug.print("Error: No todo title provided. Usage: scrap todo done \"title\"\n", .{});
        return;
    };

    var database = try db.getDb(gpa);
    defer database.deinit();

    const row = db.getTodo(gpa, &database, title) catch |err| {
        switch (err) {
            error.TodoNotFound => {
                std.debug.print("Error: Todo '{s}' not found\n", .{title});
                return;
            },
            else => return err,
        }
    };

    const status_slice = std.mem.sliceTo(&row.status, 0);
    if (std.mem.eql(u8, status_slice, "done")) {
        std.debug.print("Todo '{s}' is already done\n", .{title});
        return;
    }

    try db.updateTodoStatus(&database, "done", row.id);
    std.debug.print("Todo '{s}' marked as done\n", .{title});
}

fn todoEdit(gpa: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    const params = comptime clap.parseParamsComptime(
        \\    --title <str>     New title
        \\-p, --priority <str>  New priority: low, med, high
        \\-t, --tags <str>...   New tags (replaces existing)
        \\-n, --notify <str>    New notify time
        \\    --no-notify       Remove notification
        \\-h, --help            Display this help and exit.
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

    if (res.args.help != 0) {
        std.debug.print("Usage: scrap todo edit \"title\" [--title new] [--priority med] [--tags t1 t2] [--notify 1h] [--no-notify]\n", .{});
        return;
    }

    const positionals = res.positionals[0];
    if (positionals.len == 0) {
        std.debug.print("Error: No todo title provided\n", .{});
        return;
    }
    const title = positionals[0];

    const has_title = res.args.title != null;
    const has_priority = res.args.priority != null;
    const has_tags = res.args.tags.len > 0;
    const has_notify = res.args.notify != null;
    const has_no_notify = res.args.@"no-notify" != 0;

    if (!has_title and !has_priority and !has_tags and !has_notify and !has_no_notify) {
        std.debug.print("Error: At least one edit flag is required (--title, --priority, --tags, --notify, --no-notify)\n", .{});
        return;
    }

    var database = try db.getDb(gpa);
    defer database.deinit();

    const row = db.getTodo(gpa, &database, title) catch |err| {
        switch (err) {
            error.TodoNotFound => {
                std.debug.print("Error: Todo '{s}' not found\n", .{title});
                return;
            },
            else => return err,
        }
    };

    if (has_title) {
        try db.updateTodoTitle(&database, res.args.title.?, row.id);
        std.debug.print("Title updated\n", .{});
    }

    if (has_priority) {
        const new_priority = res.args.priority.?;
        if (!std.mem.eql(u8, new_priority, "low") and !std.mem.eql(u8, new_priority, "med") and !std.mem.eql(u8, new_priority, "high")) {
            std.debug.print("Error: Invalid priority '{s}'. Must be low, med, or high\n", .{new_priority});
            return;
        }
        try db.updateTodoPriority(&database, new_priority, row.id);
        std.debug.print("Priority updated\n", .{});
    }

    if (has_tags) {
        var json_list = std.ArrayList([]const u8).init(gpa);
        defer json_list.deinit();
        for (res.args.tags) |tag| {
            try json_list.append(tag);
        }
        const serialized_tags = try std.json.stringifyAlloc(gpa, json_list.items, .{});
        defer gpa.free(serialized_tags);
        try db.updateTodoTags(&database, serialized_tags, row.id);
        std.debug.print("Tags updated\n", .{});
    }

    if (has_no_notify) {
        try db.updateTodoNotify(&database, null, row.id);
        std.debug.print("Notification removed\n", .{});
    } else if (has_notify) {
        const epoch = utils.parseNotifyTime(res.args.notify.?) catch {
            std.debug.print("Error: Invalid notify time '{s}'. Use formats like 30m, 2h, 1d, 9:00am, 14:30\n", .{res.args.notify.?});
            return;
        };
        const notify_str = try utils.formatTimestamp(gpa, epoch);
        defer gpa.free(notify_str);
        try db.updateTodoNotify(&database, notify_str, row.id);
        std.debug.print("Notification updated\n", .{});
    }

    std.debug.print("Todo '{s}' updated\n", .{title});
}

fn todoRm(gpa: std.mem.Allocator, iter: *std.process.ArgIterator) !void {
    const title = iter.next() orelse {
        std.debug.print("Error: No todo title provided. Usage: scrap todo rm \"title\"\n", .{});
        return;
    };

    var database = try db.getDb(gpa);
    defer database.deinit();

    const row = db.getTodo(gpa, &database, title) catch |err| {
        switch (err) {
            error.TodoNotFound => {
                std.debug.print("Error: Todo '{s}' not found\n", .{title});
                return;
            },
            else => return err,
        }
    };

    try db.deleteTodo(&database, row.id);
    std.debug.print("Todo '{s}' removed\n", .{title});
}

fn launchTodoExplorer(gpa: std.mem.Allocator) !void {
    var script_path: []const u8 = undefined;
    var script_owned = false;

    // First try environment variable (for Homebrew installation)
    if (std.process.getEnvVarOwned(gpa, "SCRAP_SCRIPTS_PATH")) |scripts_dir| {
        script_path = try std.fmt.allocPrint(gpa, "{s}/todo_explorer.sh", .{scripts_dir});
        script_owned = true;
        gpa.free(scripts_dir);
    } else |_| {
        // Fallback to relative path (development)
        var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_dir = std.fs.selfExeDirPath(&exe_dir_buf) catch {
            std.debug.print("Failed to get executable directory\n", .{});
            return;
        };
        script_path = try std.fmt.allocPrint(gpa, "{s}/../libexec/scripts/todo_explorer.sh", .{exe_dir});
        script_owned = true;
    }
    defer if (script_owned) gpa.free(script_path);

    var proc = std.process.Child.init(&[_][]const u8{script_path}, gpa);

    if (proc.spawnAndWait()) |_| {} else |err| {
        std.debug.print("Failed to launch todo explorer script: {}, trying fallback...\n", .{err});

        var fallback_proc = std.process.Child.init(&[_][]const u8{"src/scripts/todo_explorer.sh"}, gpa);
        if (fallback_proc.spawnAndWait()) |_| {} else |fallback_err| {
            std.debug.print("Failed to launch todo explorer script: {}\n", .{fallback_err});
            std.debug.print("Make sure todo_explorer.sh exists and is executable\n", .{});
        }
    }
}
