const std = @import("std");

pub const MemoryMap = extern struct {
    ptr: [*]const u8,
    size: usize,
    desc_size: usize,
    desc_version: u32,
};

pub const MemoryDescriptor = extern struct {
    type: u32,
    physical_start: u64,
    virtual_start: u64,
    number_of_pages: u64,
    attribute: u64,
};

pub const BootInfo = extern struct {
    mem_map: MemoryMap,
};
