# zigd :D ~ Stop switching zig versions by yourself

## Showcase: https://youtu.be/xDC6NZGONc4

## Usage

### Just reaplace zig with zigd, `zig build` => `zigd build`
### Make sure to have zigd.ver file, with the version you need like: `0.12.0-dev.108+5395c2786`

## Commands

### d-install <Version>, installs the <Version> of zig into zigd's cache (which is located at `~/.zigd/versions`).

## Config

### Now zigd supports a config file, which is located at `~/.zigd/config`
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
### It also supports subdirectories, so if you have a project at `/home/john/Projects/dummy/dummy0`
### and require version 0.11.0 you can add this to the config file:
```
    /home/john/Projects/dummy=0.11.0
```

## Todos

- [ ] Clean-Up Code
- [x] Auto-Install Zig
- [ ] Support for VSCode zls plugin
- [x] Support for config (partially?)
- [x] Implement own tar.xz extractor (needs fixing)
- [ ] Add tests
- [x] Add d-set-default command
- [ ] Add d-set-workspace command
- [ ] Fetching "master" on each request? Doesn't sound good for perfomance, maybe check it daily?

## FAQ

### Why implement own tar.xz extractor?
#### The one in std is very slow, and I couldn't find any other zig implementation of tar.xz extractor.
#### Writing it in zig is also a bit hard so I used libarchive from C and made my own little wrapper for it.

## Troubleshooting

### My file gets wiped on save
#### ~~Set `zig.formattingProvider` to `zls`, should fix it.~~ Fixed in [#1](https://github.com/TiranexDev/zigd/pull/1)
