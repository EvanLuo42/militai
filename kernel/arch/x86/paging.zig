const std = @import("std");
const assert = std.debug.assert;

pub const PHYS_ADDR_MASK: u64 = 0x000FFFFFFFFFF000;

pub const PageTableEntry = packed struct(u64) {
    present: bool,
    read_write: bool,
    user_supervisor: bool,
    write_through: bool,
    cache_disable: bool,
    accessed: bool,
    dirty: bool,
    huge_page: bool,
    global: bool,
    available: u3,
    
    phys_addr_fragment: u40, 
    
    available_high: u11,
    no_execute: bool,

    pub fn setAddr(self: *PageTableEntry, addr: u64) void {
        assert((addr & 0xFFF) == 0);
        self.phys_addr_fragment = @truncate(addr >> 12);
    }

    pub fn getAddr(self: PageTableEntry) u64 {
        return @as(u64, self.phys_addr_fragment) << 12;
    }

    pub fn asU64(self: PageTableEntry) u64 {
        return @bitCast(self);
    }
};

comptime {
    assert(@bitSizeOf(PageTableEntry) == 64);
    assert(@sizeOf(PageTableEntry) == 8);
}

pub const PageTable = extern struct {
    entries: [512]PageTableEntry,

    pub inline fn at(self: *PageTable, index: usize) *PageTableEntry {
        assert(index < 512);
        return &self.entries[index];
    }
};

pub const VirtualAddress = struct {
    pml4_index: u9,
    pdpt_index: u9,
    pd_index: u9,
    pt_index: u9,
    offset: u12,

    pub fn from(addr: u64) VirtualAddress {
        return .{
            .pml4_index = @truncate((addr >> 39) & 0x1FF),
            .pdpt_index = @truncate((addr >> 30) & 0x1FF),
            .pd_index   = @truncate((addr >> 21) & 0x1FF),
            .pt_index   = @truncate((addr >> 12) & 0x1FF),
            .offset     = @truncate(addr & 0xFFF),
        };
    }
};