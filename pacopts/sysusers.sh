#!/usr/bin/bash
#
# Authors:
# Eric Vidal <eric@obarun.org>
#
# Copyright (C) 2015-2017 Eric Vidal <eric@obarun.org>
#
# This script is under license BEER-WARE
# "THE BEER-WARE LICENSE" (Revision 42):
# <eric@obarun.org> wrote this file.  As long as you retain this notice you
# can do whatever you want with this stuff. If we meet some day, and you think
# this stuff is worth it, you can buy me a beer in return.   Eric Vidal

# ${1} path to the file
# ${2} file to parse, can be a list e.g. "nbd.conf quemu.conf"
parse_file(){
	
	local tidy_loop path_file check parse_check
	local -a named
	
	path_file="${1}"
	named=( "${2}" )
	
	for tidy_loop in ${path_file}/${named[@]}; do
		
		tidy_loop=${tidy_loop##*/}

		while read check; do
	
			while read -d " " parse_check;do 
				case $parse_check in 
					u|g|m|r)
						parse_line "${parse_check}" "${check} "
						;;
					*) continue ;;
				esac
			done <<< "${check}"
	
		done < "${path_file}/${tidy_loop}"
	
	done 
	
	unset named tidy_loop path_file check parse_check
}

# {1} sysusers options : mean u,g,m or r
# {2} complete line to parse
parse_line(){
	 
	opts="${1}"
	line="${2}"
	
	case "${opts}" in
		u) 	line_u		
			;;
		g) 	line_g
			;;
		m) 	line_m
			;;
		r)	line_r
			;;
	esac	
	
	
}

# {1} line to parse
check_args(){
	
	local what element
	what="${1}"

	while read -d " " element; do
		case "${element}" in
			u|g|r) continue 
					;;
			m) 	named_g=$(awk -F " " '{print $2 }' <<< ${what})
				group_g=$(awk -F " " '{print $3 }' <<< ${what})
				;;	
			\"*) comment_=$(awk -F "\"*\"" '{ print $2 }' <<< ${what})
				;;
			*[0-9])
				uidgid="${element}"		
				;;
			/*)
				directory_="${element}"
				;;
			-) 	continue
				;;
			*\") continue
				;;
			*[a-z]|*[A-z])
				echo ${what} | awk -F "${element}" '{ print $1 }' | grep \" &>/dev/null
				if [[ $? -eq 0 ]]; then
					continue
				else
					named_="${element}"
				fi
				;;
		esac
	done <<< "${what}"
	
	unset what element
}


line_u(){
	local named_ directory_ optdirectory_ optdirectory_v uidgid optgid optgid_v optuid optuid_v comment_ optcomment optcomment_v

	check_args "${line}"
	
	if [[ -z "${directory_}" ]]; then
		optdirectory="-d"
		optdirectory_v="/"
	else
		optdirectory="-d"
		optdirectory_v="${directory_}"
	fi
	if [[ -z "${uidgid}" ]]; then
		optgid=""
		optgid_v=""
		optuid=""
		optuid_v=""
	else
		optgid="-g"
		optgid_v="${uidgid}"
		optuid="-u" 
		optuid_v="${uidgid}"
	fi
	if [[ -z "${comment_}" ]]; then
		optcomment=""
		optcomment_v=""
	else
		optcomment="-c" 
		optcomment_v="${comment_}"
	fi
	
	getent group ${named_} &>/dev/null
	if [[ $? -eq 0 ]]; then
		out_info "group ${named_} already exist, nothing to do"
	else
		out_action "Creating group ${named_} with the option(s):"
		out_action "${optgid} ${optgid_v}" 
		groupadd -r ${optgid} ${optgid_v} ${named_} || die " Impossible to create group ${named_}"
	fi
	
	getent passwd ${named_} &>/dev/null
	if [[ $? -eq 0 ]]; then
		out_info "user ${named_} already exist, nothing to do"
	else
		out_action "Creating user ${named_} with the option(s):"
		out_action "${optuid} ${optuid_v} ${optgid} ${optgid_v} ${optdirectory} ${optdirectory_v} ${optcomment} ${optcomment_v} -s /sbin/nologin"
		if [[ -z "${comment_}" ]]; then
			useradd -r ${optuid} ${optuid_v} ${optgid} ${optgid_v} ${optdirectory} ${optdirectory_v} -s /sbin/nologin ${named_}	|| die " Impossible to create user ${named_}"
		else
			useradd -r ${optuid} ${optuid_v} ${optgid} ${optgid_v} ${optdirectory} ${optdirectory_v} "${optcomment}" "${optcomment_v}" -s /sbin/nologin ${named_}	|| die " Impossible to create user ${named_}"
		fi
	fi
	
	unset named_ directory_ optdirectory_ optdirectory_v uidgid optgid optgid_v optuid optuid_v comment_ optcomment optcomment_v
}
line_g(){
	local uidgid optgid optgid_v optuid optuid_v named_
	
	check_args "${line}"
	
	if [[ -z "${uidgid}" ]]; then
		optgid=""
		optgid_v=""
		optuid=""
		optuid_v=""
	else
		optgid="-g"
		optgid_v="${uidgid}"
		optuid="-u" 
		optuid_v="${uidgid}"
	fi
	
	getent group ${named_} &>/dev/null
	if [[ $? -eq 0 ]]; then
		out_info "group ${named_} already exist, nothing to do"
	else	
		out_action "Creating group ${named_} with the option(s):"
		out_action "${optgid} ${optgid_v}"
		groupadd -r ${optgid} ${optgid_v} ${named_} || die " Impossible to create group ${named_}"
	fi
	
	unset uidgid optgid optgid_v optuid optuid_v named_
}

line_m(){
	local named_g group_g uidgid optgid optgid_v optuid optuid_v directory_ optdirectory_ optdirectory_v comment_ optcomment optcomment_v
	
	check_args "${line}"
	
	if [[ -z "${directory_}" ]]; then
		optdirectory=""
		optdirectory_v=""
	else
		optdirectory="-d"
		optdirectory_v="${directory_}"
	fi
	
	if [[ -z "${uidgid}" ]]; then
		optgid=""
		optgid_v=""
		optuid=""
		optuid_v=""
	else
		optgid="-g"
		optgid_v="${uidgid}"
		optuid="-u" 
		optuid_v="${uidgid}"
	fi
	
	if [[ -z "${comment_}" ]]; then
		optcomment=""
		optcomment_v=""
	else
		optcomment="-c" 
		optcomment_v="${comment_}"
	fi
	
	getent group ${group_g} &>/dev/null
	if [[ $? -ne 0 ]]; then
		out_info "group ${group_g} does not exist, create it"
		groupadd -r ${optgid} ${optgid_v} ${group_g} || die " Impossible to create group ${group_g}"
	fi
	
	getent passwd ${named_g} &>/dev/null
	if [[ $? -ne 0 ]]; then
		out_info "user ${named_g} does not exist, create it"
		if [[ -z "${comment_}" ]]; then
			useradd -r ${optuid} ${optuid_v} ${optgid} ${optgid_v} ${optdirectory} ${optdirectory_v} ${named_g} || die " Impossible to create user ${named_g}"
		else
			useradd -r ${optuid} ${optuid_v} ${optgid} ${optgid_v} ${optdirectory} ${optdirectory_v} "${optcomment}" "${optcomment_v}" ${named_g} || die " Impossible to create user ${named_g}"
		fi
	fi
	
	out_action "Add user ${named_g} to group ${group_g}"
	gpasswd -a ${named_g} ${group_g} || die " Impossible to add ${named_g} to group ${group_g}"
	
	unset named_g group_g uidgid optgid optgid_v optuid optuid_v directory_ optdirectory_ optdirectory_v comment_ optcomment optcomment_v
}

line_r(){
	out_info "Pacopts cannot parse the file ${path_file}/${named} for r line,"
	out_info "you need to do it manually"
	break
}
