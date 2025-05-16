const std = @import("std");
const common = @import("PClusterCommon");
const PClusterConfig = common.PClusterConfig;
const PCluster = @This();

pub fn init(data: PClusterConfig) !PCluster {
    _ = data;
    @compileError("Not implemented");
}

pub fn deinit(pcluster: PCluster) void {
    _ = pcluster;
    @compileError("Not implemented");
}

pub fn updateData(pcluster: *PCluster) !void {
    _ = pcluster;
    @compileError("Not implemented");
}

pub fn writeReport(pcluster: *const PCluster) !void {
    _ = pcluster;
    @compileError("Not implemented");
}
