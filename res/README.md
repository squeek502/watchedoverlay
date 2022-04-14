## Creating `resource.res.obj`

- Convert the .png into .ico (I've been using https://icoconvert.com/old.php)
- `rc resource.rc` to create `resource.res` (might need to do this from a MSVC command prompt or run the relevant [`vcvars*.bat`](https://docs.microsoft.com/en-us/cpp/build/building-on-the-command-line) to get `rc` in your `PATH`)
- Rename `resource.res` to `resource.res.obj` so that the Zig compiler is able to link it (just `.res` results in a file extension not recognized error, relevant code is [here](https://github.com/ziglang/zig/blob/9c509f1526b4560b4e97367a18755a9d1ae6fcf7/src/Compilation.zig#L4195-L4225) and the relevant issue is [here](https://github.com/ziglang/zig/issues/3702))
