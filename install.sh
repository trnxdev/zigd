#!/usr/bin/env sh

if ! [ -x "$(command -v wget)" ]; then
    echo 'wget is required to install zigd'
    exit 1
fi

if [[ -z "${ZIGD_DIRECTORY}" ]]; then
  ZIGD_PATH=$HOME/.zigd
else
  ZIGD_PATH=$ZIGD_DIRECTORY
fi

# Setup
mkdir -p $ZIGD_PATH/bin

# Zigd
wget https://github.com/trnxdev/zigd/releases/latest/download/zigd -O $ZIGD_PATH/bin/zigd
chmod +x $ZIGD_PATH/bin/zigd

# Zigdemu
wget https://github.com/trnxdev/zigd/releases/latest/download/zigdemu -O $ZIGD_PATH/bin/zigdemu
chmod +x $ZIGD_PATH/bin/zigdemu

# Yipee! You installed zigd
echo 'Succesfully installed! Now do `zigd setup [a zig version of your choice]`'
echo "Also, you have to add `export PATH=${ZIGD_PATH}/bin:$PATH` to your ~/.bashrc"
echo 'and then run `source ~/.bashrc` in this terminal to start using zigd!'

exit 0
