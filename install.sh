#!/usr/bin/env sh

if ! [ -x "$(command -v wget)" ]; then
    echo 'wget is required to install zigd'
    exit 1
fi

# Setup
mkdir -p $HOME/.zigd/bin

# Zigd
wget https://github.com/trnxdev/zigd/releases/latest/download/zigd -O $HOME/.zigd/bin/zigd
chmod +x $HOME/.zigd/bin/zigd

# Zigdemu
wget https://github.com/trnxdev/zigd/releases/latest/download/zigdemu -O $HOME/.zigd/bin/zigdemu
chmod +x $HOME/.zigd/bin/zigdemu

# Yipee! You installed zigd
echo 'Succesfully installed! Now do `zigd setup [a zig version of your choice]`'
echo 'Also, you have to add `export PATH=$HOME/.zigd/bin:$PATH` to your ~/.bashrc'
echo 'and then run `source ~/.bashrc` in this terminal to start using zigd!'

exit 0
