# wordperfect81-modern

Launch Corel WordPerfect 8.1 for Linux on a modern Linux system in a self contained environment.

This repo does not include the WordPerfect binaries. You must supply:

- `corel_linux_1.2.iso`

Check [Internet Archive](https://archive.org/details/corel_linux_1.2). Put that ISO in the repo root, then run:

```bash
./setup.sh
./run-wordperfect.sh
```

If the ISO lives elsewhere, set `COREL_ISO`:

```bash
COREL_ISO=/path/to/corel_linux_1.2.iso ./setup.sh
```

## What It Does

- extracts the WordPerfect 8.1 Debian package and required runtime packages from the supplied Corel Linux 1.2 ISO
- stages old libc5 and X11 runtime libraries locally under `compat/`
- stages classic X11 data and fonts locally under `compat/x11` and `compat/fonts`
- builds a small 32-bit preload shim that bypasses the old libc5 startup crash on modern hosts
- launches WordPerfect in a `bwrap` filesystem view that provides the legacy paths and compatibility runtime it expects
- keeps WordPerfect user config and working state under `state/`
- seeds the full bundled WP Type 1 screen-font set into `app/usr/lib/wp8/shlib10`
- seeds a richer generated `wp.drs` into the staged app tree so Roman/Helve/Courier screen fonts work without an interactive font-install step
- ships precomputed X font index metadata so setup does not need to generate it on the host

## Requirements

- Linux with 32-bit x86 execution enabled
- a working X11 display or Xwayland session
- a host 32-bit glibc loader at `/usr/lib32/ld-linux.so.2`, `/usr/lib/ld-linux.so.2`, or `/lib/ld-linux.so.2`
- `bash`, `bsdtar`, `ar`, `tar`, `find`
- `gcc` with 32-bit build support for `gcc -m32`
- `bwrap`
- optional: `xset` to register the bundled fonts with the X server

## Notes

- This is a compatibility hack, not a period-correct environment.
- The launcher uses `bwrap` because WordPerfect expects hard-coded absolute paths such as `/usr/lib/wp8` and `/usr/X11R6`.
- All WordPerfect config and runtime state is intended to stay inside `state/`.
- `support/wp.drs` is a generated compatibility artifact produced from the bundled WP Type 1 screen-font set and staged to avoid a brittle interactive `xwpfi` install step.
