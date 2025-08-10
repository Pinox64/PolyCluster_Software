const std = @import("std");
const Allocator = std.mem.Allocator;
const common = @import("PClusterCommon");
const PClusterConfig = common.PClusterConfig;
const SystemInformation = common.SystemInformation;
const protocol = common.protocol;
const Mutexed = common.Mutexed;

const PCluster = switch (@import("builtin").os.tag) {
    .linux => @import("linux/PCluster.zig"),
    .windows => @import("windows/PCluster.zig"),
    .macos => @import("macos/PCluster.zig"),
    else => @compileError("Not implemented"),
};

var pcluster: Mutexed(PCluster) = undefined;
var sys_info: SystemInformation = .init;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var envmap = try std.process.getEnvMap(allocator);
    defer envmap.deinit();

    {
        const file = try common.system.getConfigFile(envmap);
        defer file.close();
        pcluster.acquire().config = PClusterConfig.loadFromReader(allocator, file.reader()) catch |err| blk: {
            if (err != error.ParseZon) {
                return err;
            }

            std.log.err("Parsing the config file failed... Using default config", .{});
            break :blk PClusterConfig.default;
        };
        pcluster.release();
    }

    const config_listener_thread = try std.Thread.spawn(.{}, configUpdaterTask, .{allocator});
    defer config_listener_thread.detach();

    while (true) {
        driverLoop() catch |e| {
            std.log.err("Error while executing the driver loop: {s}. Retrying in 2 seconds", .{@errorName(e)});
            std.Thread.sleep(std.time.ns_per_s * 2);
        };
    }
}

pub fn driverLoop() !void {
    pcluster = .init(try .init(.default));

    while (true) {
        try sys_info.updateAll();
        for (0..20) |_| {
            try pcluster.get().writeReport(sys_info);
            std.Thread.sleep(std.time.ns_per_ms * 10);
        }
        std.Thread.sleep(std.time.ns_per_ms * pcluster.get().config.update_period_ms);
    }
}

pub fn configUpdaterTask(allocator: Allocator) !void {
    const localhost = comptime std.net.Address.parseIp("127.0.0.1", protocol.default_port) catch unreachable;
    var server = localhost.listen(.{ .reuse_port = true, .reuse_address = true, .kernel_backlog = 1 }) catch |e| {
        std.log.err("Error while starting server: {}, exiting...\n", .{e});
        std.process.exit(1);
    };

    while (true) {
        const client = try server.accept();
        defer client.stream.close();

        configUpdaterLoop(allocator, client) catch |e| {
            std.log.err("Error while listening configurations from {}: {s}.", .{ client.address, @errorName(e) });
        };
    }
}

fn configUpdaterLoop(allocator: Allocator, client: std.net.Server.Connection) !void {
    var buffered_writer = std.io.bufferedWriter(client.stream.writer());
    var buffered_reader = std.io.bufferedReader(client.stream.reader());
    const writer = buffered_writer.writer();
    const reader = buffered_reader.reader();

    while (true) {
        const in_packet = try protocol.DriverBoundPacket.read(allocator, reader);
        defer in_packet.deinit(allocator);

        var out_packet: protocol.ControllerBoundPacket = undefined;

        switch (in_packet) {
            .disconnect => return,
            .set_config => |config| {
                pcluster.acquire().config = config;
                pcluster.release();
            },
            .request_protocol_version => {
                out_packet = .{ .request_protocol_version_response = protocol.version };
                try out_packet.write(writer);
            },
            .request_system_information => {
                out_packet = .{ .request_system_information_response = sys_info };
                try out_packet.write(writer);
            },
        }

        try buffered_writer.flush();
    }
}
