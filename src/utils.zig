const rl = @import("raylib");
const rg = @import("raygui");

/// `rl.getColor` only accepts a `u32`. Performing `@intCast` on the return value
/// of `rg.getStyle` invokes checked undefined behavior from Zig when passed to
/// `rl.getColor`, hence the custom implementation here...
fn getColor(hex: i32) rl.Color {
    var color: rl.Color = .black;
    // zig fmt: off
    color.r = @intCast((hex >> 24) & 0xFF);
    color.g = @intCast((hex >> 16) & 0xFF);
    color.b = @intCast((hex >>  8) & 0xFF);
    color.a = @intCast((hex >>  0) & 0xFF);
    // zig fmt: on
    return color;
}

pub fn getBackgroundColor() rl.Color {
    return getColor(rg.getStyle(.default, .{ .default = .background_color }));
}

pub fn backBtn() bool {
    const size = 30;
    return rg.button(.init(24, 24, size, size), "<");
}

pub fn drawTextCentered(text: [:0]const u8, font_size: i32, color: rl.Color) void {
    const text_width = rl.measureText(text, font_size);
    const offset_x = @divTrunc(rl.getRenderWidth(), 2) - @divTrunc(text_width, 2);
    const offset_y = @divTrunc(rl.getRenderHeight(), 2) - @divTrunc(font_size, 2);
    rl.drawText(text, offset_x, offset_y, font_size, color);
}
