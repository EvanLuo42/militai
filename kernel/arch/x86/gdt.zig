const std = @import("std");

const GdtEntry = packed struct {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    granularity: u8,
    base_high: u8,
};

const GdtPtr = packed struct {
    limit: u16,
    base: u64,
};

var gdt_entries: [7]GdtEntry = undefined;
var gdt_ptr: GdtPtr = undefined;

pub fn init() void {
    setEntry(0, 0, 0, 0, 0);
    setEntry(1, 0, 0, 0x9A, 0x20);
    setEntry(2, 0, 0, 0x92, 0x00);
    setEntry(3, 0, 0, 0xF2, 0x00);
    setEntry(4, 0, 0, 0xFA, 0x20);
    
    gdt_ptr.limit = @sizeOf(@TypeOf(gdt_entries)) - 1;
    gdt_ptr.base = @intFromPtr(&gdt_entries);

    loadGdt(&gdt_ptr);
    
    reloadSegments();
}

fn setEntry(idx: usize, base: u32, limit: u32, access: u8, flags: u8) void {
    gdt_entries[idx] = GdtEntry{
        .base_low = @truncate(base & 0xFFFF),
        .base_middle = @truncate((base >> 16) & 0xFF),
        .base_high = @truncate((base >> 24) & 0xFF),
        .limit_low = @truncate(limit & 0xFFFF),
        .access = access,
        .granularity = @as(u8, @truncate((limit >> 16) & 0x0F)) | (flags & 0xF0),
    };
}

fn loadGdt(ptr: *GdtPtr) void {
    asm volatile ("lgdt (%[ptr])" : : [ptr] "r" (ptr));
}

fn reloadSegments() void {
    asm volatile (
        \\ pushq $0x08 
        \\ leaq 1f(%%rip), %%rax
        \\ pushq %%rax
        \\ lretq
        \\ 1:
        \\ mov $0x10, %%ax
        \\ mov %%ax, %%ds
        \\ mov %%ax, %%es
        \\ mov %%ax, %%fs
        \\ mov %%ax, %%gs
        \\ mov %%ax, %%ss
        ::: "rax", "memory"
    );
}