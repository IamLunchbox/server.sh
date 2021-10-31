#!/usr/bin/env bash
set -e -u -o pipefail
# sources: https://github.com/imthenachoman/How-To-Secure-A-Linux-Server
# https://static.open-scap.org/ssg-guides/ssg-rhel7-guide-C2S.html
# https://github.com/trimstray/linux-hardening-checklist

compat_check() {
	if [[ $UID == 0 ]]; then
		printf "\n${BRed}Please use this script not as root, this will place, \
configuration files at the wrong place."
		exit 1
	elif [[ -z $(uname -a | grep -i "ubuntu") ]] || [[ -z $(uname -a | grep -i "debian") ]]; then
		printf "\n${BRed}This script was only runs on for Debian and Ubuntu.${NC}\n"
		exit 2
	fi
	printf "${Notiz}Updating the system.\n"
	sudo apt update -y && sudo apt upgrade -y
}

setup_ufw() {
	echo "${ufw_allow}" | sudo tee /etc/ufw/applications.d/default-net 1>/dev/null
	# unset u since a query of unset variables will stop the script
	set +u
	if [[ -n "${SSH_CONNECTION}" ]]; then
		ssh-port=$(echo $SSH_CONNECTION | cut -d " " -f 4)
		sudo ufw allow in ${ssh-port}/tcp comment "allow ssh in from your current ssh-port"
	elif [[ -n "${SSH_CLIENT}" ]]; then
			ssh-port=$(echo $SSH_CLIENT | cut -d " " -f 3)
			sudo ufw allow in ${ssh-port}/tcp comment "allow ssh in from your current ssh-port"
	elif [[ -n "${SSH_TTY}" ]]; then
		printf "${Notiz}Detected a ssh connection, but could not determine a port. Aborting ufw setup.\n${NC}"
		return false
	fi
	set -u

	# disable script stop at non-0 exit codes, to enable a firewall reset if need be
	set +e
	sudo ufw allow out "DEFAULT-NET"
	if [[ $(sudo dmesg | grep "Hypervisor detected") ]] && [[ ${command} == "desktop" ]]; then
		# The following services are opened since this operating system is used in a vm
		sudo ufw allow out "DEFAULT-NET VM"
	fi
	set -e
}

enable_firewall() {
	printf "${Notiz}Installing and activating UFW\n${NC}"
	if [[ ! $(dpkg -s ufw 2>/dev/null) ]]; then
	  sudo apt install -y ufw
	fi
	if [[ ${command} == "desktop" ]] && [[ ! $(dpkg -s gufw 2>/dev/null) ]]; then
		sudo apt install -y gufw
	fi
	setup_ufw

	if [[ $? -ne 0 ]]; then
		printf "${Warning} UFW will not be enabled, because some rule could not be set.\n${NC}"
		sudo ufw reset
	else
		#lastly set the defaults deny of traffic
		sudo ufw default deny incoming comment 'deny all incoming traffic'
		sudo ufw default deny outgoing comment 'deny all outgoing traffic'
		sudo ufw enable
		printf "${Notiz}Set up the firewall. You might experience disruptions connecting to unusual ports, like 8080. Use ufw allow PORT then.\n${NC}"
	fi
}

enable_apparmor() {
	if [[ -e /etc/apparmor.d/disable/usr.bin/firefox ]]; then
		printf "${Notiz}Activating apparmor for Firefox using the default profile\n${NC}"
		sudo rm /etc/apparmor.d/disable/usr.bin.firefox
		sudo apparmor_parser /etc/apparmor.d/usr.bin.firefox
	fi
}

harden_pam() {
	# The Password configuration
	if [[ ! $(dpkg -s libpam-pwquality 2>/dev/null) ]]; then
		sudo apt install -y libpam-pwquality
	fi
	if [[ ! -d /etc/security/pwquality.conf.d ]]; then
		sudo mkdir /etc/security/pwquality.conf.d
	fi
	if [[ ! $(grep "password    required    pam_pwquality.so" "/etc/pam.d/common-password") ]]; then
		# enforce the password requirements via pam
		sudo cp --archive "/etc/pam.d/common-password" /etc/pam.d/common-password-COPY-$(date +"%Y%m%d%H%M%S")
		echo "password    required    pam_pwquality.so" | sudo tee -a /etc/pam.d/common-password 1>/dev/null
	fi
	echo "${pam-passwd-config}" | sudo tee "/etc/security/pwquality.conf.d/99-difficult-passwords.conf" 1>/dev/null
	printf "${Notiz}Set up default difficult passwords for any application using pam-common-password\n${NC}"
}

enable_auto_upgrades() {
	if [[ ! $(dpkg -s unattended-upgrades) ]]; then
		sudo apt install -y unattended-upgrades
		printf "${Notiz}Installed unattended-upgrades. By default, this will pull and install security updates daily.
		Right now the following packages need to be updated:\n${NC}"
		sudo unattended-upgrades --dry-run
	fi
}

change_umask() {
	# set umask to 0027 for the currently used shell
	case ${SHELL} in
		"/usr/bin/bash"|"/bin/bash")
		# Skipping any overwrites if a default umask is already set in bashrc and /etc/profile
			if [[ ! $(grep "umask" /etc/profile) ]]; then
				printf "${Notiz}Entering the default umask 0027 into /etc/profile${NC}"
				echo "umask 0027" | sudo tee -a "/etc/profile" 1>/dev/null
			fi
			if [[ ! $(grep "umask" ${HOME}/.bashrc) ]]; then
				printf "${Notiz}Entering the default umask 0027 into ${HOME}/.bashrc${NC}"
				echo "umask 0027" >> ${HOME}/.bashrc
			fi
			;;

		"/usr/bin/zsh"|"/bin/zsh")
		# Skipping any overwrites if a default value is already set in zshrc and /etc/zsh/zshenv
			if [[ ! $(grep "umask" /etc/zsh/zshenv) ]]; then
				printf "${Notiz}Entering the default umask 0027 into /etc/zshenv${NC}"
				echo "umask 0027" | sudo tee -a /etc/zsh/zshenv 1>/dev/null
			fi
			if [[ ! $(grep "umask" ${HOME}/.zshrc) ]]; then
				printf "${Notiz}Entering the default umask 0027 into ${HOME}/.zshrc${NC}"
				echo "umask 0027" >> ${HOME}/.zshrc
			fi
			;;

			*)
			printf "${BRed}Could not set default umask, since I don't support ${SHELL}!\n${NC}"
			;;
	esac
}

secure_important_dirs(){
	#todo
	chmod 750 "${HOME}"
	printf "${Notiz}The permission of ${HOME} was set to 750${NC}"
	if [[ ! $(grep "proc     /proc     proc     defaults,hidepid=2     0     0" "/etc/fstab") ]]; then
		sudo cp --archive /etc/fstab /etc/fstab-COPY-$(date +"%Y%m%d%H%M%S")
		echo -e "\nproc     /proc     proc     defaults,hidepid=2     0     0         # added by $(whoami) on $(date +"%Y-%m-%d @ %H:%M:%S")" | sudo tee -a /etc/fstab 1>/dev/null
	fi
}

secure_mount() {
	case ${SHELL} in
		"/usr/bin/bash"|"/bin/bash")
		# Skipping any overwrites if a default umask is already set in bashrc and /etc/profile
			if [[ ! $(grep "mount -o noexec,nosuid" /etc/profile) ]]; then
				echo 'alias mount="mount -o noexec,nosuid"' | sudo tee -a /etc/profile 1>/dev/null
				printf "${Notiz}The alias mount=\"mount -o noexec,nosuid\" was entered into /etc/profile${NC}"
			fi
			if [[ ! $(grep "mount -o noexec,nosuid" ${HOME}/.bashrc) ]]; then
				echo 'alias mount="mount -o noexec,nosuid"' >> ${HOME}/.bashrc
				printf "${Notiz}The alias mount=\"mount -o noexec,nosuid\" was entered into ${HOME}/.bashrc${NC}"
			fi
			;;
		"/usr/bin/zsh"|"/bin/zsh")
		# Skipping any overwrites if a default value is already set in zshrc and /etc/zsh/zshenv
			if [[ ! $(grep "mount -o noexec,nosuid" /etc/zsh/zshenv) ]]; then
				echo 'alias mount="mount -o noexec,nosuid"' | sudo tee -a /etc/zsh/zshenv 1>/dev/null
				printf "${Notiz}The alias mount=\"mount -o noexec,nosuid\" was entered into /etc/zshenv${NC}"
			fi
			if [[ ! $(grep "mount -o noexec,nosuid" ${HOME}/.zshrc) ]]; then
				echo 'alias mount="mount -o noexec,nosuid"' >> "${HOME}/.zshrc"
				printf "${Notiz}The alias mount=\"mount -o noexec,nosuid\" was entered into ${HOME}/.zshrc${NC}"
			fi
			;;
		*)
			printf "${BRed}Could not set alias mount=\"mount -o noexec,nosuid\" since ${SHELL} is not supported!\n${NC}"
			;;
	esac
	if [[ ! $(systemctl status udisks2.service | grep "Loaded: masked (Reason: Unit udisks2.service is masked.)") ]]; then
		printf "${Notiz}Disabling udisks2.service. This will disable any automounting - even using nautilus!\n${NC}"
		sudo systemctl stop udisks2.service
		sudo systemctl mask udisks2.service
	fi
	# Add to /etc/modprobe.d/fs-blacklist.conf:
	for i in ${filesystem_blacklist}; do
		if [[ ! -f /etc/blacklist-custom.conf ]]; then
			printf "${Notiz}Blacklisting filesystem driver ${i}, because he is usually not needed.\n${NC}"
			echo "${i}" | sudo tee /etc/blacklist-custom.conf 1>/dev/null
		elif [[ ! $(grep "${i}" /etc/blacklist-custom.conf) ]]; then
			printf "${Notiz}Blacklisting filesystem driver ${i}, because he is usually not needed.\n${NC}"
			echo "${i}" | sudo tee -a /etc/blacklist-custom.conf 1>/dev/null
		fi
	done
}

misc_hardening() {
	# Add to /etc/sysctl.d/local.conf:
	if [[ -f /etc/sysctl.d/local.conf ]]; then
		if [[ ! $(grep 's.suid_dumpable = 0' /etc/sysctl.d/local.conf) ]]; then
			echo 's.suid_dumpable = 0' | sudo tee -a /etc/sysctl.d/local.conf 1>/dev/null
		fi
	else
		echo 's.suid_dumpable = 0' | sudo tee -a /etc/sysctl.d/local.conf 1>/dev/null
	fi
	if [[ ! $(grep '*     hard   core    0' /etc/security/limits.conf) ]]; then
		echo '*     hard   core    0' | sudo tee -a /etc/security/limits.conf 1>/dev/null
	fi
}

version(){
	#todo
	if [[ false ]]; then
		echo "this is a placeholder"
	fi
}

#sets $NAME, $VERSION, $ID, $ID_LIKE, $VERSION_CODENAME and $UBUNTU_CODENAME
source /etc/os-release

#Start off by defining strictly necessary variables

# Colors
RED='\033[0;31m'
NC='\033[0m'
BRed='\033[1;31m'
BYellow='\033[1;33m'
BPurple='\033[1;35m'
BGreen='\033[1;32m'
Notiz="\n${BYellow}Note: ${NC}"
System="\n${BPurple}Warning: ${NC}"

scriptname=$0
ufw_allow="[DEFAULT-NET]
title=DEFAULT-NET
description=DNS, NTP, HTTP, HTTPS, NTP and DHCP
ports=53|123|80/tcp|443/tcp|67|68

[DEFAULT-NET VM]
title=DEFAULT-Net-VM
description=SSH,SMTP,IMAP,RDP
ports=22/tcp|25/tcp|465/tcp|587/tcp|143/tcp|993/tcp|3389|3390
"

filesystem_blacklist="install freevxfs /bin/true
install udf /bin/true
install squashfs /bin/true
install hfsplus /bin/true
install jffs2 /bin/true
install hfs /bin/true
install cramfs /bin/true"

pam_passwd_config="minlen = 12
minclass = 4
maxrepeat = 4
dictcheck = 1
usercheck = 1
enforcing = 1
retry = 3
enforce_for_root"

# messages
usage="${scriptname} server|desktop|help\n
A script to harden a linux system. There are no other options yet.
"
usage_short="${scriptname} server|desktop|help
"

if [[ $# -ne 1 ]]; then
	printf "${usage_short}${System}There has been no argument given.${NC}\n"
  exit 4
fi

command=$1

case ${command} in
	"desktop")
	compat_check
	enable_firewall
	enable_apparmor
	harden_pam
	enable_auto_upgrades
	change_umask
	secure_important_dirs
	secure_mount
	misc_hardening
	;;

	"server")
	compat_check
	enable_firewall
	harden_pam
	enable_auto_upgrades
	change_umask
	secure_important_dirs
	secure_mount
	misc_hardening
	;;

	*)
		printf "${usage}"
	;;
esac
