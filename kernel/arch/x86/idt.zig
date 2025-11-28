const std = @import("std");
const serial = @import("../../serial.zig");

const IdtEntry = packed struct {
    base_low: u16,
    selector: u16,
    ist: u8,
    flags: u8,
    base_mid: u16,
    base_high: u32,
    reserved: u32,
};

const IdtPtr = packed struct {
    limit: u16,
    base: u64,
};

var idt_entries: [256]IdtEntry = undefined;
var idt_ptr: IdtPtr = undefined;

pub fn init() void {
    setIdtGate(14, @intFromPtr(&pageFaultHandlerISr));

    idt_ptr.limit = @sizeOf(@TypeOf(idt_entries)) - 1;
    idt_ptr.base = @intFromPtr(&idt_entries);
    
    asm volatile ("lidt (%[ptr])" : : [ptr] "r" (&idt_ptr));
    
    std.log.info("[IDT] Initialized. Page Fault trap ready.\n", .{});
}

fn setIdtGate(num: u8, base: u64) void {
    idt_entries[num] = IdtEntry{
        .base_low = @truncate(base & 0xFFFF),
        .selector = 0x08,
        .ist = 0,
        .flags = 0x8E,
        .base_mid = @truncate((base >> 16) & 0xFFFF),
        .base_high = @truncate((base >> 32) & 0xFFFFFFFF),
        .reserved = 0,
    };
}

export fn pageFaultHandlerISr() callconv(.Naked) void {
    asm volatile (
        \\ pushq %rax
        \\ pushq %rcx
        \\ pushq %rdx
        \\ pushq %rdi
        \\ pushq %rsi
        \\ pushq %r8
        \\ pushq %r9
        \\ pushq %r10
        \\ pushq %r11
        \\ pushq %rbp
        \\
        \\ mov %cr2, %rdi  // 参数 1: Page Fault Address
        \\ call pageFaultHandler
        \\
        \\ popq %rbp
        \\ popq %r11
        \\ popq %r10
        \\ popq %r9
        \\ popq %r8
        \\ popq %rsi
        \\ popq %rdi
        \\ popq %rdx
        \\ popq %rcx
        \\ popq %rax
        \\
        \\ add $8, %rsp
        \\ iretq
    );
}

export fn pageFaultHandler(addr: u64) callconv(.C) void {
    std.log.err("\n!!! PAGE FAULT DETECTED !!!\n", .{});
    std.log.err("Violation Address (CR2): 0x{x}\n", .{addr});
    
    serial.hang();
}