#!/usr/bin/env bash
set -u -o pipefail

#todo
# set permission-checks to restrict the world from reading and editing

## default vars
help="$0 run|dry-run
A small helper script to backup a docker-compose directory to an nfs share.
"
scriptname="$0"

alias realpath="realpath -e"

prepare() {
if [[ ! -f "./docker-backup.env" ]]; then
  echo "You did not provide a necessary environment file. Exiting."
  exit 1
else
  source "./docker-backup.env"
  starting_point="$(pwd)"
  backup_dir="backup-$(date +%s)"
  backup_path="$(realpath "${backup_location}")/${backup_dir}"
fi
if [[ -d "${backup_location}" ]] && [[ $(mount -l | grep "${backup_location}") ]]; then
  sudo -u ${user} rm -rf "${backup_location}"/*
  sudo -u ${user} mkdir "${backup_path}"
else
  echo "Either your backup location does not exist or is not mounted. Exiting."
  exit 2
fi

if [[ ! $(id -u) == 0 ]]; then
  echo "This script is intended for automated usage and needs to be run as root (as of now).
Otherwise this script could not impersonate a given user."
  exit 3

elif [[ stat ${scriptname} ]]; then
    exit 4

elif [[ stat "docker-backup.env" ]]; then
    exit 5

elif [[ ${#services[@]} -lt 1 ]]; then
  echo "You have given no services to backup."
  echo "$help"
  exit 6
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

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>>docker-backup.log 2>&1

prepare
docker_backup
additional_backups

if [[ ${#post_exec_cmd} -gt 0 ]]; then
  bash -c "${post_exec_cmd}"
fi

exit 0
