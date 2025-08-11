const std = @import("std");
const Allocator = std.mem.Allocator;
const PClusterConfig = @This();
const SystemInformation = @import("SystemInformation.zig");
const serial = @import("serial.zig");

const Error = error{
    SystemInformationNotSupported,
};

pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

pub const DisplayInfo = enum(u8) {
    off = 0,
    cpu_usage = 1,
    cpu_temperature = 2,
    mem_usage = 3,
    gpu_usage = 4,
    gpu_temperature = 5,

    pub fn next(info: DisplayInfo) DisplayInfo {
        var val: u8 = @intFromEnum(info);
        val += 1;
        if (val > @intFromEnum(DisplayInfo.gpu_temperature)) val = 0;
        return @enumFromInt(val);
    }
};

pub const LEDMode = enum(u8) {
    solid = 1,
};

pub const Dial = struct {
    brightness: u8 = 100,
    color: Color = .{},
};

pub const Needle = struct {
    brightness: u8 = 100,
    color: Color = .{},
};

displays: [4]DisplayInfo = @splat(.off),
led_mode: LEDMode = .solid,
dial: Dial = .{},
needle: Needle = .{},
update_period_ms: u64 = 3000,

pub const default = PClusterConfig{
    .displays = [4]DisplayInfo{ .cpu_usage, .cpu_temperature, .mem_usage, .off },
    .led_mode = .solid,
    .dial = .{ .brightness = 100, .color = .{ .r = 0, .g = 0, .b = 255 } },
    .needle = .{ .brightness = 100, .color = .{ .r = 0, .g = 255, .b = 0 } },
};

pub fn loadFromReader(allocator: Allocator, reader: anytype) !PClusterConfig {
    var bytes = std.ArrayList(u8).init(allocator);
    defer bytes.deinit();

    try reader.readAllArrayList(&bytes, 8192);
    const null_terminated_bytes: [:0]u8 = @ptrCast(bytes.items);

    var status = std.zon.parse.Status{};
    defer status.deinit(allocator);
    return std.zon.parse.fromSlice(PClusterConfig, allocator, null_terminated_bytes, &status, .{}) catch |err| {
        if (err == error.ParseZon) {
            std.log.info("Config file at {}", .{status});
        }

        return err;
    };
}

pub fn saveToWriter(pcluster_config: PClusterConfig, writer: anytype) !void {
    return std.zon.stringify.serialize(pcluster_config, .{}, writer);
}

pub fn writeReport(pcluster_config: *const PClusterConfig, buffer: *[20]u8, info: SystemInformation) !void {
    var stream = std.io.fixedBufferStream(buffer);
    var writer = stream.writer();
    writer.writeByte(0) catch unreachable;
    writer.writeByte(64) catch unreachable;
    writer.writeByte(0) catch unreachable;

    // TODO: a function that can serialize any type and write to a writer?
    for (pcluster_config.displays) |display_info| {
        writer.writeByte(@intFromEnum(display_info)) catch unreachable;
        const byte: u8 = switch (display_info) {
            .off => 0,
            .cpu_usage => @intFromFloat(@round(info.cpu_usage_percent)),
            .cpu_temperature => @intFromFloat(@round(info.cpu_temperature_celsius)),
            .mem_usage => @intFromFloat(@round(info.memory_usage_percent)),
            else => return Error.SystemInformationNotSupported,
        };
        writer.writeByte(byte) catch unreachable;
    }
    writer.writeByte(@intFromEnum(pcluster_config.led_mode)) catch unreachable;
    writer.writeByte(pcluster_config.dial.brightness) catch unreachable;
    writer.writeByte(pcluster_config.dial.color.r) catch unreachable;
    writer.writeByte(pcluster_config.dial.color.g) catch unreachable;
    writer.writeByte(pcluster_config.dial.color.b) catch unreachable;
    writer.writeByte(pcluster_config.needle.brightness) catch unreachable;
    writer.writeByte(pcluster_config.needle.color.r) catch unreachable;
    writer.writeByte(pcluster_config.needle.color.g) catch unreachable;
    writer.writeByte(pcluster_config.needle.color.b) catch unreachable;
}

pub fn readFrom(reader: anytype) !PClusterConfig {
    // Passing undefined for the allocator is safe because there's dynamic data in PClusterConfig
    return try serial.deserialize(PClusterConfig, undefined, reader, .little);
}

pub fn writeTo(config: PClusterConfig, writer: anytype) !void {
    // INFO: Instead of using serial, use std.zig.zon.stringify.serialize instead? Use compression ?
    try serial.serialize(config, writer, .little);
}

test "report bytes" {
    const config = PClusterConfig{
        .displays = [4]PClusterConfig.DisplayInfo{ .cpu_usage, .cpu_temperature, .mem_usage, .off },
        .led_mode = .solid,
        .dial = .{ .brightness = 100, .color = .{ .r = 0, .g = 0, .b = 255 } },
        .needle = .{ .brightness = 100, .color = .{ .r = 0, .g = 255, .b = 0 } },
    };

    const info = SystemInformation{
        .cpu_usage_percent = 20,
        .cpu_temperature_celsius = 30,
        .memory_usage_percent = 40,
    };
    const expected_report_bytes = [20]u8{ //
        0, 64, 0, // prefix
        @intFromEnum(config.displays[0]), @intFromFloat(info.cpu_usage_percent), // DisplayInfo 1
        @intFromEnum(config.displays[1]), @intFromFloat(info.cpu_temperature_celsius), // DisplayInfo 2
        @intFromEnum(config.displays[2]), @intFromFloat(info.memory_usage_percent), // DisplayInfo 3
        @intFromEnum(config.displays[3]), 0, // DisplayInfo 4
        @intFromEnum(config.led_mode), //

        config.dial.brightness,
        config.dial.color.r,
        config.dial.color.g,
        config.dial.color.b,
        config.needle.brightness,
        config.needle.color.r,
        config.needle.color.g,
        config.needle.color.b,
    };

    var buffer: [20]u8 = undefined;
    try config.writeReport(&buffer, info);

    try std.testing.expectEqual(expected_report_bytes, buffer);
}

test "report SystemInformationNotSupported error" {
    const config = PClusterConfig{
        .displays = [4]PClusterConfig.DisplayInfo{ .cpu_usage, .cpu_temperature, .mem_usage, @enumFromInt(255) },
    };
    const info: SystemInformation = .init;

    var buffer: [20]u8 = undefined;
    try std.testing.expectError(Error.SystemInformationNotSupported, config.writeReport(&buffer, info));
}

test "read/write config" {
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const config = PClusterConfig.default;

    try config.writeTo(stream.writer());
    stream.pos = 0;
    const read_config = try PClusterConfig.readFrom(stream.reader());
    try std.testing.expectEqualDeep(config, read_config);
}
