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

var pcluster: Mutexed(PCluster) = .init(PCluster{
    .handle = undefined,
    .config = .default,
});
var sys_info: SystemInformation = .init;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var envmap = try std.process.getEnvMap(allocator);
    defer envmap.deinit();

    {
        const config_path = try common.system.getConfigFilePath(allocator, envmap);
        defer allocator.free(config_path);

        pcluster.acquire().config = PClusterConfig.loadFromPath(config_path) catch |err| blk: {
            if (err != error.ParseZon) {
                return err;
            }

            std.log.err("Parsing the config file failed... Using default config", .{});
            break :blk PClusterConfig.default;
        };
        pcluster.release();
    }

    const controller_connect_thread = try std.Thread.spawn(.{}, connectToControllerTask, .{});
    controller_connect_thread.detach();

    try out_packet_queue.writeItem(.{ .set_pcluster_plugged = false });
    while (true) {
        writeReportToPClusterLoop() catch |e| {
            try out_packet_queue.writeItem(.{ .set_pcluster_plugged = false });
            const seconds_to_wait = 2;
            std.log.err("Error while executing the driver loop: {s}. Retrying in {d} seconds", .{ @errorName(e), seconds_to_wait });
            std.Thread.sleep(std.time.ns_per_s * seconds_to_wait);
        };
    }
}

pub fn writeReportToPClusterLoop() !void {
    {
        const pcluster_ptr = pcluster.acquire();
        defer pcluster.release();
        pcluster_ptr.handle = try PCluster.openWithHIDRaw();
        pcluster_ptr.connected = true;
        try out_packet_queue.writeItem(.{ .set_pcluster_plugged = true });
    }
    defer {
        out_packet_queue.writeItem(.{ .set_pcluster_plugged = false }) catch {};
        pcluster.acquire().connected = false;
        pcluster.release();
    }

    while (true) {
        try sys_info.updateAll();
        for (0..pcluster.get().config.update_period_ms / 20) |_| {
            try pcluster.get().writeReport(sys_info);
            std.Thread.sleep(std.time.ns_per_ms * 20);
        }
    }
}

var out_packet_queue = common.ThreadSafeQueue(protocol.ControllerBoundPacket, 64).init;

pub fn connectToControllerTask() !void {
    var debug_allocator: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    const localhost = comptime std.net.Address.parseIp("127.0.0.1", protocol.default_port) catch unreachable;
    var server = localhost.listen(.{ .reuse_port = true, .reuse_address = true, .kernel_backlog = 1 }) catch |e| {
        std.log.err("Error while starting server: {}, exiting...\n", .{e});
        std.process.exit(1);
    };

    while (true) {
        const client = try server.accept();
        defer client.stream.close();

        out_packet_queue = .init;
        try out_packet_queue.writeItem(.{ .set_pcluster_plugged = pcluster.get().connected });
        const writer_thread = try std.Thread.spawn(.{}, controllerWriteLoop, .{client.stream.writer()});
        defer {
            out_packet_queue.writeItem(.{ .disconnect = {} }) catch {};
            writer_thread.join();
        }

        controllerReadLoop(allocator, client) catch |e| {
            std.log.err("Error while listening configurations from {}: {s}.", .{ client.address, @errorName(e) });
        };
    }
}

fn controllerReadLoop(allocator: Allocator, client: std.net.Server.Connection) !void {
    var buffered_reader = std.io.bufferedReader(client.stream.reader());
    const reader = buffered_reader.reader();

    while (true) {
        const in_packet = try protocol.DriverBoundPacket.read(allocator, reader);
        defer in_packet.deinit(allocator);

        switch (in_packet) {
            .disconnect => return,
            .set_config => |config| {
                pcluster.acquire().config = config;
                pcluster.release();
            },
            .request_protocol_version => try out_packet_queue.writeItem(.{ .request_protocol_version_response = protocol.version }),
            .request_system_information => try out_packet_queue.writeItem(.{ .request_system_information_response = sys_info }),
        }
    }
}

pub fn controllerWriteLoop(unbuffered_writer: anytype) void {
    var buffered_writer = std.io.bufferedWriter(unbuffered_writer);
    const writer = buffered_writer.writer();
    while (true) {
        const packet = out_packet_queue.readItem();

        packet.write(writer) catch return;
        buffered_writer.flush() catch return;

        // Used to end the thread
        if (packet == .disconnect) return;
    }
}
