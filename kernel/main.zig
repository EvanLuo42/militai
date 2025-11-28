const std = @import("std");
const serial = @import("serial.zig");
const common = @import("common");

pub const BootInfo = common.BootInfo;

const Pmm = @import("vm/pmm.zig").Pmm;
const Vmm = @import("vm/vmm.zig");
const Gdt = @import("arch/x86/gdt.zig");
const Idt = @import("arch/x86/idt.zig");
const Heap = @import("vm/heap.zig");

pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 4096,
    .logFn = kernelLog,
    .log_level = .info,
};

pub fn kernelLog(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const prefix = "[" ++ @tagName(level) ++ "] " ++ scope_prefix;

    serial.kprint(prefix ++ format, args);
}

var kernel_stack: [16 * 1024]u8 align(16) = undefined;

export fn _start(_: *BootInfo) linksection(".text.entry") callconv(.Naked) noreturn {
    asm volatile (
        \\ cli
        \\ mov %[stack_top], %%rsp
        \\ xor %%rbp, %%rbp
        \\ call kmain
        \\ hlt
        :
        : [stack_top] "r" (@intFromPtr(&kernel_stack) + kernel_stack.len),
    );

    while (true) {}
}

export fn kmain(boot_info: *const BootInfo) callconv(.C) noreturn {
    serial.init();

    serial.kprint("\n\n========================================\n", .{});
    serial.kprint("Zircon starting...\n", .{});
    serial.kprint("========================================\n", .{});

    const mm = boot_info.mem_map;
    const entries = if (mm.desc_size > 0) mm.size / mm.desc_size else 0;

    std.log.info("[BOOT] mem_map: base=0x{x}, size={d}, desc_size={d}, entries~{d}\n", .{ @intFromPtr(mm.ptr), mm.size, mm.desc_size, entries });

    Pmm.init(boot_info);
    Vmm.init();

    Gdt.init();

    Idt.init();

    Heap.init();

    

    std.log.info("[KERNEL] entering idle loop (hlt)...\n", .{});

    serial.hang();
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    _ = ret_addr;
    std.log.err("\n!!!!! KERNEL PANIC !!!!!\n{s}\n", .{msg});
    serial.hang();
}
