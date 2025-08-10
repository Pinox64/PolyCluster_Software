const std = @import("std");
const clay = @import("zclay");
const common = @import("PClusterCommon");
const PClusterConfig = common.PClusterConfig;

const light_grey: clay.Color = .{ 224, 215, 210, 255 };
const red: clay.Color = .{ 168, 66, 28, 255 };
const green: clay.Color = .{ 66, 168, 28, 255 };
const orange: clay.Color = .{ 225, 138, 50, 255 };
const white: clay.Color = .{ 250, 250, 255, 255 };
const black = colorFromHexString("000000") catch unreachable;
const background_color = colorFromHexString("121212") catch unreachable;

pub const State = struct {
    driver_connected: bool,
    pcluster_connected: bool,
    config: PClusterConfig,
};

pub fn layout(state: State) void {
    clay.UI()(clay.ElementDeclaration{
        .id = .ID("Background"),
        .background_color = background_color,
        .layout = .{
            .sizing = .{ .h = .grow, .w = .grow },
            .padding = .all(16),
            .child_alignment = .{
                .x = .center,
                .y = .center,
            },
        },
    })({
        clay.UI()(clay.ElementDeclaration{
            .id = .ID("PCluster"),
            .layout = .{
                .child_gap = 8,
                .padding = .all(30),
            },
            .border = .{
                .color = black,
                .width = .outside(3),
            },
            .corner_radius = .all(130),
            .background_color = .{ 0, 0, 0, 40 },
        })({
            for (0..4) |i| {
                layoutDial(state, @intCast(i));
            }
        });

        clay.UI()(clay.ElementDeclaration{
            .layout = .{
                .sizing = .{
                    .w = .fit,
                    .h = .fit,
                },
                .direction = .top_to_bottom,
                .child_gap = 4,
                .padding = .all(4),
            },
            .floating = .{
                .attach_to = .to_root,
            },
        })({
            clay.UI()(clay.ElementDeclaration{
                .layout = .{
                    .child_alignment = .{
                        .y = .center,
                    },
                    .child_gap = 8,
                },
            })({
                clay.UI()(clay.ElementDeclaration{
                    .layout = .{
                        .sizing = .{
                            .w = .fixed(14),
                            .h = .fixed(14),
                        },
                    },
                    .background_color = if (state.driver_connected) green else red,
                    .corner_radius = .all(7),
                })({});
                clay.text("Driver", .{
                    .color = white,
                });
            });

            clay.UI()(clay.ElementDeclaration{
                .layout = .{
                    .child_alignment = .{
                        .y = .center,
                    },
                    .child_gap = 8,
                },
            })({
                clay.UI()(clay.ElementDeclaration{
                    .layout = .{
                        .sizing = .{
                            .w = .fixed(14),
                            .h = .fixed(14),
                        },
                    },
                    .background_color = if (state.pcluster_connected) green else red,
                    .corner_radius = .all(7),
                })({});
                clay.text("PCluster", .{
                    .color = white,
                });
            });
        });
    });
}

pub fn layoutDial(state: State, index: u32) void {
    const width = 200;
    const height = 200;

    clay.UI()(clay.ElementDeclaration{
        .id = .IDI("Dial", @intCast(index)),
        .layout = .{
            .sizing = .{ .h = .fixed(width), .w = .fixed(height) },
            .direction = .top_to_bottom,
            .child_alignment = .{
                .x = .center,
            },
            .child_gap = 8,
            .padding = .all(8),
        },
        .corner_radius = .all(16),
        // .background_color = .{ 0, 0, 0, 30 },
    })({
        // Numbers
        clay.UI()(clay.ElementDeclaration{
            .layout = .{
                .sizing = .{
                    .w = .fixed(180),
                    .h = .fixed(180),
                },
                .child_alignment = .{
                    .x = .center,
                    .y = .center,
                },
            },
            .corner_radius = .all(90),
            .border = .{
                .color = pclusterConfigColorToClayColor(state.config.dial.color, 255),
                .width = .all(3),
            },
            .background_color = .{ 50, 50, 50, 50 },
        })({
            // Black button over needle
            clay.UI()(clay.ElementDeclaration{
                .floating = .{
                    .zIndex = 1,
                    .attach_to = .to_parent,
                    .attach_points = .{
                        .parent = .center_center,
                        .element = .center_center,
                    },
                },
                .layout = .{
                    .sizing = .{
                        .w = .fixed(40),
                        .h = .fixed(40),
                    },
                },
                .corner_radius = .all(20),
                .background_color = black,
            })({});

            // Needle
            clay.UI()(clay.ElementDeclaration{
                .floating = .{
                    .attach_points = .{ .element = .center_center, .parent = .center_center },
                    .attach_to = .to_parent,
                    .offset = .{
                        .x = -32,
                        .y = 0,
                    },
                },
                .layout = .{
                    .sizing = .{
                        .h = .fixed(6),
                        .w = .fixed(70),
                    },
                },
                .background_color = pclusterConfigColorToClayColor(state.config.needle.color, 255),
            })({});
        });

        // Oled display
        const oled_border_radius = 2;
        clay.UI()(clay.ElementDeclaration{
            .floating = .{
                .attach_to = .to_parent,
                .offset = .{
                    .x = (width - 128) / 2 + oled_border_radius,
                    .y = height - 40 + oled_border_radius,
                },
            },
            .border = .{
                .width = .all(oled_border_radius),
                .color = white,
            },
            .layout = .{
                .sizing = .{
                    .w = .fixed(128),
                    .h = .fixed(32),
                },
                .child_alignment = .{
                    .y = .center,
                    .x = .center,
                },
            },
            .background_color = black,
        })({
            const text = switch (state.config.displays[index]) {
                .off => "",
                .cpu_usage => "CPU %",
                .cpu_temperature => "CPU Temp",
                .mem_usage => "MEM %",
                .gpu_usage => "GPU %",
                .gpu_temperature => "GPU Temp",
                // else => {
                //     std.log.err("Unsupported display information\n", .{});
                //     std.process.exit(1);
                // },
            };

            clay.text(text, .{
                .color = white,
                .font_size = 32,
                .alignement = .center,
            });
        });
    });
}

pub fn pclusterConfigColorToClayColor(color: PClusterConfig.Color, opacity: f32) clay.Color {
    return .{ @floatFromInt(color.r), @floatFromInt(color.g), @floatFromInt(color.b), opacity };
}

pub fn colorFromHexString(str: []const u8) !clay.Color {
    std.debug.assert(str.len == 6 or str.len == 8);
    return clay.Color{
        try std.fmt.parseInt(u8, str[0..2], 16),
        try std.fmt.parseInt(u8, str[2..4], 16),
        try std.fmt.parseInt(u8, str[4..6], 16),
        if (str.len == 6) 0xff else try std.fmt.parseInt(u8, str[6..8], 16),
    };
}

/// If ratio is 0, it returns color1
/// If ratio is 1, it returns color2
pub fn interpolateColors(color1: clay.Color, color2: clay.Color, ratio: f32) clay.Color {
    var color: clay.Color = undefined;
    for (&color1, &color2, &color) |c1, c2, *c3| {
        c3.* = c1 + (c2 - c1) * ratio;
    }
    return color;
}
