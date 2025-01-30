package engine

import "core:os"
import "core:strings"
import "core:strconv"
import "core:fmt"

ObjModel :: struct {
    v:          [dynamic][3]f32,  
    vt:         [dynamic][2]f32, 
    vn:         [dynamic][3]f32,  
    f:          [dynamic][3]int,       
    normals:    [dynamic][3]f32,
    indices:    [dynamic]u32,
    vertexMap: map[string]int,
    uniqueVerts: [dynamic]Vertex,
    // materials:   [dynamic]string,   // mtllib
}

LoadObj :: proc(filename: string) -> ([]Vertex, [dynamic][3]f32, [dynamic]u32)
{
    obj: ObjModel

    data, ok := os.read_entire_file(filename)

    if !ok {
        LogError("Could not read file!")
        return {}, {}, {}
    }
    defer delete(data)

    it := string(data)
    for line in strings.split_lines_iterator(&it)
    {
        entry := strings.split(line, " ")
        if entry[0] == "v" {
            append(&obj.v, ReadVertexData(entry))
        }
        if entry[0] == "vt" {
            append(&obj.vt, ReadTexCoordData(entry))
        }
        if entry[0] == "vn" {
            append(&obj.vn, ReadNormalData(entry))
        }
        if entry[0] == "f" {
            ReadFaceData(entry, &obj)
        }
        // if entry[0] == "mtllib" {
        //     append(&obj.materials, entry[1])
        // }
    }

    return obj.uniqueVerts[:], obj.normals, obj.indices
}

ReadVertexData :: proc(entry: []string) -> [3]f32
{
    return {
        cast(f32)strconv.atof(entry[1]),
        cast(f32)strconv.atof(entry[2]),
        cast(f32)strconv.atof(entry[3])
    }
}

ReadTexCoordData :: proc(entry: []string) -> [2]f32
{
    return {
        cast(f32)strconv.atof(entry[1]),
        1 - cast(f32)strconv.atof(entry[2])
    }
}

ReadNormalData :: proc(entry: []string) -> [3]f32
{
    return {
        cast(f32)strconv.atof(entry[1]),
        cast(f32)strconv.atof(entry[2]),
        cast(f32)strconv.atof(entry[3])
    }
}

ReadFaceData :: proc(entry: []string, using obj: ^ObjModel)
{
    for i := 1; i <= len(entry)-1; i += 1
    {
        vertexData := strings.split(entry[i], "/")

        posIdx := strconv.atoi(vertexData[0])
        texIdx := -1
        normIdx := -1
        
        if len(vertexData) > 1 && vertexData[1] != "" {
            texIdx = strconv.atoi(vertexData[1])
        }
        if len(vertexData) > 2 && vertexData[2] != "" {
            normIdx = strconv.atoi(vertexData[2])
        }

        posIdx -= 1
        if texIdx != -1 {
            texIdx -= 1
        }
        if normIdx != -1 {
            normIdx -= 1
        }

        vertKey := fmt.tprintf("%d%d%d", posIdx, texIdx, normIdx)
        vertIdx, exists := vertexMap[vertKey]
        if !exists {
            newVert := Vertex{
                pos = v[posIdx],
                texCoord = texIdx >= 0 ? vt[texIdx] : [2]f32{0,0},
                normals = normIdx >= 0 ? vn[normIdx] : [3]f32{0,0,0},
            }

            vertIdx = len(uniqueVerts)
            vertexMap[vertKey] = vertIdx
            append(&uniqueVerts, newVert)
        }

        append(&indices, u32(vertIdx))
    }
}