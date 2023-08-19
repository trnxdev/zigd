# zigd :D ~ Stop switching zig versions by yourself

## Showcase: https://youtu.be/xDC6NZGONc4

## Usage

### Just reaplace zig with zigd, `zig build` => `zigd build`
### Make sure to have zigd.ver file, with the version you need like: `0.12.0-dev.108+5395c2786`

## Commands

### d-install <Version>, installs the <Version> of zig into zigd's cache.


## Config

### Now zigd supports a config file, which is located at `~/.zigdconfig`
### The content can be like this:
```
    default=0.12.0-dev.108+5395c2786
```
### This will set the default version to 0.12.0-dev.108+5395c2786, so if zigd.ver is not found, it will use this version.
### You can also set the default version of workspace, by adding this
```
    /home/john/Projects/dummy=0.12.0-dev.108+5395c2786
```
### Comments can be added by adding a `#` at the start of the line.
```
    #/home/john/Projects/dummy=0.12.0-dev.108+5395c2786
```
## Todos

- [ ] Clean-Up Code
- [x] Auto-Install Zig
- [ ] Support for VSCode zls plugin
- [x] Support for config (partially?)
- [x] Implement own tar.xz extractor (needs fixing)
- [ ] Add tests
- [ ] Add d-set-default command
- [ ] Add d-set-workspace command

## FAQ

### Why implement own tar.xz extractor?
#### The one in std is very slow, and I couldn't find any other zig implementation of tar.xz extractor.
#### Writing it in zig is also a bit hard so I used libarchive from C and made my own little wrapper for it.