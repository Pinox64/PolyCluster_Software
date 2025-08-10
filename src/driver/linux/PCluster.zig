const std = @import("std");
const common = @import("PClusterCommon");
const PClusterConfig = common.PClusterConfig;
const SystemInformation = common.SystemInformation;
const PCluster = @This();

const Error = error{
    PClusterNotFound,
};

handle: std.fs.File,
connected: bool = false,
config: PClusterConfig,

pub fn init(config: PClusterConfig) !PCluster {
    return PCluster{
        .handle = try openWithHIDRaw(),
        .config = config,
    };
}

pub fn deinit(pcluster: PCluster) void {
    pcluster.handle.close();
}

pub fn openWithHIDRaw() !std.fs.File {
    const cwd = std.fs.cwd();
    var hidraw_dir = try cwd.openDir("/sys/class/hidraw/", .{ .iterate = true });
    defer hidraw_dir.close();
    var hidraw_dir_itterator = hidraw_dir.iterate();

    var buffer: [1024]u8 = undefined;
    while (try hidraw_dir_itterator.next()) |entry| {
        if (entry.kind != .sym_link) continue;
        const dest = try hidraw_dir.readLink(entry.name, &buffer);

        if (std.mem.indexOf(u8, dest, "1A86:FE07") == null) continue;

        const prefix = "/dev/";
        @memcpy(buffer[0..prefix.len], prefix);
        @memcpy(buffer[prefix.len .. prefix.len + entry.name.len], entry.name);
        return try cwd.openFile(buffer[0 .. prefix.len + entry.name.len], .{ .mode = .write_only });
    } else return Error.PClusterNotFound;
}

pub fn writeReport(pcluster: *const PCluster, sys_info: SystemInformation) !void {
    var buffer: [20]u8 = undefined;
    try pcluster.config.writeReport(&buffer, sys_info);
    try pcluster.handle.writeAll(&buffer);
}
