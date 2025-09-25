//! A `Trait` is a virtual component that can be queried based
//! on the presence of another component. For example, you can
//! have a `Renderable` struct, and specify that `Circle` and
//! `Square` components both have `Renderable` as a trait.
//! Then you can query for Renderable entities and get both
//! Circle and Square entities in the result.

const std = @import("std");
const root = @import("root.zig");
const ComponentId = root.ComponentId;
const componentId = root.componentId;

id: ComponentId,
kind: Kind,

const Trait = @This();

pub const Kind = union(enum) {
    Marker,
    IdenticalLayout,
    Grouped: struct {
        group_key: i32,
    },
};

pub fn maybeFrom(comptime ComponentT: anytype) ?Trait {
    // check for the __trait__ declaration
    if (!@hasDecl(ComponentT, "__trait__")) {
        return null;
    }

    const TraitT = ComponentT.__trait__;
    const trait_id = componentId(TraitT);

    // Determine the trait kind based on the trait type
    const trait_kind = switch (@typeInfo(TraitT)) {
        .@"struct" => blk: {
            if (@hasDecl(ComponentT, "__group_key__")) {
                break :blk Trait.Kind{ .Grouped = .{
                    .group_key = ComponentT.__group_key__,
                } };
            }

            // If it's a zero-sized struct, it's a marker trait
            if (@sizeOf(TraitT) == 0) {
                break :blk Trait.Kind.Marker;
            }

            // If it's a struct with the same layout as the component, it's identical layout
            if (@sizeOf(TraitT) == @sizeOf(ComponentT) and
                @alignOf(TraitT) == @alignOf(ComponentT))
            {
                verifyIdenticalLayout(TraitT, ComponentT);
                break :blk Trait.Kind.IdenticalLayout;
            } else {
                @compileError("Trait struct layout does not match component layout");
            }
        },
        else => @compileError("Trait must be a struct"),
    };

    return Trait{
        .id = trait_id,
        .kind = trait_kind,
    };
}

/// Recursively verifies that two types have identical layout at compile time.
/// Supports structs and tagged unions (union(enum)).
fn verifyIdenticalLayout(comptime TraitT: type, comptime ComponentT: type) void {
    // Basic size and alignment check first
    if (@sizeOf(TraitT) != @sizeOf(ComponentT)) {
        @compileError("Types have different sizes: " ++ @typeName(TraitT) ++ " (" ++ std.fmt.comptimePrint("{}", .{@sizeOf(TraitT)}) ++ ") vs " ++ @typeName(ComponentT) ++ " (" ++ std.fmt.comptimePrint("{}", .{@sizeOf(ComponentT)}) ++ ")");
    }

    if (@alignOf(TraitT) != @alignOf(ComponentT)) {
        @compileError("Types have different alignments: " ++ @typeName(TraitT) ++ " (" ++ std.fmt.comptimePrint("{}", .{@alignOf(TraitT)}) ++ ") vs " ++ @typeName(ComponentT) ++ " (" ++ std.fmt.comptimePrint("{}", .{@alignOf(ComponentT)}) ++ ")");
    }

    const trait_info = @typeInfo(TraitT);
    const component_info = @typeInfo(ComponentT);

    // Both types must be the same kind
    if (@as(std.builtin.TypeId, trait_info) != @as(std.builtin.TypeId, component_info)) {
        @compileError("Types are different kinds: " ++ @typeName(TraitT) ++ " vs " ++ @typeName(ComponentT));
    }

    switch (trait_info) {
        .@"struct" => |trait_struct| {
            const component_struct = component_info.@"struct";
            verifyStructLayout(TraitT, ComponentT, trait_struct, component_struct);
        },
        .@"union" => |trait_union| {
            const component_union = component_info.@"union";
            verifyUnionLayout(TraitT, ComponentT, trait_union, component_union);
        },
        .int, .float, .bool, .@"enum", .pointer, .array, .optional => {
            // For primitive types, size and alignment check is sufficient
        },
        else => {
            @compileError("Unsupported type for layout verification: " ++ @typeName(TraitT));
        },
    }
}

fn verifyStructLayout(
    comptime TraitT: type,
    comptime ComponentT: type,
    comptime trait_struct: std.builtin.Type.Struct,
    comptime component_struct: std.builtin.Type.Struct,
) void {
    // Check field count
    if (trait_struct.fields.len != component_struct.fields.len) {
        @compileError("Structs have different field counts: " ++ @typeName(TraitT) ++ " (" ++ std.fmt.comptimePrint("{}", .{trait_struct.fields.len}) ++ ") vs " ++ @typeName(ComponentT) ++ " (" ++ std.fmt.comptimePrint("{}", .{component_struct.fields.len}) ++ ")");
    }

    // Check layout (packed vs not)
    if (trait_struct.layout != component_struct.layout) {
        @compileError("Structs have different layouts: " ++ @typeName(TraitT) ++ " vs " ++ @typeName(ComponentT));
    }

    // Verify each field
    inline for (trait_struct.fields, component_struct.fields) |trait_field, component_field| {
        // Check field offsets
        const trait_offset = @offsetOf(TraitT, trait_field.name);
        const component_offset = @offsetOf(ComponentT, component_field.name);

        if (trait_offset != component_offset) {
            @compileError("Field '" ++ trait_field.name ++ "' has different offsets: " ++ std.fmt.comptimePrint("{}", .{trait_offset}) ++ " vs " ++ std.fmt.comptimePrint("{}", .{component_offset}) ++ " in " ++ @typeName(TraitT) ++ " vs " ++ @typeName(ComponentT));
        }

        // Recursively verify field types
        verifyIdenticalLayout(trait_field.type, component_field.type);
    }
}

fn verifyUnionLayout(
    comptime TraitT: type,
    comptime ComponentT: type,
    comptime trait_union: std.builtin.Type.Union,
    comptime component_union: std.builtin.Type.Union,
) void {
    // Check if both are tagged or untagged
    const trait_is_tagged = trait_union.tag_type != null;
    const component_is_tagged = component_union.tag_type != null;

    if (trait_is_tagged != component_is_tagged) {
        @compileError("Union tag types differ: " ++ @typeName(TraitT) ++ " vs " ++ @typeName(ComponentT));
    }

    // For tagged unions, verify tag types match
    if (trait_is_tagged) {
        verifyIdenticalLayout(trait_union.tag_type.?, component_union.tag_type.?);
    }

    // Check field count
    if (trait_union.fields.len != component_union.fields.len) {
        @compileError("Unions have different field counts: " ++ @typeName(TraitT) ++ " (" ++ std.fmt.comptimePrint("{}", .{trait_union.fields.len}) ++ ") vs " ++ @typeName(ComponentT) ++ " (" ++ std.fmt.comptimePrint("{}", .{component_union.fields.len}) ++ ")");
    }

    // Check layout
    if (trait_union.layout != component_union.layout) {
        @compileError("Unions have different layouts: " ++ @typeName(TraitT) ++ " vs " ++ @typeName(ComponentT));
    }

    // Verify each field by name (unions don't have guaranteed field order)
    inline for (trait_union.fields) |trait_field| {
        var found = false;
        inline for (component_union.fields) |component_field| {
            if (std.mem.eql(u8, trait_field.name, component_field.name)) {
                found = true;
                verifyIdenticalLayout(trait_field.type, component_field.type);
                break;
            }
        }
        if (!found) {
            @compileError("Union field '" ++ trait_field.name ++ "' not found in " ++ @typeName(ComponentT));
        }
    }
}
