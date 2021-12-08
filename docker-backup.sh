#!/usr/bin/env bash
set -u -o pipefail

## set these variables in an .env-file within this directory
#service_path=""
#services=("")
#backup_location=""
#user=""
#additional_dirs=("")
#post_exec_cmd=""

## default vars  
help="$0 run|dry-run
A small helper script to backup a docker-compose directory to an nfs share.
"
alias realpath="realpath -e"

prepare() {
if [[ -d "${nfs_share}" ]] && [[ $(mount -l | grep "${nfs_share}") ]]; then
  sudo -u ${user} rm -rf "${nfs_share}"/*
  sudo -u ${user} mkdir "${backup_path}"
else
  echo "Either your backup location does not exist or is not mounted. Exiting."
  exit 2
fi

if [[ ! -f "./.env" ]]; then
  echo "You did not provide a necessary environment file. Exiting."
  exit 3
else
  source "./.env"
  starting_point="$(pwd)"
  backup_dir="backup-$(date +%s)"
  backup_path="$(realpath "${backup_location}")/${backup_dir}"
fi

if [[ ${#services[@]} -lt 1 ]]; then
  echo "You have given no services to backup."
  echo "$help"
  exit 1
fi


}

docker_backup() {
for service in ${services[@]}; do
    servicepath="$(realpath "${service_path}")/${service}"
    cd $servicepath
    docker-compose down
    cd ..
    tar -cpz --acls --xattrs -f - "${service}" | sudo -u ${user} tee "${backup_path}"/"${service}".tar.gz 1>/dev/null
done <<< "${services}"

for service in ${services[@]}; do
  servicepath="$(realpath "${service_path}")/${service}"
  cd $servicepath
  docker-compose up -d
done <<< "${services}"
}


additional_backups() {
if [[ ${#additional_dirs[@]} -gt 0 ]]; then
for directory in ${additional_dirs[@]}; do
  cd "${directory}"
  cd ..
  tar -cpz --acls --xattrs -f - "$(realpath --relative-to="$(pwd)" "$directory")" | sudo -u ${user} tee "${backup_path}"/"$(realpath --relative-to="$(pwd)" "${directory}")".tar.gz 1>/dev/null
done <<< "${additional_dirs}"
fi
}


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

prepare
docker_backup
additional_backups

if [[ ${#post_exec_cmd} -gt 0 ]]; then
  bash -c "${post_exec_cmd}"
fi

exit 0
