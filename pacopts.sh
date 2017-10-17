#!@BINDIR@/bash
# Copyright (c) 2015-2017 Eric Vidal <eric@obarun.org>
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
SP="---" # character to use to know if the commandline on manage_aur_* is a list or not

## 		common functions

usage(){
	cat << EOF
	
${bold}Usage: ${0} <operation> [ target ]${reset}

${bold}options:${reset}
    
    origin : check origin of target
    applysys : wrap up a sysusers file 
    applytmp : wrap up all tmpfiles
    aur : manage package from AUR repositories
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
        This option do not accept any target.
    
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
find_origin(){
	local repo_origin check ori ori_line ori_name tidy_loop
	
	repo_origin="${1}"
	
	for check in ${!both[@]};do
		
		printf "\r${bold}::${reset} Check ${bold}%s${reset} package" "${both[$check]}"
		tput el #return to the last line
		
		while read ori; do
			
			ori_line=( ${ori} )
			# syntax of ori_line is 
			# repo/name version (group) [installed]
			# if the package doesn't come from the repo the syntax is
			# repo/name version (group) [installed: version]
			# if the package is not installed the syntax is
			# repo/name version (group)
			
			# ${#ori_line[@]} < 2 means field [installed] not present
			# so the package is not installed
			# skip it
			if [[ ${#ori_line[@]} > 2 ]]; then
				ori_name=${ori_line##*/}
				ori_name=${ori_name%%' '*}
				
				# only enter on the next loop if package = package searched
				# if not skip it.
				if [[ "${ori_name}" == "${both[check]}" ]]; then
					for ((tidy_loop=0;tidy_loop<${#ori_line[@]};tidy_loop++));do
						if [[ "${ori_line[$tidy_loop]}" =~ ":" ]] && [[ "${tidy_loop}" != "1" ]]; then
							if [[ "${both[$check]}" != obarun-@(mkiso|install|install-themes|build) ]]; then
								printf "\r${bred}::${reset} package ${bold}%s${reset} do not come from ${bold}${repo}${reset} repository" "${both[$check]}"
								printf "\n"
								false+=("${both[$check]}")
								# save cursor position
								tput sc
								break
							fi
						fi
					done
				fi
				unset ori_line ori_name tidy_loop
			fi
		done < <(pacman -Ss "${both[$check]}" | grep "${repo_origin}")
	done
	#return at the previous cursor position
	tput rc
	# erase the line
	tput ed
	
	unset repo_origin check ori ori_line ori_name tidy_loop
}

# ${1} name of the repos to use
# if empty, obarun is set by default
check_package(){
	
	local named item repo tidy_loop
	local -a both false repo_db
	
	# pick obarun by default
	repo="${1:-obarun}"
	
	mapfile -t repo_db < <(pacman -Slq "${repo}")
	
	# FILTER : Compare list of $installed package and $repo database,
	# if exist on twice put it on $both array
		
	while read named;do 
		for item in ${repo_db[@]}; do #$(pacman -Slq obarun)
			if  [[ "$named" == "$item" ]]; then 
				both+=("$item")
			fi
		done
	done < <(pacman -Qsq)
	
	#check origin of package
	find_origin "${repo}"
	
	if (( "${#false}" )); then 
		out_action "Do you want to replace this package(s)? [y|n]"
		reply_answer
		if (( ! $? )); then
			for tidy_loop in "${false[@]}"; do
				pacman -S "${repo}"/"${tidy_loop}"
			done
		fi
	fi
	
	unset named item repo both false repo_db tidy_loop
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
