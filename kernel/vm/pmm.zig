const std = @import("std");
const serial = @import("../serial.zig");
const common = @import("common");
const BootInfo = common.BootInfo;
const MemoryDescriptor = common.MemoryDescriptor;

pub const PAGE_SIZE: usize = 4096;

const EfiConventionalMemory = 7;
const EfiLoaderCode = 1;
const EfiLoaderData = 2;
const EfiBootServicesCode = 3;
const EfiBootServicesData = 4;

pub const Pmm = struct {
    bitmap: []u8,
    mem_size: usize,
    used_pages: usize,
    total_pages: usize,

    var self: Pmm = undefined;

    pub fn init(boot_info: *const BootInfo) void {
        const mm = boot_info.mem_map;

        var max_phys_addr: usize = 0;
        var iter: usize = 0;
        const count = mm.size / mm.desc_size;

        while (iter < count) : (iter += 1) {
            const desc = getDescriptor(mm, iter);
            const end_addr = desc.physical_start + desc.number_of_pages * PAGE_SIZE;
            if (end_addr > max_phys_addr) {
                max_phys_addr = end_addr;
            }
        }

        self.mem_size = max_phys_addr;
        self.total_pages = max_phys_addr / PAGE_SIZE;

        const bitmap_size = std.mem.alignForward(usize, self.total_pages / 8, PAGE_SIZE);

        std.log.info("[PMM] Total RAM: {d} MB, Bitmap needs: {d} KB\n", .{ self.mem_size / 1024 / 1024, bitmap_size / 1024 });

        var bitmap_phys_addr: usize = 0;
        iter = 0;
        while (iter < count) : (iter += 1) {
            const desc = getDescriptor(mm, iter);
            if (desc.type == EfiConventionalMemory) {
                const size = desc.number_of_pages * PAGE_SIZE;
                if (size >= bitmap_size) {
                    bitmap_phys_addr = desc.physical_start;
                    break;
                }
            }
        }

        if (bitmap_phys_addr == 0) {
            @panic("PMM: Could not find memory for bitmap!");
        }

        self.bitmap = @as([*]u8, @ptrFromInt(bitmap_phys_addr))[0..bitmap_size];

        @memset(self.bitmap, 0xFF);
        self.used_pages = self.total_pages;

        iter = 0;
        while (iter < count) : (iter += 1) {
            const desc = getDescriptor(mm, iter);

            if (desc.type == EfiConventionalMemory) {
                freeRegion(desc.physical_start, desc.number_of_pages);
            }
        }

        markRegionUsed(bitmap_phys_addr, std.mem.alignForward(usize, bitmap_size, PAGE_SIZE) / PAGE_SIZE);

        markRegionUsed(0, 256);

        std.log.info("[PMM] Initialized. Free: {d} MB, Used: {d} MB\n", .{ (self.total_pages - self.used_pages) * 4 / 1024, self.used_pages * 4 / 1024 });
    }

    pub fn allocPage() ?usize {
        for (self.bitmap, 0..) |byte, byte_idx| {
            if (byte != 0xFF) {
                var bit_idx: u3 = 0;
                while (bit_idx < 8) : (bit_idx += 1) {
                    if ((byte >> bit_idx) & 1 == 0) {
                        const page_idx = byte_idx * 8 + bit_idx;
                        setBit(page_idx);
                        self.used_pages += 1;
                        const addr = page_idx * PAGE_SIZE;
                        @memset(@as([*]u8, @ptrFromInt(addr))[0..PAGE_SIZE], 0);
                        return addr;
                    }
                }
            }
        }
        return null;
    }

    pub fn freePage(phys_addr: usize) void {
        const page_idx = phys_addr / PAGE_SIZE;
        if (testBit(page_idx)) {
            clearBit(page_idx);
            self.used_pages -= 1;
        }
    }

    fn getDescriptor(mm: common.MemoryMap, index: usize) *const MemoryDescriptor {
        const addr = @intFromPtr(mm.ptr) + index * mm.desc_size;
        return @as(*const MemoryDescriptor, @ptrFromInt(addr));
    }

    fn freeRegion(phys_start: usize, page_count: usize) void {
        var i: usize = 0;
        const start_idx = phys_start / PAGE_SIZE;
        while (i < page_count) : (i += 1) {
            if (testBit(start_idx + i)) {
                clearBit(start_idx + i);
                self.used_pages -= 1;
            }
        }
    }

    fn markRegionUsed(phys_start: usize, page_count: usize) void {
        var i: usize = 0;
        const start_idx = phys_start / PAGE_SIZE;
        while (i < page_count) : (i += 1) {
            if (!testBit(start_idx + i)) {
                setBit(start_idx + i);
                self.used_pages += 1;
            }
        }
    }

    pub fn remapBitmap(offset: u64) void {
        const old_ptr = @intFromPtr(self.bitmap.ptr);
        const new_ptr = old_ptr + offset;
        
        self.bitmap.ptr = @as([*]u8, @ptrFromInt(new_ptr));
        
        std.log.info("[PMM] Bitmap remapped to Virt: 0x{x}\n", .{new_ptr});
    }

    inline fn setBit(idx: usize) void {
        self.bitmap[idx / 8] |= (@as(u8, 1) << @intCast(idx % 8));
    }

    inline fn clearBit(idx: usize) void {
        self.bitmap[idx / 8] &= ~(@as(u8, 1) << @intCast(idx % 8));
    }

    inline fn testBit(idx: usize) bool {
        return (self.bitmap[idx / 8] >> @intCast(idx % 8)) & 1 == 1;
    }
};
