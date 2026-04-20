const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

pub fn i32tof32(value: i32) f32 {
    return @as(f32, @floatFromInt(value));
}

pub fn usizetof32(value: usize) f32 {
    return @as(f32, @floatFromInt(value));
}

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

pub const button_spacing = 12;
pub const button_height = 30;

pub fn checkbox(x: i32, y: i32, width: i32, height: i32, label: [:0]const u8, value: *bool) void {
    const bounds = rl.Rectangle{ .x = i32tof32(x), .y = i32tof32(y), .width = i32tof32(width), .height = i32tof32(height) };
    _ = rg.checkBox(bounds, label, value);
}

pub fn btn(x: i32, y: i32, width: i32, height: i32, label: [:0]const u8) bool {
    const bounds = rl.Rectangle{ .x = i32tof32(x), .y = i32tof32(y), .width = i32tof32(width), .height = i32tof32(height) };
    return rg.button(bounds, label);
}

pub fn btnDown(x: i32, y: i32, width: i32, height: i32, label: [:0]const u8) bool {
    const bounds = rl.Rectangle{ .x = i32tof32(x), .y = i32tof32(y), .width = i32tof32(width), .height = i32tof32(height) };
    _ = rg.button(bounds, label);
    // check if button is currently pressed via mouse or touch input
    if (rl.checkCollisionPointRec(rl.getMousePosition(), bounds)) {
        if (rl.isMouseButtonDown(rl.MouseButton.left)) {
            return true;
        }
    }
    if (rl.getTouchPointCount() > 0) {
        if (rl.checkCollisionPointRec(rl.getTouchPosition(0), bounds)) {
            return true;
        }
    }
    return false;
}

pub fn backBtn() bool {
    const size = button_height;
    return rg.button(.init(button_spacing, button_spacing, size, size), "<");
}

pub fn drawTextCentered(text: [:0]const u8, font_size: i32, color: rl.Color) void {
    const text_width = rl.measureText(text, font_size);
    const offset_x = @divTrunc(rl.getRenderWidth(), 2) - @divTrunc(text_width, 2);
    const offset_y = @divTrunc(rl.getRenderHeight(), 2) - @divTrunc(font_size, 2);
    rl.drawText(text, offset_x, offset_y, font_size, color);
}
