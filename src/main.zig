const std = @import("std");
const Allocator = std.mem.Allocator;

const EntryKind = enum {
    FILE,
    DIR,
    OTHER,
};

const Entry = struct {
    name: []const u8,
    kind: std.fs.File.Kind,
};

const CreateEnum = enum {
    FILE,
    DIR,
};

const blue_color = "\x1b[34m";
const green_color = "\x1b[32m";
const red_color = "\x1b[31m";
const reset_color = "\x1b[0m";

const stdout = std.io.getStdOut().writer();

// for commands handling
const Commands = struct {
    list: @TypeOf(listCommand),
    create: @TypeOf(createCommand),
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sample = Commands{
        .list = listCommand,
        .create = createCommand,
    };
    try commandsHandler(Commands, sample, allocator);
}

fn commandsHandler(comptime T: type, sample: T, allocator: Allocator) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        // TODO add help field to struct
        try stdout.print("error: Insufficient number of arguments, must provide command.\n", .{});
        return;
    }

    const command = args[1];

    const struct_info = @typeInfo(T);
    inline for (struct_info.Struct.fields) |field| {
        // std.debug.print("{s} {s}\n", .{ field.name, command });
        if (std.mem.eql(u8, field.name, command)) {
            const function = @field(sample, field.name);
            try function(allocator, args);
            return;
        }
    }

    try stdout.print("Undefined command.", .{});
}

fn listCommand(allocator: Allocator, args: [][]u8) !void {
    _ = args;

    const list = try getEntries(allocator);
    defer list.deinit();

    for (list.items) |entry| {
        const Kind = std.fs.File.Kind;
        switch (entry.kind) {
            Kind.directory => {
                try stdout.print("{s}", .{blue_color});
            },
            Kind.sym_link => {
                try stdout.print("{s}", .{green_color});
            },
            else => {},
        }

        try stdout.print("{s}{s}\n", .{ entry.name, reset_color });
    }
}

fn createCommand(allocator: Allocator, args: [][]u8) !void {
    _ = allocator;
    if (args.len < 3) {
        try stdout.print("Please provide filename.\n", .{});
        return;
    }
    const filename = args[2];
    const kind = if (std.mem.endsWith(u8, filename, "/")) CreateEnum.DIR else CreateEnum.FILE;

    switch (kind) {
        .FILE => {
            const f = std.fs.cwd().createFile(filename, .{ .exclusive = true }) catch |err| switch (err) {
                error.AccessDenied => {
                    try stdout.print("Access denied, cannot create file.\n", .{});
                    return;
                },
                error.BadPathName => {
                    try stdout.print("Filename cannot contain one of these characters: '/', '*', '?', '\"', '<', '>', '|'\n", .{});
                    return;
                },
                error.PathAlreadyExists => {
                    try stdout.print("File already exists.\n", .{});
                    return;
                },
                else => {
                    try stdout.print("Failed to create dir.\n", .{});
                    return;
                },
            };
            defer f.close();
        },
        .DIR => {
            std.fs.cwd().makeDir(filename) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    try stdout.print("Path already exists.\n", .{});
                    return;
                },
                error.ReadOnlyFileSystem => {
                    try stdout.print("Cannot write on read-only filesystem.\n", .{});
                    return;
                },
                else => {
                    try stdout.print("Failed to create dir.\n", .{});
                    return;
                },
            };
        },
    }
}

fn getEntries(allocator: Allocator) !std.ArrayListAligned(Entry, null) {
    var list = std.ArrayList(Entry).init(allocator);

    var i_dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer i_dir.close();

    var iterator = i_dir.iterate();
    while (try iterator.next()) |path| {
        try list.append(.{
            .name = path.name,
            .kind = path.kind,
        });
    }

    return list;
}
