package engine


API :: enum {
    Vulkan,
    OpenGL,
}

Vertex :: struct {
    pos:    [2]f32,
    color:  [3]f32,
}