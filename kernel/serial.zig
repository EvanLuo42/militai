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

fn isTransmitEmpty() bool {
    return (inb(COM1 + 5) & 0x20) != 0;
}

fn serialPutChar(c: u8) void {
    while (!isTransmitEmpty()) {}
    outb(COM1, c);
}

fn serialWrite(context: void, bytes: []const u8) error{}!usize {
    _ = context;
    for (bytes) |c| serialPutChar(c);
    return bytes.len;
}

pub fn init() void {
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x80);
    outb(COM1 + 0, 0x03);
    outb(COM1 + 1, 0x00);
    outb(COM1 + 3, 0x03);
    outb(COM1 + 2, 0xC7);
    outb(COM1 + 4, 0x0B);
}

const Writer = std.io.Writer(void, error{}, serialWrite);
pub var writer: Writer = .{ .context = {} };

pub fn kprint(comptime fmt: []const u8, args: anytype) void {
    writer.print(fmt, args) catch unreachable;
}

pub fn hang() noreturn {
    while (true) {
        asm volatile ("hlt");
    }
}
