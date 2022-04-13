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

Requires latest master version of Zig.

1. Clone this repository and its submodules (`git clone --recursive` to get submodules)
2. `zig build dist`
3. The resulting files will be in `zig-out/dist`

Note that, by default, `zig build dist` will build everything in debug mode and use all the features of your current CPU (so it may not work on other computers). To make a more portable and faster build, you can use something like `zig build -Drelease-safe -Dcpu=x86_64 dist` instead.
