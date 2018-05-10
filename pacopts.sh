#!@BINDIR@/bash
# Copyright (c) 2015-2018 Eric Vidal <eric@obarun.org>
# All rights reserved.
# 
# This file is part of Obarun. It is subject to the license terms in
# the LICENSE file found in the top-level directory of this
# distribution and at https://github.com/Obarun/pacopts/LICENSE
# This file may not be copied, modified, propagated, or distributed
# except according to the terms contained in the LICENSE file.

shellopts_set_unset "extglob" 0

LIBRARY=${LIBRARY:-'/usr/lib/obarun'}

sourcing(){
	
	local list
	
	for list in ${LIBRARY}/pacopts/*; do
		source "${list}"
	done
	
	unset list
}
sourcing

COWER_CONFIG="$HOME/.config/cower/config"


## 		common functions

usage(){
	cat << EOF
	
${bold}Usage: ${0} <operation> [ target ] ${reset}

${bold}options:${reset}
    
    origin : check origin of target
    applysys : wrap up a sysusers file 
    applytmp : wrap up all tmpfiles
    aur : handle package from AUR repositories
    service : check if a service exist for target
    
${bold}target for:${reset}
    
    origin :
        Name of the repo to check.
        If target is empty, obarun repo is
        picked by default.
	
    applysys :
        Name of the file to parse.
        Can be a list e.g. nbd.conf qemu.conf
    
    applytmp :
        This option do not accept any target.
        
    aur :
        ${0} aur <operations> [ target ] [ arguments ]
        Operations can be : 
            -d download
            -i info
            -s search
            -m msearch
            -u update
            -U upgrade
            -I install
            -b build
        Target is the name of a package(s).
        Arguments is the option(s) for cower.
    
    service :
        Name of the package(s).
        If target is empty, all installed
        packages will be checked.
        Can be a list e.g. cups lvm2 dbus
EOF
	exit 0
}

##			ORIGIN FUNCTIONS

# ${1} name of the repos to use
# ${2} package name
find_origin(){
	
	local r repo_ver local_ver
	local -a p
	
	r="${1}"
	p="${@:2}"
	
	# syntax of -Ss output is 
	# repo/name version (group) [installed]
	# if the package doesn't come from the repo the syntax is
	# repo/name version (group) [installed: version]
	# if the package is not installed the syntax is
	# repo/name version (group)
	
	for i in ${p[@]};do
		printf "\r${bold}::${reset} Check ${bold}%s${reset} package" "${i}"
		tput el #return to the last line
		repo_ver=$(expac -S "%v %r" $i | grep ${r} |awk -F"${r}" '{ print $1 }'|sed 's/ //g')
		if (("${#repo_ver}"));then
			local_ver=$(expac -Q %v $i|sed 's/ //g')
			if (( "${#local_ver}" ));then
				if ! awk 'BEGIN{if (ARGV[1] != ARGV[2]) { exit 1 } }' "${repo_ver}" "${local_ver}";then
					false+=( "${i}" )
					false+=( "${repo_ver}" )
					false+=( "${local_ver}" )
				fi
			fi
		fi
	done
	printf "\n"
	
	unset p r repo_ver local_repo
}

# ${1} name of the repos to use
# ${@:2} name of the package
# if repo is empty, obarun is set by default
# if package is empty, all package are check
check_package(){
	
	local repo 
	local -a false pack 
		
	# pick obarun by default
	repo="${1:-obarun}"
	if [[ -z "${2}" ]];then
		pack=( $(pacman -Slq ${repo}) )
	else
		pack="${@:2}"
	fi
		
	find_origin "${repo}" "${pack[@]}"
	
	if (( "${#false[@]}" )); then
		out_notvalid "This following package(s) do not come from ${repo} repository"
		for ((i=0;i<"${#false[@]}";i+=3 ));do
			printf "\t%s\n" "${false[$i]}"
		done
		out_action "Do you want to replace this package(s)? [y|n]"
		reply_answer
		if (( ! $? )); then
			for ((i=0;i<"${#false[@]}";i+=3 ));do
				pacman -S "${repo}"/"${false[$i]}"
			done
		fi
	fi
	
	unset repo false pack
}

# ${1} list of service in fonction of the package name to find
# can be empty
service(){
	local -a list_s6serv list_s6rcserv list_service list_search list_result tidy_loop
	
	list_s6serv=$(pacman -Ssq s6serv)
	list_s6rcserv=$(pacman -Ssq s6rcserv)
	for tidy_loop in ${list_s6serv[@]} ${list_s6rcserv[@]};do
		printf "\r${bold}::${reset} Check dependencies for ${bold}%s${reset} service" "${tidy_loop}"
		tput el 1 #return to the last line
		list_service+=("${tidy_loop} $(expac -S "%D" ${tidy_loop})")
		unset tidy_loop
	done
	
	
	
	if [[ -z "${1}" ]]; then
		list_search=$(pacman -Qsq)
	else
		list_search=( "${@}" )
	fi
	
	for search in ${list_search[@]}; do
		for check in ${!list_service[@]};do
			while read subarray; do
				array_line=( ${subarray} )
				if [[ "${array_line[1]}" == "${search}" ]]; then
					pkg_installed=$(pacman -Qsq ${array_line[0]})
					if [[ -z "${pkg_installed}" ]]; then
						printf "\r"
						tput el 1
						printf "\r${bgreen}:: ${reset}${bold}${array_line}${reset} is a service for ${bold}$search${reset}"
						printf "\n"
						list_result+=("${array_line[0]}")
					fi
				fi
			done <<< ${list_service[$check]}
		done		
	done
	
	if (( "${#list_result}" )); then
		out_action "Do you want to install this service(s)? [y|n]"
		reply_answer
		if (( ! $? )); then
			for tidy_loop in "${list_result[@]}"; do
				pacman -S "${tidy_loop}"
			done
		fi
	fi
	
	unset list_s6serv list_s6rcserv list_service list_search list_result
}
look_target(){
	if [[ -z "${target}" ]]; then
		out_error "target must not be empty"
		out_error "try pacopts aur help command"
		exit 1
	fi
}
look_arguments(){
	if [[ -z "${arguments}" ]]; then
		out_error "arguments must not be empty"
		out_error "try pacopts aur help command"
		exit 1
	fi
}
# ${1} want root or not,
# 0 yes, 1 no
look_root(){
	local yes_no="${1}"
	
	if (( EUID == 0 ));then
		if (( "${yes_no}" ));then
			echo "This operation need to be run without root priviligies"
			exit 1
		fi
	else
		if ! (( "${yes_no}" ));then
			echo "This operation need to be run with root priviligies"
			exit 1
		fi
	fi
	
	unset yes_no
}

want_opt(){
	local want="${1}" give="${2}" line
	while read -n 1 line;do
		if check_elements "${line}" "${give}"; then
			return 0
		fi
	done <<< "${want}"
	
	unset want give line
	
	return 1
}

parse_opt(){
	local opt pos=0
	local -a str
	str=( "${@}" )
	str=( "${str[@]:1}" )
	
	opt="${1}"
	
	
	for ((i=0;i<${#str[@]};i++));do
		a_line=( ${str[i]} )
		
		for ((j=0;j<${#a_line[j]};j++));do
	
			pos=$j
			
			case ${a_line:j:1} in
				-) ((pos++))
					if [[ -z ${a_line:pos:1} ]]; then
						return 1
					elif [[ ${a_line:pos:1} == '-' ]]; then
						((pos++))
						
						if [[ -z ${a_line:pos:2} ]]; then
							return 1
						else
							rest_args[$i]="${a_line}"
						fi
						break
					elif want_opt "${opt}" ${a_line:pos:1};then
							opbind[$i]="${a_line:pos:1}"
							break						
					fi	
					;;
				*)	tget[$i]="${a_line}"
					break
					;;
			esac
		done
	done
	unset str pos opt optwrap
}
parse_aur(){
	local opbind 
	local -a tget rest_args

	look_root 1
	look_target

	if [[ ! -f "${COWER_CONFIG}" ]]; then
		mkdir -p "$HOME/.config/cower"
		if [[ -f "/usr/share/doc/cower/config" ]];then
			cp "/usr/share/doc/cower/config" "$HOME/.config/cower/"
			source "${COWER_CONFIG}"
		else
			touch "$HOME/.config/cower/config"
		fi
	else
		source "${COWER_CONFIG}"
	fi

	if ! parse_opt "dimscUuIbh" "${target_opts[@]}" || [[ -z "${opbind}" ]]; then
		aur_help
		exit 1
	fi
		
	if [[ "${opbind}" != @(h|u|U) ]]; then
		look_arguments
	fi

	case "${opbind}" in
		d)	
			aur_download 
			;;
		i)
			aur_info 
			;;
		m)
			aur_msearch 
			;;
		s)
			aur_search 
			;;
		U)
			aur_upgrade
			;;
		u)
			aur_update 
			;;
		I)
			aur_install 
			;;
		b)
			aur_build 
			;;
		h)	aur_help
			exit 0
			;;
		*)
			aur_help
			exit 1
			;;
	esac
	
	unset opbind tget rest_args
}
