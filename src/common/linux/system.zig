const std = @import("std");
// TODO: Change this API's name

pub fn getAverageCpuUsagePercent() !f64 {
    const Static = struct {
        var last_time_user: u64 = 0;
        var last_time_nice: u64 = 0;
        var last_time_system: u64 = 0;
        var last_time_idle: u64 = 0;
        var last_time_iowait: u64 = 0;
        var last_time_irq: u64 = 0;
        var last_time_softirq: u64 = 0;
    };

    var buffer: [32768]u8 = undefined;
    const stat = try std.fs.openFileAbsolute("/proc/stat", .{});
    defer stat.close();
    const bytes_read = try stat.readAll(&buffer);
    var line_itterator = std.mem.tokenizeScalar(u8, buffer[0..bytes_read], '\n');

    while (line_itterator.next()) |line| {
        if (!std.mem.startsWith(u8, line, "cpu ")) continue;
        var it = std.mem.tokenizeScalar(u8, line, ' ');

        _ = it.next(); // will be "cpu ", useless
        const time_user = std.fmt.parseInt(u64, it.next().?, 10) catch unreachable;
        const time_nice = std.fmt.parseInt(u64, it.next().?, 10) catch unreachable;
        const time_system = std.fmt.parseInt(u64, it.next().?, 10) catch unreachable;
        const time_idle = std.fmt.parseInt(u64, it.next().?, 10) catch unreachable;
        const time_iowait = std.fmt.parseInt(u64, it.next().?, 10) catch unreachable;
        const time_irq = std.fmt.parseInt(u64, it.next().?, 10) catch unreachable;
        const time_softirq = std.fmt.parseInt(u64, it.next().?, 10) catch unreachable;
        defer {
            Static.last_time_user = time_user;
            Static.last_time_nice = time_nice;
            Static.last_time_system = time_system;
            Static.last_time_idle = time_idle;
            Static.last_time_iowait = time_iowait;
            Static.last_time_irq = time_irq;
            Static.last_time_softirq = time_softirq;
        }

        const diff_time_user = time_user - Static.last_time_user;
        const diff_time_nice = time_nice - Static.last_time_nice;
        const diff_time_system = time_system - Static.last_time_system;
        const diff_time_idle = time_idle - Static.last_time_idle;
        const diff_time_iowait = time_iowait - Static.last_time_iowait;
        const diff_time_irq = time_irq - Static.last_time_irq;
        const diff_time_softirq = time_softirq - Static.last_time_softirq;

        return 100.0 - @as(f64, @floatFromInt(diff_time_idle * 100)) / @as(f64, @floatFromInt(diff_time_user + diff_time_nice + diff_time_system + diff_time_idle + diff_time_iowait + diff_time_irq + diff_time_softirq));
    }
    unreachable;
}

fn parseIntInString(T: type, s: []const u8) T {
    var index: usize = 0;
    while (index <= s.len and s[index] < '0' or s[index] > '9') : (index += 1) {}

    var int: T = 0;
    while (index <= s.len and s[index] >= '0' and s[index] <= '9') : (index += 1) {
        int *= 10;
        int += s[index] - '0';
    }
    return int;
}

pub fn getMemoryUsagePercent() !f64 {
    var buffer: [32768]u8 = undefined;
    const meminfo = try std.fs.openFileAbsolute("/proc/meminfo", .{});
    defer meminfo.close();
    const bytes_read = try meminfo.readAll(&buffer);
    var line_itterator = std.mem.tokenizeScalar(u8, buffer[0..bytes_read], '\n');

    var line: []const u8 = undefined;
    line = line_itterator.next().?;
    std.debug.assert(std.mem.indexOf(u8, line, "MemTotal: ") != null);
    const mem_total = parseIntInString(u64, line);

    line = line_itterator.next().?;
    std.debug.assert(std.mem.indexOf(u8, line, "MemFree: ") != null);

    line = line_itterator.next().?;
    std.debug.assert(std.mem.indexOf(u8, line, "MemAvailable: ") != null);
    const mem_available = parseIntInString(u64, line);

    return 100 * (1 - @as(f64, @floatFromInt(mem_available)) / @as(f64, @floatFromInt(mem_total)));
}

pub fn getTemperatureCelsius(zone: []const u8) !f64 {
    var thermal_dir = try std.fs.openDirAbsolute("/sys/class/thermal/", .{ .iterate = true });
    defer thermal_dir.close();

    var thermal_dir_iterator = thermal_dir.iterate();
    while (try thermal_dir_iterator.next()) |entry| {
        if (entry.kind != .sym_link) continue;
        if (std.mem.indexOf(u8, entry.name, "zone") == null) continue;
        var dir = try thermal_dir.openDir(entry.name, .{});
        defer dir.close();

        var thermal_zone_type = try dir.openFile("type", .{});
        defer thermal_zone_type.close();

        var buffer: [256]u8 = undefined;
        var read_bytes = try thermal_zone_type.readAll(&buffer);
        if (std.mem.eql(u8, zone, buffer[0 .. read_bytes - 1])) {
            var temperature_file = try dir.openFile("temp", .{});
            defer temperature_file.close();

            read_bytes = try temperature_file.readAll(&buffer);
            return try std.fmt.parseFloat(f64, buffer[0 .. read_bytes - 1]) / 1000;
        }
    }

    // TODO: proper error management
    std.log.err("zone not found.", .{});
    return 0;
}
