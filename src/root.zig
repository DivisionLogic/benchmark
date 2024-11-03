const std = @import("std");
const assert = std.debug.assert;
const time = std.time;
const info = @import("logger").info;
const TypeInfo = @import("builtin").TypeInfo;
const Timer = time.Timer;

const BenchFn = fn (*Context) void;

pub const Context = struct {
    timer: Timer,
    run_timer: Timer,
    iter: u32,
    count: u32,
    state: State,
    nanoseconds: u64,

    const HeatingTime = time.ns_per_s;
    const RunTime = time.ns_per_s;

    const State = enum {
        None,
        Heating,
        Running,
        Finished,
    };

    pub fn init() Context {
        return Context{ .timer = Timer.start() catch unreachable, .run_timer = Timer.start() catch unreachable, .iter = 0, .count = 0, .state = .None, .nanoseconds = 0 };
    }

    pub fn run(self: *Context) bool {
        switch (self.state) {
            .None => {
                self.state = .Heating;
                self.timer.reset();
                self.run_timer.reset();
                return true;
            },
            .Heating => {
                self.count += 1;
                const elapsed = self.run_timer.read();
                if (elapsed >= HeatingTime) {
                    // Caches should be hot
                    self.count = @as(u32, @intCast(RunTime / (HeatingTime / self.count)));
                    self.state = .Running;
                    self.timer.reset();
                }

                return true;
            },
            .Running => {
                if (self.iter < self.count) {
                    self.iter += 1;
                    return true;
                } else {
                    self.nanoseconds = self.timer.read();
                    self.state = .Finished;
                    return false;
                }
            },
            .Finished => unreachable,
        }
    }

    pub fn startTimer(self: *Context) void {
        self.timer.reset();
    }

    pub fn stopTimer(self: *Context) void {
        const elapsed = self.timer.read();
        self.nanoseconds += elapsed;
    }

    pub fn runExplicitTiming(self: *Context) bool {
        switch (self.state) {
            .None => {
                self.state = .Heating;
                self.run_timer.reset();
                return true;
            },
            .Heating => {
                self.count += 1;
                if (self.run_timer.read() >= HeatingTime) {
                    // Caches should be hot
                    self.count = @as(u32, @intCast(RunTime / (HeatingTime / self.count)));
                    self.nanoseconds = 0;
                    self.run_timer.reset();
                    self.state = .Running;
                }

                return true;
            },
            .Running => {
                if (self.iter < self.count) {
                    self.iter += 1;
                    return true;
                } else {
                    self.state = .Finished;
                    return false;
                }
            },
            .Finished => unreachable,
        }
    }

    pub fn averageTime(self: *Context, unit: u64) f32 {
        assert(self.state == .Finished);
        return @as(f32, @floatFromInt(self.nanoseconds / unit)) / @as(f32, @floatFromInt(self.iter));
    }
};

pub fn benchmark(comptime name: []const u8, comptime f: BenchFn) void {
    var ctx = Context.init();
    @call(.auto, f, .{&ctx});

    var unit: u64 = undefined;
    var unit_name: []const u8 = undefined;
    const avg_time = ctx.averageTime(1);
    assert(avg_time >= 0);

    if (avg_time <= time.ns_per_us) {
        unit = 1;
        unit_name = "ns";
    } else if (avg_time <= time.ns_per_ms) {
        unit = time.ns_per_us;
        unit_name = "us";
    } else {
        unit = time.ns_per_ms;
        unit_name = "ms";
    }

    info("{s}: avg {d:.3}{s} ({} iterations)", .{ name, ctx.averageTime(unit), unit_name, ctx.iter });
}

fn argTypeFromFn(comptime f: anytype) type {
    const F = @TypeOf(f);
    if (@typeInfo(F) != .Fn) {
        @compileError("Argument must be a function.");
    }

    const fnInfo = @typeInfo(F).Fn;
    if (fnInfo.params.len != 2) {
        @compileError("Only functions taking 1 argument are accepted.");
    }

    return fnInfo.params[1].type.?;
}

pub fn benchmarkArgs(comptime name: []const u8, comptime f: anytype, comptime args: []const argTypeFromFn(f)) void {
    inline for (args) |a| {
        var ctx = Context.init();
        const arg_type = argTypeFromFn(f);
        const bench_fn_type: type = fn (*Context, arg_type) void;
        const f2: bench_fn_type = f;
        f2(&ctx, a);

        var unit: u64 = undefined;
        var unit_name: []const u8 = undefined;
        const avg_time = ctx.averageTime(1);
        assert(avg_time >= 0);

        if (avg_time <= time.ns_per_us) {
            unit = 1;
            unit_name = "ns";
        } else if (avg_time <= time.ns_per_ms) {
            unit = time.ns_per_us;
            unit_name = "us";
        } else {
            unit = time.ns_per_ms;
            unit_name = "ms";
        }

        info("{s} <{s}>: avg {d:.3}{s} ({} iterations)\n", .{ name, if (@TypeOf(a) == type) @typeName(a) else "", ctx.averageTime(unit), unit_name, ctx.iter });
    }
}

pub fn doNotOptimize(value: anytype) void {
    // LLVM triggers an assert if we pass non-trivial types as inputs for the asm volatile expression.
    const T = @TypeOf(value);
    const typeId = @typeInfo(T);
    switch (typeId) {
        .Bool, .Int, .Float => {
            asm volatile (""
                :
                : [_] "r,m" (value),
                : "memory"
            );
        },
        .Optional => {
            if (value) |v| doNotOptimize(v);
        },
        .Struct => {
            inline for (comptime std.meta.fields(T)) |field| {
                doNotOptimize(@field(value, field.name));
            }
        },
        .Type, .Void, .NoReturn, .ComptimeFloat, .ComptimeInt, .Undefined, .Null, .Fn => @compileError("doNotOptimize makes no sense for " ++ @tagName(typeId)),
        else => @compileError("doNotOptimize is not implemented for " ++ @tagName(typeId)),
    }
}

fn testBenchSleep57(ctx: *Context) void {
    while (ctx.run()) {
        time.sleep(57 * time.ns_per_ms);
    }
}
test "benchmark" {
    if (!@import("opts").benchmark) return error.SkipZigTest;
    benchmark("Sleep57", testBenchSleep57);
}

fn testBenchSleepArg(ctx: *Context, ms: u32) void {
    while (ctx.run()) {
        time.sleep(ms * time.ns_per_ms);
    }
}

test "benchmarkArgs" {
    if (!@import("opts").benchmark) return error.SkipZigTest;
    benchmarkArgs("Sleep", testBenchSleepArg, &[_]u32{ 20, 30 });
}

fn testSleepCustom(ctx: *Context) void {
    while (ctx.runExplicitTiming()) {
        time.sleep(30 * time.ns_per_ms);
        ctx.startTimer();
        defer ctx.stopTimer();
        time.sleep(10 * time.ns_per_ms);
    }
}

test "benchmark custom timing" {
    if (!@import("opts").benchmark) return error.SkipZigTest;
    benchmark("sleep smol", testSleepCustom);
}

