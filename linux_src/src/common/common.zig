pub const serial = @import("serial.zig");
pub const PClusterConfig = @import("PClusterConfig.zig");
pub const SystemInformation = @import("SystemInformation.zig");
pub const Mutexed = @import("Mutexed.zig").Mutexed;
pub const protocol = @import("protocol.zig");
pub const ThreadSafeQueue = @import("ThreadSafeQueue.zig").ThreadSafeQueue;
pub const system = switch (@import("builtin").os.tag) {
    .linux => @import("linux/system.zig"),
    .windows => @import("windows/system.zig"),
    .macos => @import("macos/system.zig"),
    else => @compileError("Not implemented"),
};

test {
    _ = @import("serial.zig");
    _ = @import("PClusterConfig.zig");
    _ = @import("protocol.zig");
}
