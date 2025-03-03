const std = @import("std");
const sqlite = @import("sqlite");

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
