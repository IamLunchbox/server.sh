#!/usr/bin/env bash
set -e -u -o pipefail

get_tools() {
sudo apt install -y zsh zsh-autosuggestions zsh-syntax-highlighting git

chsh -s /bin/zsh

}
set_prefs() {

cd $HOME
git clone https://github.com/IamLunchbox/dotfiles .dotfiles
cd .dotfiles
./install
}

get_tools
set_prefs

exit 0
