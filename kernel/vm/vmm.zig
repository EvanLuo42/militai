const std = @import("std");
const paging = @import("../arch/x86/paging.zig");
const Pmm = @import("pmm.zig").Pmm;
const serial = @import("../serial.zig");

const PageTable = paging.PageTable;
const PageTableEntry = paging.PageTableEntry;
const VirtualAddress = paging.VirtualAddress;

pub const HHDM_OFFSET: u64 = 0xFFFF800000000000;
pub const KERNEL_BASE: u64 = 0xFFFFFFFF80000000;
const MAX_PHYS_MAP: u64 = 4 * 1024 * 1024 * 1024;

var kernel_pml4: *PageTable = undefined;
var is_paging_active: bool = false;

pub fn init() void {
    std.log.info("[VMM] Initializing paging structures...\n", .{});

    const pml4_phys = Pmm.allocPage() orelse @panic("VMM: Failed to allocate PML4");
    kernel_pml4 = physToPtr(pml4_phys);
    @memset(@as([*]u8, @ptrCast(kernel_pml4))[0..4096], 0);

    std.log.info("[VMM] Created PML4 at phys: 0x{x}\n", .{pml4_phys});

    std.log.info("[VMM] Mapping HHDM (0 -> 4GB) using 2MB Huge Pages...\n", .{});
    
    const flags_common = 3;
    
    var phys: u64 = 0;
    while (phys < MAX_PHYS_MAP) : (phys += 2 * 1024 * 1024) {
        mapHugePage(phys + HHDM_OFFSET, phys, flags_common);
    }

    std.log.info("[VMM] Mapping Identity (0 -> 16MB)...\n", .{});
    phys = 0;
    while (phys < 16 * 1024 * 1024) : (phys += 4096) {
        mapPage(phys, phys, flags_common);
    }

    std.log.info("[VMM] Loading CR3 register...\n", .{});
    loadCR3(pml4_phys);

    is_paging_active = true;
    kernel_pml4 = physToPtr(pml4_phys);

    std.log.info("[VMM] CR3 Switched! Paging is ACTIVE.\n", .{});
    
    const PmmInner = @import("pmm.zig").Pmm;
    PmmInner.remapBitmap(HHDM_OFFSET);
}

pub fn mapPage(virt: u64, phys: u64, flags: u64) void {
    const idx = VirtualAddress.from(virt);

    const pml4_entry = kernel_pml4.at(idx.pml4_index);
    const pdpt = getOrAllocTable(pml4_entry);

    const pdpt_entry = pdpt.at(idx.pdpt_index);
    const pd = getOrAllocTable(pdpt_entry);

    const pd_entry = pd.at(idx.pd_index);
    const pt = getOrAllocTable(pd_entry);

    const pt_entry = pt.at(idx.pt_index);

    pt_entry.setAddr(phys);
    
    const raw_val = pt_entry.asU64();
    const address_part = raw_val & paging.PHYS_ADDR_MASK;
    pt_entry.* = @as(PageTableEntry, @bitCast(address_part | flags));
}

pub fn mapHugePage(virt: u64, phys: u64, flags: u64) void {
    const idx = VirtualAddress.from(virt);

    const pml4_entry = kernel_pml4.at(idx.pml4_index);
    const pdpt = getOrAllocTable(pml4_entry);

    const pdpt_entry = pdpt.at(idx.pdpt_index);
    const pd = getOrAllocTable(pdpt_entry);

    const pd_entry = pd.at(idx.pd_index);

    pd_entry.setAddr(phys);

    const raw_val = pd_entry.asU64();
    const address_part = raw_val & paging.PHYS_ADDR_MASK;
    
    pd_entry.* = @as(PageTableEntry, @bitCast(address_part | flags | 0x80));
}

pub fn physToVirt(phys: u64) u64 {
    if (is_paging_active) {
        return phys + HHDM_OFFSET;
    }
    return phys;
}

fn getOrAllocTable(entry: *PageTableEntry) *PageTable {
    if (entry.present) {
        return physToPtr(entry.getAddr());
    }

    const new_table_phys = Pmm.allocPage() orelse @panic("VMM: OOM in getOrAllocTable");
    const new_table_ptr = physToPtr(new_table_phys);

    @memset(@as([*]u8, @ptrCast(new_table_ptr))[0..4096], 0);

    entry.setAddr(new_table_phys);
    entry.present = true;
    entry.read_write = true;
    entry.user_supervisor = true; 
    return new_table_ptr;
}

inline fn physToPtr(phys: u64) *PageTable {
    const virt = physToVirt(phys);
    return @ptrFromInt(virt);
}

inline fn loadCR3(pml4_phys: u64) void {
    asm volatile (
        "mov %[addr], %%cr3"
        :
        : [addr] "r" (pml4_phys)
        : "memory"
    );
}

pub inline fn flushTLB(addr: u64) void {
    asm volatile (
        "invlpg (%[addr])"
        :
        : [addr] "r" (addr)
        : "memory"
    );
}