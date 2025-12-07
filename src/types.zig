const clap = @import("clap");

pub const SubCommands = enum {
    add,
    delete,
    find,
    open,
    editTag,
    help,
};

pub const main_parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
};

pub const main_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<command>
    \\
);

pub const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);