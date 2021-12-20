#!/usr/bin/env bash
set -e -u -o pipefail

cmd=$1
help=""

confirmer() {
while true; do
  echo $1
  read confirm
  case $confirm in
    "Y"|"y"|"yes"|"Y")
    return 0
    ;;
    "N"|"n"|"no"|"No")
    echo "Exiting."
    exit 1
    ;; 
    *)
    echo "Undefined your choice"
    ;;
  esac
done
}

prep() {
if [[ $(id -u) -eq 0 ]]; then
  confirmer "Warning: You are runnung as root and could deploy stuff at places, where they don't belong. Continue? [Y/N]"
elif [[ ! command -v sudo ]]; then
  "You don't have sudo installed. Setting it up requires a relog. Aborting."
fi
}

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

if [[ $# -lt 1 ]]; then
  echo "You better give a command to execute"
  echo "$help"
  exit 1
fi

for var in $@; do
  case $var in 
    "help")


prep
get_tools
set_prefs

exit 0
