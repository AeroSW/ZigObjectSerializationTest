const std = @import("std");
const builtin = @import("builtin");
const file = std.fs.File;
const cwd = std.fs.cwd();
const fba = std.heap.FixedBufferAllocator;

const ArbitraryType = struct {
    size: u64,
    line: []u8
};
const BoxedStructure = packed struct {
    flag: bool,
    letter: u8,
    u32_value: u32,
};
const arbitrary_output_name: []const u8 = "./output/arbitrary.bin";
const boxed_type_one_output_name: []const u8 = "./output/boxed_type_one.bin";

pub fn WriteArbitraryType(mem_alloc: std.mem.Allocator) !ArbitraryType {
    var at: ArbitraryType = .{
        .size = 25,
        .line = try mem_alloc.alloc(u8, 25)
    };
    // Zero out the u8 array to ensure no trash values
    // are written to the file.
    @memset(at.line, 0);
    const hello_world = "Hello, World!";
    var ii: u64 = 0;
    while (ii < hello_world.len) : (ii += 1) {
        at.line[ii] = hello_world[ii];
    }
    const arb_file = try cwd.createFile(arbitrary_output_name, .{.lock = .exclusive});
    defer arb_file.close();
    try arb_file.writer().writeAll(std.mem.asBytes(&at.size));
    try arb_file.writer().writeAll(at.line);
    return at;
}
pub fn ReadArbitraryType(mem_alloc: std.mem.Allocator) !ArbitraryType {
    const arb_file = try cwd.openFile(arbitrary_output_name,
        .{.mode = .read_only, .lock = .exclusive});
    defer arb_file.close();
    const last_pos = try arb_file.getEndPos();
    const arbitrary_buffer: []u8 = try mem_alloc.alloc(u8, last_pos);
    const read_sze = try arb_file.readAll(arbitrary_buffer);
    if (read_sze == last_pos) {
        const size = std.mem.bytesToValue(u64, arbitrary_buffer[0..8]);
        const str: []u8 = try mem_alloc.alloc(u8, size);
        @memset(str, 0);
        var ii: u64 = 0;
        while (ii < size and (ii+8) < last_pos) : (ii += 1) {
            str[ii] = arbitrary_buffer[ii + 8];
        }
        return ArbitraryType{
            .size = size,
            .line = str
        };
    }
    else {
        std.debug.print("Did not properly read file. {} != {}\n", .{read_sze, last_pos});
        return error.ParseError;
    }
}

pub fn WriteBoxedStructure(endianess: std.builtin.Endian) !BoxedStructure {
    const bto: BoxedStructure = .{
        .flag = true,
        .letter = 'a',
        .u32_value = 456
    };
    const box_file = try cwd.createFile(boxed_type_one_output_name, .{});
    defer box_file.close();
    try box_file.writer().writeStructEndian(bto, endianess);
    return bto;
}
pub fn ReadBoxedStructure(endianess: std.builtin.Endian) !BoxedStructure {
    const box_file = try cwd.openFile(boxed_type_one_output_name,
        .{.mode = .read_only, .lock = .exclusive});
    defer box_file.close();
    const bt1 = try box_file.reader().readStructEndian(BoxedStructure, endianess);
    return bt1;
}

pub fn main() !void {
    const endianess = builtin.target.cpu.arch.endian();
    // Allocating 2Mb of memory for usage.
    // Super overkill for this test.
    var buff: [2048]u8 = undefined;
    var allocator = fba.init(&buff);
    const mem_alloc = allocator.allocator();
    // Wrapping the FixedBufferAllocator with an ArenaAllocator
    // allows us to clean up test in `main()` using `ArenaAllocator.deinit()`
    // `ArenaAllocator.deinit()` cleans up everything allocated using itself.
    var arena = std.heap.ArenaAllocator.init(mem_alloc);
    const arena_alloc = arena.allocator();
    defer arena.deinit();
    std.debug.print("System endianess:             {}\n", .{endianess});
    std.debug.print("Estimated ArbitraryType Size: {}\n", .{@sizeOf(ArbitraryType)});
    std.debug.print("Actual BoxedTypeOne Size:     {}\n", .{@sizeOf(BoxedStructure)});
    // Cleanup Output Directory and Recreate it.
    // Probably better to attempt opening the directory,
    // and on error that it doesn't exist, then creating
    // it.  Since simple program, it is easier to just
    // delete and recreate, since, contents of directory
    // are being overwritten on every execution.
    cwd.deleteTree("output") catch {};
    cwd.makeDir("output") catch {
        std.debug.print("System lacks proper permissions to create output directory.\n", .{});
        return;
    };
    const written_arb_type = try WriteArbitraryType(arena_alloc);
    std.debug.print("Actual Arb Object's Instantiated Size: {}\n", .{(@sizeOf(u64) + written_arb_type.size)});
    const written_box_struct = try WriteBoxedStructure(endianess);
    const read_arb_type = try ReadArbitraryType(arena_alloc);
    const read_box_struct = try ReadBoxedStructure(endianess);
    std.debug.print("----------------------------------------\n", .{});
    std.debug.print("----------------------------------------\n", .{});
    std.debug.print("Boxed Structure Write to Read Likeness\n", .{});
    std.debug.print("\tBoxedStructure.flag:\n\t\tWritten: {} || Read: {} || Likeness {}\n",
        .{written_box_struct.flag, read_box_struct.flag, (written_box_struct.flag == read_box_struct.flag)});
    std.debug.print("\tBoxedStructure.letter:\n\t\tWritten: '{c}' || Read: '{c}' || Likeness {}\n",
        .{written_box_struct.letter, read_box_struct.letter, (written_box_struct.letter == read_box_struct.letter)});
    std.debug.print("\tBoxedStructure.u32_value:\n\t\tWritten: {} || Read: {} || Likeness {}\n",
        .{written_box_struct.u32_value, read_box_struct.u32_value, (written_box_struct.u32_value == read_box_struct.u32_value)});
    std.debug.print("----------------------------------------\n", .{});
    std.debug.print("----------------------------------------\n", .{});
    std.debug.print("Arbitrary Type Write to Read Likeness\n", .{});
    std.debug.print("\tArbitraryType.size: Written:\n\t\t{} || Read: {} || Likeness {}\n",
        .{written_arb_type.size, read_arb_type.size, (written_arb_type.size == written_arb_type.size)});
    std.debug.print("\tArbitraryType.line: Written:\n\t\t\"{s}\" || Read: \"{s}\" || Likeness {}\n",
        .{written_arb_type.line, read_arb_type.line, (std.mem.eql(u8, written_arb_type.line, read_arb_type.line))});
}

test "Expect no memory leaks" {
    try main();
}
