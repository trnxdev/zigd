# zigd :D ~ Manage your zigd versions on ease!

## Usage: 
### There are 2 executables, `zigdemu` and `zigd`

## zigd

### zigd is an executable to manage versions or other zigd related stuff, by the default zigd files are managed in $HOME/.zigd, you can replace that with the `ZIGD_DIRECTORY` environment variable.

### Commands:

| Command           | What does it do?                                             |
| :---------------: | :----------------------------------------------------------: |
| install [version] | Installs a zig version                                       |
| setup [version]   | Installs a zig version and sets it as default in the config. |
| exists [version]  | Check if a zig version is installed on the system            |
| recache-master    | Re-cache the master version                                  |
| help              | Help screen                                                  |
| version           | Outputs zigd version                                         |
 
## zigdemu

### zigdemu is an executable to "emulate" the zig executable, what it really does it just finds the correct zig version installed with zigd and executes it.
### So just replace zig with zigdemu, `zig build` => `zigdemu build`

### How the zigdemu executable finds the correct version:
##### sorted by Precedence

- zig.ver: A file that contains the zig version, nothing more.
- build.zig.zon: More specifically the minimum_zig_version option
- (zigd directory)/config

### In the config there is also an order

- (path): A version for a specific path, it is search recursively (so if you set /x=0.11.0, /x/d will also use 0.11.0)
- default: It is used as a last resort, pretty much self explainable

## Config Syntax

### As mentioned previously the config file is located at (zigd directory)/config

### You can use # at the start for comments (Works only if it's at the start, won't be checked if it has even one space before)

### And the syntax is just ``k=v``, where k is default or a path and v is a zig version, here is an example:

<sub>~/.zigd/config</sub>
```
default=0.13.0
# My company still uses the old Zig Version >:(
/home/john/work/some_project=0.5.0
```

### Fun fact, if you are in `/home/john/work/some_project/some_deeper_project`, it will still return 0.5.0, because zigd searches for paths recursively! :O 

## Build

### `zig build`

## Important Stuff to know

### `master` version is cached for 12 hours at (zigd directory)/cached_master, you can use `zigd recache-master` to update it.

## An Example Usage

```
[john@coolpc test]$ cat ~/.zigd/config 
default=0.12.0
[john@coolpc test]$ zigdemu version
warning: Zigd could not find zig version "0.12.0" on your system, installing...
0.12.0
[john@coolpc test]$ # Change the Version (in any editor of your choice)
[john@coolpc test]$ cat ~/.zigd/config 
default=0.13.0
[john@coolpc test]$ zigdemu version
warning: Zigd could not find zig version "0.13.0" on your system, installing...
0.13.0
[john@coolpc test]$ # Create a zig.ver file with a version you need
[john@coolpc test]$ cat zig.ver
0.12.0
[john@coolpc test]$ zigdemu version
0.12.0
[john@coolpc test]$ # Use zigd utility for more stuff!
[john@coolpc test]$ zigd exists 0.12.0
Yes!
[john@coolpc test]$ zigd exists 0.11.0
No!
[john@coolpc test]$ zigd install 0.11.0
Installing zig version "0.11.0"
[john@coolpc test]$ zigd exists 0.11.0
Yes!
[john@coolpc test]$ # Change the zig.ver file again...
[john@coolpc test]$ cat zig.ver
0.11.0
[john@coolpc test]$ zigdemu version
0.11.0
[john@coolpc test]$ # Change the version to be master in zig.ver
[john@coolpc test]$ cat zig.ver
master
[trnx@trnxbox zigd]$ zigdemu version
warning: Zigd could not find zig version "master" (0.14.0-dev.14+ec337051a) on your system, installing...
0.14.0-dev.14+ec337051a
[trnx@trnxbox zigd]$ # Wow! This is epic!
```
<sub>0.14.0-dev.14+ec337051a is the master as of making the README</sub>