const std = @import("std");

pub fn ThreadSafeQueue(T: type, comptime size: usize) type {
    return struct {
        const Queue = @This();
        queue: std.fifo.LinearFifo(T, .{ .Static = size }),
        sema: std.Thread.Semaphore = .{},
        mutex: std.Thread.Mutex = .{},

        pub const init = Queue{ .queue = .init() };

        pub fn writeItem(queue: *Queue, t: T) void {
            queue.mutex.lock();
            defer queue.mutex.unlock();

            if (queue.queue.count == size) queue.queue.discard(1);

            queue.queue.writeItem(t) catch unreachable;
            queue.sema.post();
        }

        pub fn readItem(queue: *Queue) T {
            queue.sema.wait();
            queue.mutex.lock();
            defer queue.mutex.unlock();
            return queue.queue.readItem().?;
        }
    };
}
