var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    if (builtin.os.tag != .linux and builtin.os.tag != .macos) {
        @compileError("This is only made for macos and linux");
    }

    const argv = std.os.argv;

    const allocator, const is_debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
    };
    defer if (is_debug) {
        _ = debug_allocator.detectLeaks();
    };

    rl.initWindow(512, 512, "brainfuck graphical");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    const file_path: []const u8 = if (argv.len == 1) "program.bf" else if (argv.len == 2) std.mem.span(argv[1]) else {
        try stderr.writeAll("too many arguments, please just put a single file path\n");
        std.process.exit(1);
    };

    const program = try fileToProgram(allocator, file_path);
    defer allocator.free(program);

    var bf: BrainFuck = .init(program);

    while (!rl.windowShouldClose()) {
        if (bf.end) {
            rl.closeWindow();
        }

        bf.interpret();

        const width, const height = .{ rl.getScreenWidth(), rl.getScreenHeight() };

        const size = @max(width, height);
        const t_size = @divTrunc(size, 16);

        rl.beginDrawing();
        defer rl.endDrawing();

        for (bf.cells[0..256], 0..) |cell, i| {
            const x: i32 = @intCast(i % 16);
            const y: i32 = @intCast(i / 16);
            rl.drawRectangle(t_size * x, t_size * y, t_size, t_size, toRlColor(cell));
        }
    }
}

const max_length = @min(std.math.maxInt(u32), std.math.maxInt(usize));

fn boolsToU8(bools: [8]bool) u8 {
    var result: u8 = 0;
    for (bools, 0..8) |b, i| {
        result |= @as(u8, @intFromBool(b)) << @intCast(i);
    }
    return result;
}

fn toRlColor(col: u8) rl.Color {
    const r: u16 = (col >> 5) & 0b111;
    const g: u16 = (col >> 2) & 0b111;
    const b: u16 = col & 0b11;
    return .{
        .r = @intCast(r * 255 / 7),
        .g = @intCast(g * 255 / 7),
        .b = @intCast(b * 255 / 3),
        .a = 255,
    };
}

const Instruction = union(enum) {
    add: u8,
    sub: u8,
    right: u8,
    left: u8,
    draw,
    read,
    open,
    close,
};

const BrainFuck = struct {
    cells: [30_000]u8 = @splat(0),
    idx: usize = 0,

    pc: usize = 0,
    program: []const Instruction,

    end: bool = false,

    pub fn init(program: []const Instruction) BrainFuck {
        return .{
            .program = program,
        };
    }

    pub fn interpret(self: *BrainFuck) void {
        while (self.pc < self.program.len) : (self.pc += 1) switch (self.program[self.pc]) {
            .add => |x| self.cells[self.idx] +%= x,
            .sub => |x| self.cells[self.idx] -%= x,
            .right => |x| self.idx = (self.idx + x) % self.cells.len,
            .left => |x| {
                var x2: usize = x;
                while (x2 > self.idx) {
                    x2 -= self.idx + 1;
                    self.idx = self.cells.len - 1;
                }
                self.idx -= x2;
            },
            .open => if (self.cells[self.idx] == 0) {
                var loops: usize = 1;
                while (loops != 0) {
                    self.pc += 1;
                    switch (self.program[self.pc]) {
                        .open => loops += 1,
                        .close => loops -= 1,
                        else => {},
                    }
                }
            },
            .close => if (self.cells[self.idx] != 0) {
                var loops: usize = 1;
                while (loops != 0) {
                    self.pc -= 1;
                    switch (self.program[self.pc]) {
                        .close => loops += 1,
                        .open => loops -= 1,
                        else => {},
                    }
                }
            },
            .draw => {
                self.pc += 1;
                return;
            },
            .read => self.cells[self.idx] = boolsToU8(.{
                rl.isKeyDown(.up),
                rl.isKeyDown(.down),
                rl.isKeyDown(.left),
                rl.isKeyDown(.right),
                rl.isKeyDown(.z),
                rl.isKeyDown(.x),
                rl.isKeyDown(.c),
                rl.isKeyDown(.left_shift),
            }),
        };

        self.end = true;
    }
};

fn fileToProgram(allocator: std.mem.Allocator, file_name: []const u8) ![]const Instruction {
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const program_str = try file.readToEndAlloc(allocator, max_length);
    defer allocator.free(program_str);

    const program_buffer = try allocator.alloc(Instruction, program_str.len);
    var program: []Instruction = program_buffer[0..0];
    defer allocator.free(program_buffer);

    var loops: usize = 0;

    for (program_str) |c| {
        std.debug.assert(program.ptr == program_buffer.ptr and program.len < program_buffer.len);
        switch (c) {
            '+' => {
                if (program.len != 0 and program[program.len-1] == .add) {
                    program[program.len-1].add +%= 1;
                } else {
                    program.len += 1;
                    program[program.len-1] = .{ .add = 1 };
                }
            },
            '-' => {
                if (program.len != 0 and program[program.len-1] == .sub) {
                    program[program.len-1].sub +%= 1;
                } else {
                    program.len += 1;
                    program[program.len-1] = .{ .sub = 1 };
                }
            },
            '>' => {
                if (program.len != 0 and program[program.len-1] == .right and program[program.len-1].right != 255) {
                    program[program.len-1].right += 1;
                } else {
                    program.len += 1;
                    program[program.len-1] = .{ .right = 1 };
                }
            },
            '<' => {
                if (program.len != 0 and program[program.len-1] == .left and program[program.len-1].left != 255) {
                    program[program.len-1].left += 1;
                } else {
                    program.len += 1;
                    program[program.len-1] = .{ .left = 1 };
                }
            },
            '.' => {
                program.len += 1;
                program[program.len-1] = .draw;
            },
            ',' => {
                program.len += 1;
                program[program.len-1] = .read;
            },
            '[' => {
                loops += 1;

                program.len += 1;
                program[program.len-1] = .open;
            },
            ']' => {
                if (loops == 0) {
                    return error.InvalidProgram;
                }
                loops -= 1;

                program.len += 1;
                program[program.len-1] = .close;
            },
            else => {},
        }
    }

    if (loops != 0) {
        return error.InvalidProgram;
    }

    program = try allocator.alloc(Instruction, program.len);
    @memcpy(program, program_buffer[0..program.len]);

    return program;
}

const std = @import("std");
const stderr = std.io.getStdErr().writer();
const builtin = @import("builtin");
const rl = @import("raylib");
