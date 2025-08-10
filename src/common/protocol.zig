const std = @import("std");
const PClusterConfig = @import("PClusterConfig.zig");
const SystemInformation = @import("SystemInformation.zig");
const serial = @import("serial.zig");

const Version = struct {
    major: u16,
    minor: u16,
    patch: u16,

    pub fn parse(str: []const u8) !Version {
        var it = std.mem.tokenizeScalar(u8, str, '.');
        var result: Version = undefined;

        result.major = try std.fmt.parseInt(u16, it.next() orelse return error.InvalidVersionString, 10);
        result.minor = try std.fmt.parseInt(u16, it.next() orelse return error.InvalidVersionString, 10);
        result.patch = try std.fmt.parseInt(u16, it.next() orelse return error.InvalidVersionString, 10);

        return result;
    }
};

pub const default_port: u16 = 51423;

// TODO: When zig 0.15.0 is released, expose this directly into @import("builtin")
pub const version = Version.parse("0.1.0") catch unreachable;

pub const ControllerBoundPacket = union(enum(u8)) {
    request_protocol_version_response: Version,
    request_config_response: PClusterConfig,
    request_system_information_response: SystemInformation,

    const methods = PacketMethods(@This());
    pub const write = methods.write;
    pub const read = methods.read;
    pub const deinit = methods.deinit;
};

pub const DriverBoundPacket = union(enum(u8)) {
    request_protocol_version: void,
    request_config: void,
    request_system_information: void,
    set_config: PClusterConfig,

    const methods = PacketMethods(@This());
    pub const write = methods.write;
    pub const read = methods.read;
    pub const deinit = methods.deinit;
};

fn PacketMethods(Packet: type) type {
    return struct {
        pub fn write(packet: Packet, writer: anytype) !void {
            try serial.serialize(packet, writer, .little);
        }

        pub fn read(allocator: std.mem.Allocator, reader: anytype) !Packet {
            return try serial.deserialize(Packet, allocator, reader, .little);
        }

        pub fn deinit(packet: Packet, allocator: std.mem.Allocator) void {
            serial.deinitDeserializedType(packet, allocator);
        }
    };
}

test "request protocol version write and read" {
    var buffer: [128]u8 = undefined;
    const expected_packet = DriverBoundPacket{
        .request_protocol_version = {},
    };

    var stream = std.io.fixedBufferStream(&buffer);
    try expected_packet.write(stream.writer());

    try std.testing.expectEqual(1, stream.pos);
    try std.testing.expectEqual(@intFromEnum(std.meta.activeTag(expected_packet)), buffer[0]);

    stream.pos = 0;
    const read_packet = try DriverBoundPacket.read(std.testing.allocator, stream.reader());
    try std.testing.expectEqualDeep(expected_packet, read_packet);
}

test "set config write and read" {
    var buffer: [128]u8 = undefined;
    const expected_packet = DriverBoundPacket{
        .set_config = .{},
    };

    var stream = std.io.fixedBufferStream(&buffer);
    try expected_packet.write(stream.writer());

    try std.testing.expectEqual(1 + @bitSizeOf(PClusterConfig) / 8, stream.pos);
    try std.testing.expectEqual(@intFromEnum(std.meta.activeTag(expected_packet)), buffer[0]);

    stream.pos = 0;
    const read_packet = try DriverBoundPacket.read(std.testing.allocator, stream.reader());
    try std.testing.expectEqualDeep(expected_packet, read_packet);
}
