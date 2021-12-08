#!/usr/bin/env
set -u -o pipefail

if [[ ! -d ./motd ]]; then
  echo "There seems to be no script directory. Quitting."
  exit 1
else
  sudo cp -i ./motd/* /etc/update-motd.d/
  if [[ $? -eq 0 ]]; then
    echo "Did successfully copy the files to the destination :("
  fi
fi
