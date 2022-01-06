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

admin_tools() {
sudo apt install -y zsh zsh-autosuggestions zsh-syntax-highlighting git curl
chsh -s /bin/zsh
cd $HOME
git clone https://github.com/IamLunchbox/dotfiles .dotfiles
cd .dotfiles
./install
curl https://deb.releases.teleport.dev/teleport-pubkey.asc | sudo apt-key add -
sudo add-apt-repository 'deb https://deb.releases.teleport.dev/ stable main'
sudo apt-get update
sudo apt install teleport
}



if [[ $# -lt 1 ]]; then
  echo "You better give a command to execute"
  echo "$help"
  exit 1
fi

for var in $@; do
  if [[ $var =~ "[Hh]elp" ]]; then
    echo "$help"
    exit 0
  fi
done

prep

for var in $@; do
  case $var in 
  "tools")
    admin_tools
    exit 0
    ;;
  *)
    echo "You entered a key, which does not exist"
    exit 1
    ;;
  esac
done

