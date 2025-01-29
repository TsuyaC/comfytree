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
            coloredPrefix = fmt.tprintf("\x1b[92m%s", prefix)
        case .Warning:
            prefix = "[WARNING]"
            coloredPrefix = fmt.tprintf("\x1b[33m%s", prefix)
        case .Error:
            prefix = "[ERROR]"
            coloredPrefix = fmt.tprintf("\x1b[31m%s", prefix)
    }

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