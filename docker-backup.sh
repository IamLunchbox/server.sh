#!/usr/bin/env bash
set -u -o pipefail

#todo
# set permission-checks to restrict the world from reading and editing

## default vars
help="$0 run|dry-run
A small helper script to backup a docker-compose directory to an nfs share."
scriptname="$0"
timestamp="[$(date +%F-%T]) "
alias realpath="realpath -e"

prepare() {
  echo "${timestamp}Docker Backup start."
  if [[ ! -f "./docker-backup.env" ]]; then
    echo "${timestamp}You did not provide a necessary environment file. Exiting."
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
    echo "${timestamp}Either your backup location does not exist or is not mounted. Exiting."
    exit 2
  fi

  if [[ ! $(id -u) == 0 ]]; then
    echo "${timestamp}This script is intended for automated usage and needs to be run as root (as of now).
Otherwise this script could not impersonate a given user."
    exit 3
  elif [[ ${#services[@]} -lt 1 ]]; then
    echo "${timestamp}You have given no services to backup."
    exit 6
  fi

}

docker_backup() {
for service in ${services[@]}; do
    servicepath="$(realpath "${service_path}")/${service}"
    cd $servicepath
    echo "${timestamp}Turning off ${service}"
    docker-compose down
    cd ..
    echo "${timestamp}Backing up ${service}"
    tar -cpz --acls --xattrs -f - "${service}" | sudo -u ${user} tee "${backup_path}"/"${service}".tar.gz 1>/dev/null
done <<< "${services}"

for service in ${services[@]}; do
  servicepath="$(realpath "${service_path}")/${service}"
  cd $servicepath
  echo "${timestamp}Starting ${service}"
  docker-compose up -d
done <<< "${services}"
}


additional_backups() {
if [[ ${#additional_dirs[@]} -gt 0 ]]; then
  for directory in ${additional_dirs[@]}; do
    cd "${directory}"
    cd ..
    echo "${timestamp}Backing up $directory"
    tar -cpz --acls --xattrs -f - "$(realpath --relative-to="$(pwd)" "$directory")" | sudo -u ${user} tee "${backup_path}"/"$(realpath --relative-to="$(pwd)" "${directory}")".tar.gz 1>/dev/null
  done <<< "${additional_dirs}"
fi
}


if [[ $# = 1 ]]; then
  case $1 in
    "run")
      exec 3>&1 4>&2
      trap 'exec 2>&4 1>&3' 0 1 2 3
      exec 1>>docker-backup.log 2>&1
      ;;
    "quiet")
      true
      ;;
    *)
      echo "${timestamp}I could not understand you. Quitting."
      exit 1
      ;;
  esac
else
  echo "$help"
  exit 0
fi
prepare
if [[ $(date +%H) = 1 ]]; then
  docker_backup
  additional_backups

  if [[ ${#post_run_cmd} -gt 0 ]]; then
    echo "${timestamp}Executing the post run command."
    bash -c "${post_run_cmd}"
    echo "${timestamp}Done."
  fi
else
  if [[ ${#post_exec_cmd} -gt 0 ]]; then
    echo "${timestamp}Executing the post execution-command."
    bash -c "${post_exec_cmd}"
    echo "${timestamp}Done."
  fi
fi
exit 0
