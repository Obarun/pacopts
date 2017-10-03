#!@BINDIR@/bash
# Copyright (c) 2015-2017 Eric Vidal <eric@obarun.org>
# All rights reserved.
# 
# This file is part of Obarun. It is subject to the license terms in
# the LICENSE file found in the top-level directory of this
# distribution and at https://github.com/Obarun/pacopts/LICENSE
# This file may not be copied, modified, propagated, or distributed
# except according to the terms contained in the LICENSE file.

SYS_PATH=( "/etc/sysusers.d" "/run/sysusers.d" "/usr/lib/sysusers.d" )
SYS_NAME=""
SYS_RESULT=""

check_elements(){
	for e in "${@:2}"; do [[ $e == $1 ]] && return 0; done; return 1;
	unset e
}
check_file(){
	local tidy_loop conf
	
	for tidy_loop in ${SYS_PATH[@]}; do
		if [[ -d "${tidy_loop}" ]]; then
			for conf in "${tidy_loop}"/*.conf ; do
				check_elements ${conf##*/} ${SYS_NAME[@]}
				if (( $? )); then
					SYS_NAME+=("${conf##*/}")
				fi
			done
		fi
	done
	
	unset tidy_loop conf
}
check_path(){
	local path tidy_loop
	for path in ${SYS_PATH[@]}; do
		for tidy_loop in ${SYS_NAME[@]}; do
			if [[ -f "${path}/${tidy_loop}" ]]; then
				check_elements "${tidy_loop}" ${SYS_RESULT[@]##*/}
				if (( $? ));then
					SYS_RESULT+=("${path}/${tidy_loop}")
				fi
			fi
		done
	done
	unset path tidy_loop
}

# ${1} file to parse, can be a list e.g. nbd.conf quemu.conf
parse_file(){
	local sys line
	
	if [[ -z "${1}" ]];then
		check_file
		check_path
	else
		SYS_NAME="${@}"
		check_path
	fi

	#echo SYS_RESULT::${SYS_RESULT[@]}

	for sys in ${SYS_RESULT[@]}; do
		while read line; do
			case ${line:0:1} in
				u) line_u "${line}"
					;;
				g) line_g "${line}"
					;;				
				m) line_m "${line}"
					;;
				r) line_r "${line}"
					;;
				*) continue
					;;
			esac
		done < "${sys}"
	done
	
	unset sys line
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
	local line="${1}"
	
	check_args "${line}"
	
	optdirectory="-d${directory_:-/}"
	optcomment="-c${comment_}"
	
	optgid="-g"
	optuid="-u"
	if [[ -z "${uidgid}" ]]; then
		optgid=""
		optuid=""
	fi
		
	getent group ${named_} &>/dev/null
	if [[ $? -ne 0 ]]; then
		out_action "groupadd -r ${optgid} ${uidgid}" 
		groupadd -r ${optgid} ${uidgid} ${named_} || die " Impossible to create group ${named_}"
	fi
	
	getent passwd ${named_} &>/dev/null
	if [[ $? -ne 0 ]]; then
		if [[ -z "${comment_}" ]]; then
			if [[ -z "${optgid}" ]]; then
				optgid="-g ${named_}"
			fi
			out_action "useradd -r ${optuid} ${uidgid} ${optgid} ${uidgid} ${optdirectory} -s /sbin/nologin ${named_}"
			useradd -r ${optuid} ${uidgid} ${optgid} ${uidgid} ${optdirectory} -s /sbin/nologin ${named_} || die " Impossible to create user ${named_}"
		else
			if [[ -z "${optgid}" ]]; then
				optgid="-g ${named_}"
			fi
			out_action "useradd -r ${optuid} ${uidgid} ${optgid} ${uidgid} ${optdirectory} ${optcomment} -s /sbin/nologin ${named_}"
			useradd -r ${optuid} ${uidgid} ${optgid} ${uidgid} ${optdirectory} "${optcomment}" -s /sbin/nologin ${named_}	|| die " Impossible to create user ${named_}"
		fi
	fi
	
	unset line named_ directory_ optdirectory_ optdirectory_v uidgid optgid optgid_v optuid optuid_v comment_ optcomment optcomment_v
}
line_g(){
	local uidgid optgid optgid_v optuid optuid_v named_
	local line="${1}"
	
	check_args "${line}"
	
	optgid="-g"

	if [[ -z "${uidgid}" ]]; then
		optgid=""
	fi
	
	getent group ${named_} &>/dev/null
	if [[ $? -ne 0 ]]; then
		out_action "groupadd -r ${optgid} ${uidgid} ${named_}"
		groupadd -r ${optgid} ${uidgid} ${named_} || die " Impossible to create group ${named_}"
	fi
	
	unset line uidgid optgid optgid_v optuid optuid_v named_
}

line_m(){
	local named_g group_g uidgid optgid optgid_v optuid optuid_v directory_ optdirectory_ optdirectory_v comment_ optcomment optcomment_v
	local line="${1}"
	
	check_args "${line}"
	
	optdirectory="-d${directory_}"
	if [[ -z "${directory_}" ]]; then
		optdirectory=""
	fi
	
	optgid="-g"
	optuid="-u" 
	if [[ -z "${uidgid}" ]]; then
		optgid=""
		optuid=""
	fi
	
	optcomment="-c${comment_}"
		
	getent group ${group_g} &>/dev/null
	if [[ $? -ne 0 ]]; then
		out_action "groupadd -r ${optgid} ${uidgid} ${group_g}"
		groupadd -r ${optgid} ${uidgid} ${group_g} || die " Impossible to create group ${group_g}"
	fi
	
	getent passwd ${named_g} &>/dev/null
	if [[ $? -ne 0 ]]; then
		if [[ -z "${comment_}" ]]; then
			if [[ -z "${optgid}" ]]; then
				optgid="-g ${group_g}"
			fi
			out_action "useradd -r ${optuid} ${uidgid} ${optgid} ${uidgid} ${optdirectory} ${named_g}"
			useradd -r ${optuid} ${uidgid} ${optgid} ${uidgid} ${optdirectory} ${named_g} || die " Impossible to create user ${named_g}"
		else
			if [[ -z "${optgid}" ]]; then
				optgid="-g ${group_g}"
			fi
			out_action "useradd -r ${optuid} ${uidgid} ${optgid} ${uidgid}  ${optdirectory_v} ${optcomment} ${named_g}"
			useradd -r ${optuid} ${uidgid} ${optgid} ${uidgid}  ${optdirectory_v} "${optcomment}" ${named_g} || die " Impossible to create user ${named_g}"
		fi
	fi
	
	out_action "Add user ${named_g} to group ${group_g}"
	gpasswd -a ${named_g} ${group_g} || die " Impossible to add ${named_g} to group ${group_g}"
	
	unset line named_g group_g uidgid optgid optgid_v optuid optuid_v directory_ optdirectory_ optdirectory_v comment_ optcomment optcomment_v
}

line_r(){
	out_info "Pacopts cannot parse the file ${path_file}/${named} for r line,"
	out_info "you need to do it manually"
	break
}
