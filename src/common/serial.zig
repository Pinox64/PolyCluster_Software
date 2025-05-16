const std = @import("std");

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
        .void, .null => {},
        .bool => try writer.writeByte(@intFromBool(data)),
        inline .int, .float, .@"union" => {
            const bytes = std.mem.toBytes(std.mem.nativeTo(T, data, endianness));
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
        .@"enum" => |t| result = @enumFromInt(try deserialize(t.tag_type, allocator, reader, endianness)),
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
        .void, .null => {},
        .bool => result = try deserialize(u8, allocator, reader, endianness) == 1,
        inline .int, .float, .@"union" => {
            // TODO: Find a fix because @sizeOf is platform specific
            // users wont be able to share configs in their binary form
            const raw_bytes = try reader.readBytesNoEof(@sizeOf(T));
            result = std.mem.toNative(T, @bitCast(raw_bytes), endianness);
        },
        else => @compileError("Type not supported"),
    }
    return result;
}

pub fn deinitDeserializedType(deserialized: anytype, allocator: std.mem.Allocator) void {
    const T = @TypeOf(deserialized);
    const typeInfo = @typeInfo(T);

    switch (typeInfo) {
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
