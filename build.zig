const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const bootloader_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
        .abi = .msvc,
    });

    const bootloader = b.addExecutable(.{
        .name = "bootx64",
        .root_source_file = b.path("bootloader/main.zig"),
        .target = bootloader_target,
        .optimize = optimize,
    });

    const bootloader_install = b.addInstallArtifact(bootloader, .{
        .dest_dir = .{ .override = .{ .custom = "efi/boot" } },
    });

    const kernel_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("kernel/main.zig"),
        .target = kernel_target,
        .optimize = .ReleaseSmall,
    });
    kernel.setLinkerScript(b.path("kernel/linker.ld"));
    kernel.root_module.code_model = .kernel; 
    kernel.root_module.red_zone = false;

    const kernel_bin = b.addObjCopy(kernel.getEmittedBin(), .{
        .format = .bin,
    });
    
    const kernel_install = b.addInstallFile(kernel_bin.getOutput(), "kernel.bin");

    const image_step = b.step("image", "Create OS Disk Image");
    
    const img_path = "zig-out/os.img";

    const make_img = b.addSystemCommand(&.{ 
        "dd", "if=/dev/zero", "of=" ++ img_path, "bs=1M", "count=64" 
    });

    const fmt_img = b.addSystemCommand(&.{ 
        "mkfs.vfat", "-F", "32", "-n", "MYOS_EFI", img_path 
    });
    
    const mkdir_dirs = b.addSystemCommand(&.{ 
        "mmd", "-i", img_path, "::/EFI", "::/EFI/BOOT" 
    });

    const boot_src = b.getInstallPath(.{ .custom = "efi/boot" }, "bootx64.efi");
    const copy_boot = b.addSystemCommand(&.{ 
        "mcopy", "-i", img_path, "-o", boot_src, "::/EFI/BOOT/BOOTX64.EFI" 
    });

    const kernel_src = b.getInstallPath(.{ .custom = "" }, "kernel.bin");
    const copy_kernel = b.addSystemCommand(&.{ 
        "mcopy", "-i", img_path, "-o", kernel_src, "::/kernel.bin" 
    });

    copy_boot.step.dependOn(&bootloader_install.step);
    copy_kernel.step.dependOn(&kernel_install.step);

    fmt_img.step.dependOn(&make_img.step);
    mkdir_dirs.step.dependOn(&fmt_img.step);
    copy_boot.step.dependOn(&mkdir_dirs.step);
    copy_kernel.step.dependOn(&mkdir_dirs.step);

    image_step.dependOn(&copy_boot.step);
    image_step.dependOn(&copy_kernel.step);

    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-bios", "/usr/share/OVMF/OVMF_CODE.fd",
        "-drive", "format=raw,file=" ++ img_path,
        "-serial", "stdio"
    });
    run_cmd.step.dependOn(image_step);

    const run_step = b.step("run", "Run in QEMU");
    run_step.dependOn(&run_cmd.step);
}