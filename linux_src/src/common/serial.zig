const std = @import("std");
const builtin = @import("builtin");

const native_endian = builtin.cpu.arch.endian();

pub fn serialize(data: anytype, writer: anytype, comptime endianness: std.builtin.Endian) !void {
    const T = @TypeOf(data);
    const typeInfoT = @typeInfo(T);
    switch (typeInfoT) {
        .@"enum" => |t| try serialize(@as(t.tag_type, @intFromEnum(data)), writer, endianness),
        .array => inline for (&data) |e| {
            try serialize(e, writer, endianness);
        },
        .pointer => |t| {
            switch (t.size) {
                .one => try serialize(data.*, writer, endianness),
                .slice => {
                    try serialize(@as(u64, data.len), writer, endianness);
                    for (data) |e| {
                        try serialize(e, writer, endianness);
                    }
                },
                .many, .c => @compileError("Many and C style pointers are not supported, try casting to a sentinel or slice"),
            }
        },
        .@"struct" => |t| inline for (t.fields) |field| {
            try serialize(@field(data, field.name), writer, endianness);
        },
        .@"union" => {
            if (typeInfoT.@"union".tag_type == null) @compileError("Union with no tag type not supported");
            try serialize(std.meta.activeTag(data), writer, endianness);
            switch (data) {
                inline else => |e| try serialize(e, writer, endianness),
            }
        },
        .void, .null => {},
        .bool => try writer.writeByte(@intFromBool(data)),
        inline .int, .float => {
            const Int = std.meta.Int(.unsigned, @bitSizeOf(T));
            const bytes = std.mem.toBytes(std.mem.nativeTo(Int, @bitCast(data), endianness));
            try writer.writeAll(&bytes);
        },
        else => @compileError("Type not supported"),
    }
}

/// use deinitDeserializedType on your type if it contained pointers
pub fn deserialize(T: type, allocator: std.mem.Allocator, reader: anytype, comptime endianness: std.builtin.Endian) !T {
    var result: T = undefined;
    const typeInfoT = @typeInfo(T);
    switch (typeInfoT) {
        .@"enum" => |t| {
            const tag = try deserialize(t.tag_type, allocator, reader, endianness);
            result = try std.meta.intToEnum(T, tag);
        },
        .array => |t| inline for (&result) |*e| {
            e.* = try deserialize(t.child, allocator, reader, endianness);
        },
        .pointer => |t| {
            switch (t.size) {
                .one => {
                    const ptr = try allocator.create(t.child);
                    ptr.* = try deserialize(t.child, allocator, reader, endianness);
                    result = ptr;
                },
                .slice => {
                    const length = try deserialize(u64, allocator, reader, endianness);
                    const slice = try allocator.alloc(t.child, length);
                    for (slice) |*e| {
                        e.* = try deserialize(t.child, allocator, reader, endianness);
                    }
                    result = slice;
                },
                .many, .c => @compileError("Many and C pointers are not supported, try casting to a slice"),
            }
        },
        .@"struct" => |t| inline for (t.fields) |field| {
            @field(result, field.name) = try deserialize(field.type, allocator, reader, endianness);
        },
        .@"union" => {
            if (typeInfoT.@"union".tag_type == null) @compileError("Union with no tag type not supported");
            const active_tag = try deserialize(std.meta.Tag(T), allocator, reader, endianness);
            inline for (comptime std.meta.tags(typeInfoT.@"union".tag_type.?)) |tag| {
                if (tag == active_tag) {
                    return @unionInit(T, @tagName(tag), try deserialize(std.meta.TagPayload(T, tag), allocator, reader, endianness));
                }
            }
        },
        .void, .null => {},
        .bool => result = try deserialize(u8, allocator, reader, endianness) == 1,
        inline .int, .float => {
            const raw_bytes = try reader.readBytesNoEof(@sizeOf(T));
            result = std.mem.bytesAsValue(T, &raw_bytes).*;
            if (native_endian != endianness) result = @byteSwap(result);
        },
        else => @compileError("Type not supported"),
    }
    return result;
}

pub fn deinitDeserializedType(deserialized: anytype, allocator: std.mem.Allocator) void {
    const T = @TypeOf(deserialized);
    const typeInfoT = @typeInfo(T);

    switch (typeInfoT) {
        .pointer => |t| {
            switch (t.size) {
                .one => {
                    deinitDeserializedType(deserialized.*, allocator);
                    allocator.destroy(deserialized);
                },
                .slice => {
                    for (deserialized) |e| {
                        deinitDeserializedType(e, allocator);
                    }
                    allocator.free(deserialized);
                },
                .many, .c => @compileError("C style pointers are not supported, try casting to a slice"),
            }
        },
        .array => for (deserialized[0..]) |e| {
            deinitDeserializedType(e, allocator);
        },
        .@"struct" => |t| inline for (t.fields) |field| {
            deinitDeserializedType(@field(deserialized, field.name), allocator);
        },
        .@"union" => {
            if (typeInfoT.@"union".tag_type == null) @compileError("Union with no tag type not supported");
            switch (deserialized) {
                inline else => |e| deinitDeserializedType(e, allocator),
            }
        },
        else => {},
    }
}

test "deserialize/serialize simple" {
    var buffer: [4]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const Data = struct { a: u8 = 0, b: u8 = 16, c: u16 = 22 };
    const data = Data{};

    {
        try serialize(data, stream.writer(), .little);
        const expected_bytes_little_endian = [4]u8{ 0, 16, 22, 0 };
        try std.testing.expectEqual(expected_bytes_little_endian, buffer);
        var deserialize_buffer = std.io.fixedBufferStream(&expected_bytes_little_endian);

        const read_data = try deserialize(Data, std.testing.allocator, deserialize_buffer.reader(), .little);
        defer deinitDeserializedType(read_data, std.testing.allocator);
        try std.testing.expectEqualDeep(data, read_data);
    }

    stream.reset();

    {
        try serialize(data, stream.writer(), .big);
        const expected_bytes_big_endian = [4]u8{ 0, 16, 0, 22 };
        try std.testing.expectEqual(expected_bytes_big_endian, buffer);
        var deserialize_buffer = std.io.fixedBufferStream(&expected_bytes_big_endian);

        const read_data = try deserialize(Data, std.testing.allocator, deserialize_buffer.reader(), .big);
        defer deinitDeserializedType(read_data, std.testing.allocator);
        try std.testing.expectEqualDeep(data, read_data);
    }
}

test "deserialize/serialize more complex" {
    var buffer: [21]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const four: u16 = 4;
    const array = [2]u16{ 5, 6 };
    const Data = struct { a: bool = false, b: [2]u16 = [2]u16{ 1, 2 }, c: enum(u16) { a, b, c, d } = @enumFromInt(3), d: *const u16 = &four, e: []const u16 };
    const data = Data{ .e = &array };

    {
        try serialize(data, stream.writer(), .little);
        const expected_bytes_little_endian = [21]u8{ 0, 1, 0, 2, 0, 3, 0, 4, 0, 2, 0, 0, 0, 0, 0, 0, 0, 5, 0, 6, 0 };
        try std.testing.expectEqual(expected_bytes_little_endian, buffer);
        var deserialize_buffer = std.io.fixedBufferStream(&expected_bytes_little_endian);

        const read_data = try deserialize(Data, std.testing.allocator, deserialize_buffer.reader(), .little);
        defer deinitDeserializedType(read_data, std.testing.allocator);
        try std.testing.expectEqualDeep(data, read_data);
    }

    stream.reset();

    {
        try serialize(data, stream.writer(), .big);
        const expected_bytes_big_endian = [21]u8{ 0, 0, 1, 0, 2, 0, 3, 0, 4, 0, 0, 0, 0, 0, 0, 0, 2, 0, 5, 0, 6 };
        try std.testing.expectEqual(expected_bytes_big_endian, buffer);
        var deserialize_buffer = std.io.fixedBufferStream(&expected_bytes_big_endian);

        const read_data = try deserialize(Data, std.testing.allocator, deserialize_buffer.reader(), .big);
        defer deinitDeserializedType(read_data, std.testing.allocator);
        try std.testing.expectEqualDeep(data, read_data);
    }
}

test "deserialize/serialize tagged union" {
    var buffer: [5]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const Union = union(enum(u8)) {
        field_1: *u32,
        field_2: *u32,
    };
    const data = Union{
        .field_1 = try std.testing.allocator.create(u32),
    };
    data.field_1.* = 257;
    defer std.testing.allocator.destroy(data.field_1);

    {
        try serialize(data, stream.writer(), .little);
        const expected_bytes_little_endian = [5]u8{ 0, 1, 1, 0, 0 };
        try std.testing.expectEqual(expected_bytes_little_endian, buffer);
        var deserialize_buffer = std.io.fixedBufferStream(&expected_bytes_little_endian);

        const read_data = try deserialize(Union, std.testing.allocator, deserialize_buffer.reader(), .little);
        defer deinitDeserializedType(read_data, std.testing.allocator);
        try std.testing.expectEqualDeep(data, read_data);
    }

    stream.reset();

    {
        try serialize(data, stream.writer(), .big);
        const expected_bytes_little_endian = [5]u8{ 0, 0, 0, 1, 1 };
        try std.testing.expectEqual(expected_bytes_little_endian, buffer);
        var deserialize_buffer = std.io.fixedBufferStream(&expected_bytes_little_endian);

        const read_data = try deserialize(Union, std.testing.allocator, deserialize_buffer.reader(), .big);
        defer deinitDeserializedType(read_data, std.testing.allocator);
        try std.testing.expectEqualDeep(data, read_data);
    }
}
