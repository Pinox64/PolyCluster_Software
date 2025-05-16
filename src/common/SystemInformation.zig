const std = @import("std");
const SystemInformation = @This();

const system = switch (@import("builtin").os.tag) {
    .linux => @import("linux/system.zig"),
    .windows => @import("windows/system.zig"),
    .macos => @import("macos/system.zig"),
    else => @compileError("Not implemented"),
};

cpu_usage_percent: f64,
cpu_temperature_celsius: f64,
memory_usage_percent: f64,

pub const default = SystemInformation{
    .cpu_usage_percent = 0,
    .cpu_temperature_celsius = 0,
    .memory_usage_percent = 0,
};

pub fn updateAll(sys_info: *SystemInformation) !void {
    try sys_info.updateAverageCpuUsagePercent();
    try sys_info.updateCpuTemperatureCelsius();
    try sys_info.updateMemoryUsagePercent();
}

pub fn updateAverageCpuUsagePercent(sys_info: *SystemInformation) !void {
    sys_info.cpu_usage_percent = try system.getAverageCpuUsagePercent();
}

pub fn updateCpuTemperatureCelsius(sys_info: *SystemInformation) !void {
    sys_info.cpu_temperature_celsius = try system.getTemperatureCelsius("x86_pkg_temp");
}

pub fn updateMemoryUsagePercent(sys_info: *SystemInformation) !void {
    sys_info.memory_usage_percent = try system.getMemoryUsagePercent();
}
