package engine

import "core:fmt"
import "core:strings"
import "base:runtime"

// ██       ██████   ██████   ██████  ███████ ██████  
// ██      ██    ██ ██       ██       ██      ██   ██ 
// ██      ██    ██ ██   ███ ██   ███ █████   ██████  
// ██      ██    ██ ██    ██ ██    ██ ██      ██   ██ 
// ███████  ██████   ██████   ██████  ███████ ██   ██ 

@(private="file")
LogType :: enum {
    Normal,
    Warning,
    Error,
}

when ODIN_DEBUG {
    IS_DETAILED :: true
} else {
    IS_DETAILED :: false
}

@(private="file")
Log :: proc(type: LogType, msg: string, location: runtime.Source_Code_Location, isDetailed: bool = false)
{
    prefix: string
    coloredPrefix: string
    coloredSuffix: string = "\x1b[0m"
    switch type {
        case .Normal:
            prefix = "[LOG]"
            coloredPrefix = fmt.tprint("\x1b[92m", prefix)
        case .Warning:
            prefix = "[WARNING]"
            coloredPrefix = fmt.tprint("\x1b[33m", prefix)
        case .Error:
            prefix = "[ERROR]"
            coloredPrefix = fmt.tprint("\x1b[31m", prefix)
    }

    coloredPrefix, _ = strings.replace(coloredPrefix, " ", "", 1) // Removes weird space infront of prefix, no clue why this happens yet
    fmt.print(coloredPrefix)
    if isDetailed {
        fmt.printf(" %s\nat: %s:%d: %s%s\n", msg, location.file_path, location.line, location.procedure, coloredSuffix)
    } else {
        fmt.printf(" %s%s\n", msg, coloredSuffix)
    }
}

LogInfo :: proc(msg: string, location:=#caller_location, isDetailed: bool = false)
{
    Log(LogType.Normal, msg, location, (isDetailed && IS_DETAILED))
}

LogWarning :: proc(msg: string, location:=#caller_location, isDetailed: bool = true)
{
    Log(LogType.Warning, msg, location, (isDetailed && IS_DETAILED))
}

LogError :: proc(msg: string, location:=#caller_location, isDetailed: bool = true)
{
    Log(LogType.Error, msg, location, (isDetailed && IS_DETAILED))
}