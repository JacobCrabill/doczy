const std = @import("std");
const zap = @import("zap");
const zd = @import("zigdown");

const style_css = @embedFile("style.css");

const Allocator = std.mem.Allocator;

pub const Self = @This();

alloc: Allocator = undefined,
ep: zap.Endpoint = undefined,
root_dir: std.fs.Dir = undefined,

pub const error_page =
    \\<html><body>
    \\  <link rel="stylesheet" href="/style.css">
    \\  <h1>Apologies! An error occurred</h1>
    \\  <p>
    \\    Email
    \\    <a href="mailto:info@flow-state.photos">info@flow-state.photos</a>
    \\    for assistance
    \\  </p>
    \\  <h2><a href=/index.html>Return to home</a></h2>
    \\</body></html>
;

pub fn init(
    a: std.mem.Allocator,
    user_path: []const u8,
    root_dir: std.fs.Dir,
) Self {
    return .{
        .alloc = a,
        .root_dir = root_dir,
        .ep = zap.Endpoint.init(.{
            .path = user_path,
            .get = renderMarkdown,
            // .post = postUser,
            // .put = putUser,
            // .patch = putUser,
            // .delete = deleteUser,
            // .options = optionsUser,
        }),
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn endpoint(self: *Self) *zap.Endpoint {
    return &self.ep;
}

/// Render a Markdown file under "/markdown" to HTML
pub fn renderMarkdown(e: *zap.Endpoint, r: zap.Request) void {
    const self: *Self = @fieldParentPtr("ep", e);

    const path = r.path orelse {
        r.setStatus(.internal_server_error);
        r.sendBody(error_page) catch return;
        return;
    };

    if (!std.mem.endsWith(u8, path, ".md")) {
        // r.setStatus(.internal_server_error);
        // r.sendBody(error_page) catch return;
        // std.debug.print("Not a Markdown file: {s}\n", .{path});
        return;
    }

    const md_html = self.render_file(path) orelse {
        r.setStatus(.internal_server_error);
        r.sendBody(error_page) catch return;
        return;
    };
    defer self.alloc.free(md_html);

    const body_template =
        \\<html><body>
        \\  <style>{s}</style>
        \\  {s}
        \\  <h2><a href=/index.html>Return to home</a></h2>
        \\</body></html>
    ;
    const body = std.fmt.allocPrint(self.alloc, body_template, .{ style_css, md_html }) catch unreachable;
    r.setStatus(.created);
    r.sendBody(body) catch return;
}

fn render_file(self: Self, path: []const u8) ?[]const u8 {
    // Determine the file to open - Should look like "/markdown/some_file.md"
    const prefix = "/";
    std.debug.assert(std.mem.startsWith(u8, path, prefix));

    if (path.len <= prefix.len + 1)
        return null;

    const sub_path = path[prefix.len..];

    // Open file
    // TODO: Share site config around
    var file: std.fs.File = self.root_dir.openFile(sub_path, .{ .mode = .read_only }) catch |err| {
        std.log.err("Error opening markdown file {s}: {any}", .{ sub_path, err });
        return null;
    };
    defer file.close();

    const md_text = file.readToEndAlloc(self.alloc, 1_000_000) catch |err| {
        std.log.err("Error reading file: {any}", .{err});
        return null;
    };
    defer self.alloc.free(md_text);

    // Parse page
    var parser: zd.Parser = zd.Parser.init(self.alloc, .{ .copy_input = false, .verbose = false });
    defer parser.deinit();

    parser.parseMarkdown(md_text) catch |err| {
        std.log.err("Error parsing markdown file: {any}", .{err});
        return null;
    };

    // Create the output buffe catch returnr
    var buf = std.ArrayList(u8).init(self.alloc);
    defer buf.deinit();

    // Render slide
    var h_renderer = zd.htmlRenderer(buf.writer(), self.alloc);
    defer h_renderer.deinit();

    h_renderer.renderBlock(parser.document) catch |err| {
        std.log.err("Error rendering HTML from markdown: {any}", .{err});
        return null;
    };

    return buf.toOwnedSlice() catch return null;
}
