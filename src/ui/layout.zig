const std = @import("std");
const clay = @import("zclay");
const common = @import("PClusterCommon");
const PClusterConfig = common.PClusterConfig;
const rl = @import("raylib");

const global = @import("global.zig");
const pcluster_config = &global.pcluster_config;
const driver_connected = &global.driver_connected;
const pcluster_connected = &global.pcluster_connected;
const system_information = &global.system_information;

const light_grey: clay.Color = .{ 224, 215, 210, 255 };
const red: clay.Color = .{ 168, 66, 28, 255 };
const green: clay.Color = .{ 66, 168, 28, 255 };
const orange: clay.Color = .{ 225, 138, 50, 255 };
const white: clay.Color = .{ 250, 250, 255, 255 };
const black = colorFromHexString("000000") catch unreachable;
const background_color = colorFromHexString("121212") catch unreachable;

const State = struct {
    scroll_delta: rl.Vector2 = undefined,
    mouse_position: rl.Vector2 = undefined,
};

pub var state = State{};

pub fn layout() void {
    clay.UI()(clay.ElementDeclaration{
        .id = .ID("Background"),
        .background_color = background_color,
        .layout = .{
            .direction = .top_to_bottom,
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
                layoutDial(@intCast(i));
            }
        });

        clay.UI()(clay.ElementDeclaration{
            .layout = .{
                .direction = .left_to_right,
                .padding = .all(5),
                .child_gap = 4,
            },
        })({
            const pcluster_config_ptr = pcluster_config.acquire();
            defer pcluster_config.release();
            layoutColorChoosingWidget("Dial", &pcluster_config_ptr.dial);
            layoutColorChoosingWidget("Needle", &pcluster_config_ptr.needle);
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
            layoutStatusDot("Driver", 14, if (driver_connected.get()) green else red);
            layoutStatusDot("PCluster", 14, if (pcluster_connected.get()) green else red);
        });
    });
}

pub fn layoutDial(index: u32) void {
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
                .color = pclusterConfigColorToClayColor(pcluster_config.get().dial),
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
                .background_color = pclusterConfigColorToClayColor(pcluster_config.get().needle),
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
            const onHoverFn = (struct {
                pub fn onHoverFn(element_id: clay.ElementId, pointer_data: clay.PointerData, dial_index: usize) void {
                    std.debug.assert(dial_index < 4);
                    _ = element_id;
                    if (pointer_data.state != .pressed_this_frame) return;
                    const config = pcluster_config.acquire();
                    defer pcluster_config.release();
                    config.displays[dial_index] = config.displays[dial_index].next();
                }
            }).onHoverFn;

            clay.onHover(usize, index, onHoverFn);

            const text = switch (pcluster_config.get().displays[index]) {
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

pub fn layoutStatusDot(text: []const u8, width: f32, color: clay.Color) void {
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
                    .w = .fixed(width),
                    .h = .fixed(width),
                },
            },
            .background_color = color,
            .corner_radius = .all(width / 2),
        })({});
        clay.text(text, .{
            .color = white,
        });
    });
}

pub fn layoutColorChoosingWidget(text: []const u8, current_color: *PClusterConfig.Color) void {
    @setEvalBranchQuota(10000);
    const pure_red = comptime colorFromHexString("ff0000ff") catch unreachable;
    const pure_green = comptime colorFromHexString("00ff00ff") catch unreachable;
    const pure_blue = comptime colorFromHexString("0000ffff") catch unreachable;
    const pure_white = comptime colorFromHexString("ffffffff") catch unreachable;
    const shadow = comptime colorFromHexString("00000050") catch unreachable;

    const incrementU8ByScrollingFn = (struct {
        pub fn incrementU8ByScrollingFn(element_id: clay.ElementId, pointer_data: clay.PointerData, value: *u8) void {
            _ = element_id;
            _ = pointer_data;
            var value_f32: f32 = @floatFromInt(value.*);
            value_f32 += state.scroll_delta.y;
            if (value_f32 <= 0) {
                value.* = 0;
            } else if (value_f32 >= 255) {
                value.* = 255;
            } else {
                value.* = @intFromFloat(value_f32);
            }
        }
    }).incrementU8ByScrollingFn;

    clay.UI()(clay.ElementDeclaration{
        .layout = .{
            .direction = .top_to_bottom,
            .child_gap = 16,
            .padding = .all(4),
            .child_alignment = .{ .x = .center },
        },
        .corner_radius = .all(4),
        .background_color = shadow,
    })({
        clay.UI()(clay.ElementDeclaration{
            .layout = .{
                .child_gap = 4,
                .padding = .all(4),
            },
        })({
            clay.UI()(clay.ElementDeclaration{
                .layout = .{
                    .sizing = .{
                        .w = .fixed(20),
                        .h = .fixed(80),
                    },
                    .child_alignment = .{ .y = .bottom },
                },
                .background_color = shadow,
            })({
                clay.onHover(*u8, &current_color.r, incrementU8ByScrollingFn);
                clay.UI()(clay.ElementDeclaration{
                    .layout = .{
                        .sizing = .{
                            .w = .fixed(20),
                            .h = .fixed(@as(f32, @floatFromInt(current_color.r)) * 79 / 255 + 1),
                        },
                    },
                    .background_color = pure_red,
                })({});
            });

            clay.UI()(clay.ElementDeclaration{
                .layout = .{
                    .sizing = .{
                        .w = .fixed(20),
                        .h = .fixed(80),
                    },
                    .child_alignment = .{ .y = .bottom },
                },
                .background_color = shadow,
            })({
                clay.onHover(*u8, &current_color.g, incrementU8ByScrollingFn);
                clay.UI()(clay.ElementDeclaration{
                    .layout = .{
                        .sizing = .{
                            .w = .fixed(20),
                            .h = .fixed(@as(f32, @floatFromInt(current_color.g)) * 79 / 255 + 1),
                        },
                    },
                    .background_color = pure_green,
                })({});
            });

            clay.UI()(clay.ElementDeclaration{
                .layout = .{
                    .sizing = .{
                        .w = .fixed(20),
                        .h = .fixed(80),
                    },
                    .child_alignment = .{ .y = .bottom },
                },
                .background_color = shadow,
            })({
                clay.onHover(*u8, &current_color.b, incrementU8ByScrollingFn);
                clay.UI()(clay.ElementDeclaration{
                    .layout = .{
                        .sizing = .{
                            .w = .fixed(20),
                            .h = .fixed(@as(f32, @floatFromInt(current_color.b)) * 79 / 255 + 1),
                        },
                    },
                    .background_color = pure_blue,
                })({});
            });

            clay.UI()(clay.ElementDeclaration{
                .layout = .{
                    .sizing = .{
                        .w = .fixed(20),
                        .h = .fixed(80),
                    },
                    .child_alignment = .{ .y = .bottom },
                },
                .background_color = shadow,
            })({
                clay.onHover(*u8, &current_color.brightness, incrementU8ByScrollingFn);
                clay.UI()(clay.ElementDeclaration{
                    .layout = .{
                        .sizing = .{
                            .w = .fixed(20),
                            .h = .fixed(@as(f32, @floatFromInt(current_color.brightness)) * 79 / 255 + 1),
                        },
                    },
                    .background_color = pure_white,
                })({});
            });
        });

        clay.text(text, .{ .color = white });
    });
}

pub fn pclusterConfigColorToClayColor(color: PClusterConfig.Color) clay.Color {
    return .{ @floatFromInt(color.r), @floatFromInt(color.g), @floatFromInt(color.b), @floatFromInt(color.brightness) };
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
