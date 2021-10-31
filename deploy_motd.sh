#!/usr/bin/env
set -u -e -o pipefail

if [[ ! -d ./motd ]]; then
  echo "There seems to be no script directory. Quitting."
  exit 1
fi

if [[ -d "/etc/update-motd.d" ]]; then
  sudo cp -i ./motd/* /etc/update-motd.d
else
    echo "Did not find the update-directory. Quitting"
fi
