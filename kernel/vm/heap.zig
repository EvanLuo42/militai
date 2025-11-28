const std = @import("std");
const Pmm = @import("pmm.zig").Pmm;
const Vmm = @import("vmm.zig");
const serial = @import("../serial.zig");

const HEAP_START_ADDR: u64 = 0xFFFF900000000000;
const INITIAL_HEAP_SIZE: usize = 2 * 1024 * 1024;

var page_allocator_state = KernelPageAllocator{};
const page_allocator = std.mem.Allocator{
    .ptr = &page_allocator_state,
    .vtable = &KernelPageAllocator.vtable,
};

var fixed_buffer_allocator: std.heap.FixedBufferAllocator = undefined;
pub var allocator: std.mem.Allocator = undefined;

pub fn init() void {
    std.log.info("[HEAP] Initializing...\n", .{});
    
    const heap_slice = page_allocator.alloc(u8, INITIAL_HEAP_SIZE) catch |err| {
        serial.kprint("[HEAP] Failed to map initial heap: {}\n", .{err});
        @panic("HEAP INIT FAILED");
    };

    fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(heap_slice);
    allocator = fixed_buffer_allocator.allocator();
    
    std.log.info("[HEAP] Ready. Base: 0x{x}, Size: {d} MB\n", .{
        @intFromPtr(heap_slice.ptr), 
        heap_slice.len / 1024 / 1024
    });
    
    testAllocation();
}

fn testAllocation() void {
    std.log.info("[HEAP] Testing dynamic allocation...\n", .{});
    
    var list = std.ArrayList(u32).init(allocator);
    defer list.deinit(); 

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        list.append(i) catch |err| {
            std.log.info("Alloc failed: {}\n", .{err});
            return;
        };
    }

    std.log.info("[HEAP] ArrayList size: {d}, Item[5]: {d}\n", .{list.items.len, list.items[5]});
    
    const s = std.fmt.allocPrint(allocator, "Hex: 0x{x}", .{0xDEADBEEF}) catch "fail";
    std.log.info("[HEAP] fmt: {s}\n", .{s});
}

const KernelPageAllocator = struct {
    cursor: u64 = 0,

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
        .remap = remap
    };

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *KernelPageAllocator = @ptrCast(@alignCast(ctx));
        
        if (ptr_align.toByteUnits() > 4096) {
            return null;
        }

        const page_size = 4096;
        const aligned_len = std.mem.alignForward(usize, len, page_size);
        const pages_needed = aligned_len / page_size;

        const start_virt = HEAP_START_ADDR + self.cursor;
        
        var i: usize = 0;
        while (i < pages_needed) : (i += 1) {
            const curr_virt = start_virt + (i * page_size);
            
            const phys = Pmm.allocPage() orelse return null;
            
            Vmm.mapPage(curr_virt, phys, 3);
            Vmm.flushTLB(curr_virt);
        }

        self.cursor += aligned_len;
        return @ptrFromInt(start_virt);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        return null; 
    }
};