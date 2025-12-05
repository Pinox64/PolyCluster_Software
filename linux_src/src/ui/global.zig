const common = @import("PClusterCommon");
const PClusterConfig = common.PClusterConfig;
const SystemInformation = common.SystemInformation;

pub var pcluster_config = common.Mutexed(PClusterConfig).init(.default);
pub var driver_connected = common.Mutexed(bool).init(false);
pub var pcluster_connected = common.Mutexed(bool).init(false);
pub var system_information = common.Mutexed(SystemInformation).init(.init);
