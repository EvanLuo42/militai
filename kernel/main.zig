const std = @import("std");

const COM1 = 0x3F8;

fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [value] "{al}" (value),
          [port] "{dx}" (port),
    );
}

fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[ret]"
        : [ret] "={al}" (-> u8),
        : [port] "{dx}" (port),
    );
}

fn serialInit() void {
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x80);
    outb(COM1 + 0, 0x03);
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x03);
    outb(COM1 + 2, 0xC7);
    outb(COM1 + 4, 0x0B);
}

fn isTransmitEmpty() bool {
    return (inb(COM1 + 5) & 0x20) != 0;
}

fn serialPutChar(c: u8) void {
    while (!isTransmitEmpty()) {}
    outb(COM1, c);
}

fn serialWrite(context: void, bytes: []const u8) error{}!usize {
    _ = context;
    for (bytes) |c| {
        serialPutChar(c);
    }
    return bytes.len;
}

const serial_writer = std.io.Writer(void, error{}, serialWrite){ .context = {} };

pub fn kprint(comptime fmt: []const u8, args: anytype) void {
    serial_writer.print(fmt, args) catch unreachable;
}

pub const Framebuffer = extern struct {
    base: [*]u32,
    size: u64,
    width: u32,
    height: u32,
    stride: u32,
};

export fn _start(fb: *Framebuffer) callconv(.C) noreturn {
    serialInit();

    kprint("\n\n", .{});
    kprint("========================================\n", .{});
    kprint("Hello from Zig Kernel!\n", .{});
    kprint("========================================\n", .{});
    kprint("[KERNEL] Video Info: {}x{}, Stride: {}\n", .{ fb.width, fb.height, fb.stride });
    kprint("[KERNEL] Framebuffer Base: 0x{x}\n", .{@intFromPtr(fb.base)});

    for (0..fb.height) |y| {
        for (0..fb.width) |x| {
            const index = @as(usize, y) * @as(usize, fb.stride) + x;
            if (index < fb.size / 4) {
                fb.base[index] = 0xFFFF0000;
            }
        }
    }

    kprint("[KERNEL] Screen painted red.\n", .{});
    kprint("[KERNEL] Entering infinite loop...\n", .{});

    hang();
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    _ = ret_addr;
    kprint("\n!!!!! KERNEL PANIC !!!!!\n{s}\n", .{msg});
    hang();
}

fn hang() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
