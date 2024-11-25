const std = @import("std");
const zd = @import("zigdown");
const zap = @import("zap");
const md = @import("markdown.zig");

const flags = zd.flags; // Flags dependency inherited from Zigdown

const os = std.os;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Dir = std.fs.Dir;
const File = std.fs.File;

fn print_usage() void {
    const stdout = std.io.getStdOut().writer();
    flags.help.printUsage(Doczy, null, 85, stdout) catch unreachable;
}

/// HTTP Request handler
fn on_request(r: zap.Request) void {
    if (r.path) |path| {
        std.log.info("PATH: {s}", .{path});
    }

    if (r.query) |query| {
        std.log.debug("QUERY: {s}", .{query});
    }

    if (r.body) |body| {
        std.log.debug("BODY: {s}", .{body});
    }

    r.setStatus(.not_found);
    r.sendBody("<html><body><h1>404 - File not found</h1></body></html>") catch return;
}

/// Command-line arguments definition for the Flags module
const Doczy = struct {
    pub const description = "Quickly view a tree of Markdown files in the browser";

    pub const descriptions = .{
        .root_file =
        \\The root file of the documentation.
        \\If no root file is given, a table of contents of all Markdown files
        \\found in the root directory will be displayed instead.
        ,
        .root_directory =
        \\The root directory of the documentation.
        \\All paths will either be relative to this directory, or relative to the
        \\directory of the current file.
        ,
    };

    root_file: ?[]const u8 = null,
    root_directory: ?[]const u8 = null,

    pub const switches = .{
        .root_file = 'f',
        .root_directory = 'd',
    };
};

const Source = struct {
    dir: Dir = undefined,
    dir_path: []const u8 = undefined,
    file: ?[]const u8 = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    const params = flags.parse(&args, Doczy, .{}) catch std.process.exit(1);

    var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

    var source: Source = .{};

    if (params.root_file == null and params.root_directory == null) {
        source.dir = std.fs.cwd();
    } else if (params.root_directory) |dir| {
        source.dir = try std.fs.cwd().openDir(dir, .{ .iterate = true });
    } else if (params.root_file) |file| {
        source.file = file;
        const abs_file = try std.fs.realpath(file, &path_buf);
        const root_dir_path = std.fs.path.dirname(abs_file) orelse return error.DirectoryNotFound;
        source.dir_path = root_dir_path;
        source.dir = try std.fs.openDirAbsolute(root_dir_path, .{ .iterate = true });
    }

    // Start the server
    var listener = zap.Endpoint.Listener.init(
        alloc,
        .{
            .port = 8000,
            .on_request = on_request,
            .public_folder = source.dir_path,
            .log = true,
            .max_clients = 1000,
            .max_body_size = 100 * 1024 * 1024,
        },
    );
    defer listener.deinit();

    var ep_markdown = @import("markdown.zig").init(alloc, "/", source.dir);
    defer ep_markdown.deinit();

    // register endpoints with the listener
    try listener.register(ep_markdown.endpoint());

    try listener.listen();

    std.log.info("Listening on 0.0.0.0:8000", .{});

    const t = try std.Thread.spawn(.{}, serve, .{});
    defer t.join();

    if (source.file) |file| {
        const url = try std.fmt.allocPrint(alloc, "http://localhost:8000/{s}", .{file});
        defer alloc.free(url);
        const argv = &[_][]const u8{ "xdg-open", url };
        var proc = std.process.Child.init(argv, alloc);
        try proc.spawn();
    }
}

fn serve() void {
    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}

/// Load all *.md files in the given directory; append their absolute paths to the 'slides' array
/// dir:     The directory to search
/// recurse: If true, also recursively search all child directories of 'dir'
/// slides:  The array to append all slide filenames to
fn loadSlidesFromDirectory(alloc: Allocator, dir: Dir, recurse: bool, slides: *ArrayList([]const u8)) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .file => {
                var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
                const realpath = dir.realpath(entry.name, &path_buf) catch |err| {
                    std.debug.print("Error loading slide: {s}\n", .{entry.name});
                    return err;
                };
                if (std.mem.eql(u8, ".md", std.fs.path.extension(realpath))) {
                    std.debug.print("Adding slide: {s}\n", .{realpath});
                    const slide: []const u8 = try alloc.dupe(u8, realpath);
                    try slides.append(slide);
                }
            },
            .directory => {
                if (recurse) {
                    const child_dir: Dir = try dir.openDir(entry.name, .{ .iterate = true });
                    try loadSlidesFromDirectory(alloc, child_dir, recurse, slides);
                }
            },
            else => {},
        }
    }
}

/// Load a list of slides to present from a single text file
fn loadSlidesFromFile(alloc: Allocator, dir: Dir, file: File, slides: *ArrayList([]const u8)) !void {
    const buf = try file.readToEndAlloc(alloc, 1_000_000);
    defer alloc.free(buf);

    var lines = std.mem.split(u8, buf, "\n");
    while (lines.next()) |name| {
        if (name.len < 1) break;

        var path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const realpath = dir.realpath(name, &path_buf) catch |err| {
            std.debug.print("Error loading slide: {s}\n", .{name});
            return err;
        };
        if (std.mem.eql(u8, ".md", std.fs.path.extension(realpath))) {
            std.debug.print("Adding slide: {s}\n", .{realpath});
            const slide: []const u8 = try alloc.dupe(u8, realpath);
            try slides.append(slide);
        }
    }
}
