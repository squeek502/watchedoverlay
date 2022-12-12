watchedoverlay
==============

A Windows shell extension to mark files with a 'watched' icon, and a utility program to automatically mark things as watched by polling the recently played list of [VLC media player](https://www.videolan.org/vlc/).

![](https://www.ryanliptak.com/misc/watchedoverlay-screenshot.png)

*Note: This is mostly to scratch my own itch, and to learn a bit about using COM from Zig. I have no real plans for this becoming anything more generally useful.*

## Installation

1. Download the [.zip file from Releases](https://github.com/squeek502/watchedoverlay/releases)
2. Unzip to wherever you'd like
3. Run the `install.bat` as Administrator (right click -> Run as administrator)
4. Restart `explorer.exe`, or log out/log back in, or restart your computer

## Building

Note: Last tested with Zig 0.10.0. Pull requests that fix the build for latest master version of Zig are always welcome, though.

1. Clone this repository and its submodules (`git clone --recursive` to get submodules)
2. `zig build dist`
3. The resulting files will be in `zig-out/dist`

Note that, by default, `zig build dist` will build everything in debug mode and use all the features of your current CPU (so it may not work on other computers). To make a more portable and faster build, you can use something like `zig build dist -Drelease-safe -Dcpu=x86_64` instead.

## Overview of the source code

- [dllmain.zig](src/dllmain.zig) has the dll entry point and exports `DllGetClassObject`, which is used to provide `IClassFactory`s for our registered `CLSID`s. Also exports `DllRegisterServer`/`DllUnregisterServer` for integration with [`regsvr32`](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/regsvr32)
- [factory.zig](src/factory.zig) has our `IClassFactory` implementation, which is used to allocate our registered `IShellIconOverlayIdentifier` and `IContextMenu` implementations
- [overlay.zig](src/overlay.zig) has our `IShellIconOverlayIdentifier` implementation, which is used to determine which items to put an icon overlay on
- [context_menu.zig](src/context_menu.zig) has our `IContextMenu` implementation, which is used to add our menu item to the right click context menu
- [db.zig](src/db.zig) provides an interface to the sqlite database that stores which filepaths are marked as 'watched'
- [watcher-vlc.zig](src/watcher-vlc.zig) implements the polling of the VLC recently played files list and automatically marks things as watched
- [com.zig](src/com.zig), [windows_extra.zig](src/windows_extra.zig), and [registry.zig](src/registry.zig) provide bindings and helpers for various Windows APIs.

## Resources used

- [COM in plain C](https://www.codeproject.com/Articles/13601/COM-in-plain-C) to learn about how to work with COM from C
- [The Complete Idiot's Guide to Writing Shell Extensions](https://www.codeproject.com/Articles/445/The-Complete-Idiots-Guide-to-Writing-Shell-Exten-2) and [apriorit/IconOverlayHandler](https://github.com/apriorit/IconOverlayHandler) for an example of how custom icon overlays/context menu entries can be added (with C++)
- [marlersoft/zigwin32](https://github.com/marlersoft/zigwin32) and [michal-z/zig-gamedev](https://github.com/michal-z/zig-gamedev) for examples of how to create bindings for COM interfaces from Zig
