const std = @import("std");
const uefi = std.os.uefi;

const Framebuffer = extern struct {
    base: u64,
    size: u64,
    width: u32,
    height: u32,
    stride: u32,
};

const KernelEntry = *const fn (*Framebuffer) callconv(.{ .x86_64_sysv = .{} }) noreturn;

pub fn main() void {
    const bs = uefi.system_table.boot_services.?;
    const con_out = uefi.system_table.con_out.?;

    _ = con_out.clearScreen();
    log(con_out, "[INFO] UEFI Bootloader Started");

    var gop_guid: uefi.Guid align(8) = uefi.protocol.GraphicsOutput.guid;

    var gop: ?*uefi.protocol.GraphicsOutput = null;
    if (bs.locateProtocol(&gop_guid, null, @ptrCast(&gop)) != .success) {
        printError(con_out, "GOP Not Found");
        return;
    }
    log(con_out, "[INFO] GOP Initialized");

    var fs_guid: uefi.Guid align(8) = uefi.protocol.SimpleFileSystem.guid;

    var fs: ?*uefi.protocol.SimpleFileSystem = null;
    if (bs.locateProtocol(&fs_guid, null, @ptrCast(&fs)) != .success) {
        printError(con_out, "FS Not Found");
        return;
    }
    log(con_out, "[INFO] File System Mounted");

    var root: *const uefi.protocol.File = undefined;
    _ = fs.?.openVolume(&root);

    var kernel_file: *const uefi.protocol.File = undefined;
    const filename = std.unicode.utf8ToUtf16LeStringLiteral("kernel.bin");
    if (root.open(&kernel_file, filename, uefi.protocol.File.efi_file_mode_read, 0) != .success) {
        printError(con_out, "kernel.bin missing");
        return;
    }
    log(con_out, "[INFO] Found kernel.bin");

    const kernel_max_size = 0x100000;

    const kernel_addr: u64 = 0x100000;
    var kernel_ptr: [*]align(4096) u8 = @ptrFromInt(kernel_addr);
    const pages = (kernel_max_size + 4095) / 4096;

    if (bs.allocatePages(.allocate_address, .loader_data, pages, &kernel_ptr) != .success) {
        printError(con_out, "Mem Alloc Failed");
        return;
    }
    log(con_out, "[INFO] Memory Allocated at 0x100000");

    var read_size: usize = kernel_max_size;
    _ = kernel_file.read(&read_size, kernel_ptr);

    var fb_info = Framebuffer{
        .base = gop.?.mode.frame_buffer_base,
        .size = gop.?.mode.frame_buffer_size,
        .width = gop.?.mode.info.horizontal_resolution,
        .height = gop.?.mode.info.vertical_resolution,
        .stride = gop.?.mode.info.pixels_per_scan_line,
    };

    log(con_out, "[INFO] Kernel Loaded into Memory");

    _ = bs.stall(1_000_000);

    var map_key: usize = 0;
    var mem_size: usize = 0;
    var desc_size: usize = 0;
    var desc_ver: u32 = 0;

    _ = bs.getMemoryMap(&mem_size, null, &map_key, &desc_size, &desc_ver);
    mem_size += 4096;

    var mem_map: [*]align(8) u8 = undefined;
    _ = bs.allocatePool(.loader_data, mem_size, @ptrCast(&mem_map));

    if (bs.getMemoryMap(&mem_size, @ptrCast(mem_map), &map_key, &desc_size, &desc_ver) == .success) {
        _ = bs.exitBootServices(uefi.handle, map_key);
    } else {
        printError(con_out, "ExitBS Failed");
        while (true) {}
    }

    const entry_fn: KernelEntry = @ptrCast(kernel_ptr);
    entry_fn(&fb_info);
}

fn log(out: *uefi.protocol.SimpleTextOutput, msg: []const u8) void {
    for (msg) |c| {
        const u = [2:0]u16{ c, 0 };
        _ = out.outputString(&u);
    }
    _ = out.outputString(&[_:0]u16{ '\r', '\n' });
}

fn printError(out: *uefi.protocol.SimpleTextOutput, msg: []const u8) void {
    log(out, msg);
}