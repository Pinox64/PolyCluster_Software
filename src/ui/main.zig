const std = @import("std");
const clay = @import("zclay");
const rl = @import("raylib");
const common = @import("PClusterCommon");
const protocol = common.protocol;
const PClusterConfig = common.PClusterConfig;
const layout = @import("layout.zig");
const renderer = @import("raylib_render_clay.zig");

var pcluster_config = common.Mutexed(PClusterConfig).init(.default);
var driver_connected = common.Mutexed(bool).init(false);
var pcluster_connected = common.Mutexed(bool).init(false);

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{ .thread_safe = true }) = .init;
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    var driver_connection_thread = try std.Thread.spawn(.{}, connectionWithDriverTask, .{allocator});
    defer driver_connection_thread.detach();

    const clay_memory = try allocator.alloc(u8, clay.minMemorySize());
    defer allocator.free(clay_memory);

    const clay_arena = clay.createArenaWithCapacityAndMemory(clay_memory);
    _ = clay.initialize(clay_arena, .{ .w = 1280, .h = 720 }, .{});
    clay.setMeasureTextFunction(void, {}, renderer.measureText);

    rl.setConfigFlags(.{
        .msaa_4x_hint = true,
        .window_resizable = true,
    });
    rl.initWindow(1280, 720, "PCluster controll software");
    defer rl.closeWindow();
    rl.setTargetFPS(20);

    try renderer.loadFont(@embedFile("fonts/RobotoMono-Medium.ttf"), 0, 24);

    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(.escape)) break;
        if (rl.isKeyPressed(.d)) clay.setDebugModeEnabled(!clay.isDebugModeEnabled());

        const mouse_position = rl.getMousePosition();
        clay.setPointerState(.{
            .x = mouse_position.x,
            .y = mouse_position.y,
        }, rl.isMouseButtonDown(.left));

        const scroll_delta = rl.getMouseWheelMoveV().multiply(.{ .x = 6, .y = 6 });
        clay.updateScrollContainers(
            false,
            .{ .x = scroll_delta.x, .y = scroll_delta.y },
            rl.getFrameTime(),
        );

        clay.setLayoutDimensions(.{
            .w = @floatFromInt(rl.getScreenWidth()),
            .h = @floatFromInt(rl.getScreenHeight()),
        });

        var timer = try std.time.Timer.start();
        const layout_state = layout.State{
            .driver_connected = driver_connected.get(),
            .pcluster_connected = pcluster_connected.get(),
            .config = pcluster_config.get(),
        };

        clay.beginLayout();
        layout.layout(layout_state);
        var render_commands = clay.endLayout();
        const ns = timer.lap();
        _ = ns;
        // std.debug.print("clay layout time: {d}us\n", .{ns / std.time.ns_per_us});

        rl.beginDrawing();
        try renderer.clayRaylibRender(&render_commands, allocator);
        rl.endDrawing();
    }
}

pub fn connectionWithDriverTask(allocator: std.mem.Allocator) void {
    while (true) {
        defer std.Thread.sleep(std.time.ns_per_ms * 100);

        const conn = std.net.tcpConnectToHost(allocator, "127.0.0.1", protocol.default_port) catch continue;
        defer conn.close();

        const writer = conn.writer();
        const reader = conn.reader();

        driver_connected.set(true);
        defer driver_connected.set(false);

        // TODO: State machine to handle logic
        while (true) {
            const out_packet = protocol.DriverBoundPacket{
                .request_protocol_version = {},
            };
            out_packet.write(writer) catch break;

            const in_packet = protocol.ControllerBoundPacket.read(allocator, reader) catch break;
            defer in_packet.deinit(allocator);
            std.debug.assert(in_packet == .request_protocol_version_response);

            std.Thread.sleep(std.time.ns_per_s * 10000);
        }
    }
}
