const std = @import("std");

// For ease of use
pub fn mutexed(e: anytype) Mutexed(@TypeOf(e)) {
    return Mutexed(@TypeOf(e)).init(e);
}

pub fn Mutexed(T: type) type {
    return struct {
        const Self = @This();

        mutex: std.Thread.Mutex,
        value: T,

        pub fn init(value: T) Self {
            return Self{
                .mutex = .{},
                .value = value,
            };
        }

        pub fn acquire(self: *Self) *T {
            self.mutex.lock();
            return &self.value;
        }

        pub fn release(self: *Self) void {
            self.mutex.unlock();
        }

        pub fn get(self: *Self) T {
            const value = self.acquire().*;
            self.release();
            return value;
        }

        pub fn set(self: *Self, value: T) void {
            self.acquire().* = value;
            self.release();
        }
    };
}
