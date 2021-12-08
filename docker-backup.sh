#!/usr/bin/env bash
set -u -o pipefail

## To-do
- Deploy an .env-file and source it from this script, so this script can be updated independently. 
- move this script to a different repo and set a specific repo and set a gitignore, making sure the env-file wont be distributed
- move a level above the docker-directories to archive less directories

## set these - right now they are empty and the script will fail due to unset vars =)
docker_path=
services=()
nfs_share=
user=
additional_dirs=("")
## default vars
starting_point="$(pwd)"
backup_dir="docker-backup-$(date +%s)"
backup_path="$(realpath ${nfs_share})/${backup_dir}"
help="$0 run|dry-run
A small helper script to backup a docker-compose directory to an nfs share.
"

##checks for vailidity of settings
if [[ ${#services[@]} -lt 1 ]]; then
  echo "You have given no services to backup."
  echo "$help"
  exit 1
fi

if [[ $# = 1 ]]; then
  case $1 in
    "run")
      true
      ;;
    *)
      echo "I could not understand you. Quitting."
      echo "$help"
      exit 1
      ;;
  esac
else
  echo "$help"
  exit 0
fi

if [[ -d /etc/nginx ]]; then
  additional_dirs+="/etc/nginx"
fi
## run



if [[ -d ${nfs_share} ]] && [[ $(mount -l | grep "${nfs_share}") ]]; then
  sudo -u ${user} rm -rf ${nfs_share}/*
  sudo -u ${user} mkdir ${backup_path}
  for service in ${services[@]}; do
    servicepath="$(realpath ${docker_path})/${service}"
    cd $servicepath
    docker-compose down
    tar -cpz --acls --xattrs -f - $servicepath ${additional_dirs[@]} | sudo -u ${user} tee ${backup_path}/${service}.tar.gz 1>/dev/null
  done <<< "${services}"

  for service in ${services[@]}; do
    servicepath="$(realpath ${docker_path})/${service}"
    cd $servicepath
    docker-compose up -d
  done <<< "${services}"
else
  echo "The backup-directory does not seem to exist or is not mounted right now."
  exit 1
fi

exit 0
