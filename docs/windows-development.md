# Windows development

The supported Windows build is native x86-64 using Crystal's MSVC target. It
uses the Win32 frontend and SDL2's Visual C++ development package.

## Prerequisites

- Crystal 1.18.2 for `x86_64-pc-windows-msvc` (managed by mise)
- Visual Studio 2022 C++ build tools
- SDL2 2.32.10 Visual C++ development package
- PowerShell 7

Set `SWANIUM_SDL2_DIR` to the extracted `SDL2-2.32.10` directory. It must
contain `include/SDL.h`, `lib/x64/SDL2.lib`, and `lib/x64/SDL2.dll`. Run builds
from an x64 Native Tools command prompt:

```powershell
mise run spec
mise run build-windows
mise run package-windows
```

Crystal's runtime dependencies and the Visual C++ runtime are statically linked.
The ZIP contains only the executable, `SDL2.dll`, README, and license. User
state is stored below `%LOCALAPPDATA%\swanium-crystal`.

## ARM64 status

ARM64 is not published yet. Crystal 1.18.2, which is pinned by this repository,
does not provide a matching Windows ARM64 MSVC distribution. The frontend and
build script select SDL2's `lib/arm64` directory on an ARM64 host, so the
application code is prepared for it, but enabling release CI must wait for a
compatible Crystal/MSVC compiler package and a successful native test run.
