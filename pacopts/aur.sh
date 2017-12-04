#!@BINDIR/bash
# Copyright (c) 2015-2017 Eric Vidal <eric@obarun.org>
# All rights reserved.
# 
# This file is part of Obarun. It is subject to the license terms in
# the LICENSE file found in the top-level directory of this
# distribution and at https://github.com/Obarun/pacopts/LICENSE
# This file may not be copied, modified, propagated, or distributed
# except according to the terms contained in the LICENSE file.

# function to find which installer to use for a given package
# return 10 for pacman, 11 for AUR helper
# ${1} name of package
choose_installer(){
	
	local b named
		
	named="${1}"
		
	for b in $(pacman -Ssq ${named[@]}); do
		if [[ $named =~ $b ]] ; then
			return 10			
		fi
	done
	unset b
	
	for b in $(cower -sq ${named[@]}); do
		if [[ $named =~ $b ]] ; then
			return 11			
		fi
	done
	unset b
	
	# be sure the named are not a group
	# if it's the case return value for pacman
	
	for b in $(pacman -Sgq ${named[@]}); do
		if [[ $named =~ $b ]] ; then
			return 10			
		fi
	done
		
	unset named b
}

# ${1} command to pass to cower
# ${2} cower arguments to pass
cower_cmd(){
	
	local opts
	
	cmd="${1}"
	opts=( "${2}" )
	
	cower "${cmd}" ${opts[@]} || unset opts && return 1
	
	unset opts
	
	return 0
}

# ${1} name of the package
install_scheme(){
	
	local named scheme_functions rc
	local -a installed_yet installed_version aur_version exist
	
	named="${1}"
	
	installed_yet=$(pacman -Qsq ${named})
	installed_version=$(expac -Q %v ${named}|sed "s:-:.:")
	aur_version=$(cower -i ${named} --format=%v|sed "s:-:.:")
	exist=( $(cower_cmd "-sq" ${named}) )
	
	if ! check_elements "${named}" ${exist[@]}; then
		printf "%s\n" ":: ${bold}${named}${reset} doesn't exist"
		return 1
	fi
	
	# already installed or not
	if (( "${#installed_yet}" )); then
		if check_elements "${named}" ${installed_yet[@]}; then
			# check the version, if differ then install it
			if ! check_elements ${installed_version} ${aur_version}; then
				# check the upper version
				awk -v n1=${aur_version} -v n2=${installed_version} 'BEGIN { exit (n1>n2) ? 1 : 0 }'
				rc=$?
				if (( !"${rc}" )); then
					printf "\n"
					printf "%s\n" ":: ${bold}${named}${reset} already up to date"
					printf "%s\n" ":: installed -> ${bold}${installed_version}${reset}, aur -> ${bold}${aur_version}${reset}"
					printf "\n"
				fi
			else
				rc=0
				printf "\n"
				printf "%s\n" ":: ${bold}${named}${reset} already up to date"
				printf "%s\n" ":: installed -> ${bold}${installed_version}${reset}, aur -> ${bold}${aur_version}${reset}"
				printf "\n"
			fi
		else
			rc=1	
		fi
	else
		rc=1
	fi
			
	if (( "${rc}" )); then
		
		unset rc
	
		for scheme_functions in scheme_{get_pkgbuild,dependencies,build,install}; do
			"${scheme_functions}" "${named}"
		done
	fi
	
	unset named scheme_functions installed_yet installed_version aur_version exist rc
}

# ${1} name of the package
scheme_get_pkgbuild(){
	
	local named real_name
		
	named="${1}"
	
	printf "\n"
	printf "%s\n" ":: Get ${bold}${named}${reset} PKGBUILD"
	printf "\n"
	
	real_name=$(cower -i ${named} --format=%b)
	
	search_in_dir "${work_dir}" "${real_name}" "PKGBUILD" &>/dev/null
	if (( ! $? )); then
		printf "%s" ":: ${named} exist, overwrite it?[y|n] > "
		reply_answer
		if (( ! $? )); then
			cower_cmd "-df" "${named} ${rest_args[@]} ${OPTS_COWER[@]}" 
		else
			return 1
		fi
	else	
		cower_cmd "-d" "${named} ${rest_args[@]} ${OPTS_COWER[@]}" 
	fi
	
	unset named real_name
	
	return 0
}

# ${1} name of the package
scheme_dependencies(){
	
	local named tidy_loop
	local -a dps dps_parsed
	
	named="${1}"
	dps=$(cower -i $named --format=%D) # Depends
	dps+=($(cower -i $named --format=%M)) # Makedepends
	
	printf "\n"
	printf "%s\n" ":: Check dependencies for ${bold}${named}${reset}"
	printf "\n"
	
	# parse each element of the array to remove any <>= characters
	for tidy_loop in ${dps[@]}; do
		#echo tidy_loop :: $tidy_loop
		tidy_loop=${tidy_loop%%@(>|<|=)*}
		#echo tidy_loop parsed :: $tidy_loop
		dps_parsed+=("$tidy_loop")
	done
	unset tidy_loop
	
	# loop through dependencies recursively
	for tidy_loop in ${dps_parsed[@]}; do
		
		choose_installer "${tidy_loop}"
		
		rc=$?
		
		if [[ "$rc" == 11 ]];then
			scheme_dependencies "${tidy_loop}"
			install_scheme "${tidy_loop}"
		fi
	done
	
	unset named dps dps_parsed tidy_loop
	
	return 0
}

# ${1} name of the package
# ${2} working directory
scheme_build(){
	
	local named real_name
	named="${1}"
	
	printf "\n"
	printf "%s\n" ":: Build ${bold}${named}${reset}"
	printf "\n"
	
	real_name=$(cower -i ${named} --format=%b)
	
	pushd "${real_name}" &>/dev/null
	
	search_in_dir "${work_dir}" "${real_name}" "${real_name}"*.pkg.tar.xz &>/dev/null
	
	if (( ! "$?" )); then
		printf "%s" ":: ${named} compiled package exist, overwrite it?[y|n] > "
		reply_answer
		if (( ! "$?" )); then
				makepkg -f ${OPTS_MAKEPKG[@]} || return 1
		else
			return 1
		fi
	else
		makepkg ${OPTS_MAKEPKG[@]} || return 1
	fi
	
	popd &>/dev/null
	
	unset named real_name
	
	return 0
}

scheme_install(){
	
	local named real_name
	
	named="${1}"
	
	printf "\n"
	printf "%s\n" ":: Install ${bold}${named}${reset}"
	printf "\n"
	
	real_name=$(cower -i ${named} --format=%b)
	cache=($(pacman --verbose 2>/dev/null|awk -F"Cache Dirs: " '{print $2}'))
	
	pushd "${real_name}" &>/dev/null
	
	su -c "pacman ${OPTS_PACMAN[@]} ${real_name}-*.pkg.tar.xz; cp -f ${real_name}-*.pkg.tar.xz ${cache}" || return 1
	
	popd &>/dev/null
	
	unset named real_name
	
	return 0
}

aur_download(){
	
	local tidy_loop
		
	if check_elements "help" ${tget[@]} ||  [[ -z "${tget[@]}" ]];then
		aur_download_help
		exit 0
	fi

	for tidy_loop in ${tget[@]}; do
		printf "%s\n" "download :: ${bold}${tidy_loop}${reset}"
		printf "\n"
		cower_cmd "-d" "${tidy_loop} ${rest_args[@]} ${OPTS_COWER[@]}"
		printf "\n"
	done
			
	unset tidy_loop
}

aur_info(){
	
	local tidy_loop
		
	if check_elements "help" ${tget[@]} ||  [[ -z "${tget[@]}" ]];then
		aur_info_help
		exit 0
	fi
			
	for tidy_loop in ${tget[@]}; do
		printf "%s\n" "info :: ${bold}${tidy_loop}${reset}"
		printf "\n"
		cower_cmd "-i" "${tidy_loop} ${rest_args[@]} ${OPTS_COWER[@]}"
		printf "\n"
	done
	
	unset tidy_loop
}

aur_msearch(){
	
	local tidy_loop
	
	if check_elements "help" ${tget[@]} ||  [[ -z "${tget[@]}" ]];then
		aur_msearch_help
		exit 0
	fi
	
	for tidy_loop in ${tget[@]}; do
		printf "%s\n" "msearch :: ${bold}${tidy_loop}${reset}"
		printf "\n"
		cower_cmd "-m" "${tidy_loop} ${rest_args[@]} ${OPTS_COWER[@]}"
		printf "\n"
	done
	
	unset tidy_loop
}

aur_search(){
	
	local tidy_loop
		
	if check_elements "help" ${tget[@]} ||  [[ -z "${tget[@]}" ]];then
		aur_search_help
		exit 0
	fi

	for tidy_loop in ${tget[@]}; do
		printf "%s\n" "search :: ${bold}${tidy_loop}${reset}"
		printf "\n"
		cower_cmd "-s" "${tidy_loop} ${rest_args[@]} ${OPTS_COWER[@]}"
		printf "\n"
	done
		
	unset tidy_loop
}

aur_update(){
	
	local tidy_loop work_dir
	local -a update_list
	
	work_dir="${TargetDir:-/tmp}"
	
	check_dir "${work_dir}"
	if (( "$?" )); then
		mkdir -p "${work_dir}" || die " Impossible to create the working directory"
	fi
	if check_elements "help" ${tget[@]};then
		aur_update_help
		exit 0
	elif [[ -z "${tget[@]}" ]];then
		printf "%s\n" "check :: ${bold}All package${reset}"
		cower_cmd "-u" "${rest_args[@]} ${OPTS_COWER[@]}"
		printf "\n"
	else
		for tidy_loop in ${tget[@]}; do
			printf "%s\n" "check :: ${bold}${tidy_loop}${reset}"
			cower_cmd "-u" "${tidy_loop} ${rest_args[@]} ${OPTS_COWER[@]}"
			printf "\n"
		done
	fi
	
	unset tidy_loop update_list pack work_dir
}
aur_upgrade(){
	
	local tidy_loop work_dir
	local -a update_list

	work_dir="${TargetDir:-/tmp}"
	
	check_dir "${work_dir}"
	if (( "$?" )); then
		mkdir -p "${work_dir}" || die " Impossible to create the working directory"
	fi
	
	if check_elements "help" ${tget[@]};then
		aur_upgrade_help
		exit 0
	elif [[ -z "${tget[@]}" ]];then
		update_list=$(cower_cmd "-uq")
		if (( ${#update_list} )); then
			pushd "${work_dir}" &>/dev/null
			for tidy_loop in ${update_list[@]}; do
				printf "%s\n" "update :: ${bold}${pack}${reset}"
				install_scheme "${tidy_loop}"
				printf "\n"
			done
			popd &>/dev/null
		else
			printf "%s\n" ":: ${bold}nothing to do${reset}"
		fi
	else
		pushd "${work_dir}" &>/dev/null
		for tidy_loop in ${tget[@]}; do
			printf "%s\n" "update :: ${bold}${tidy_loop}${reset}"
			install_scheme "${tidy_loop}"
			printf "\n"
		done	
	fi		
	
	unset tidy_loop pack work_dir update_list
}
aur_install(){
	
	local tidy_loop work_dir
	
	work_dir="${TargetDir:-/tmp}"
	
	check_dir "${work_dir}"
	if (( "$?" )); then
		mkdir -p "${work_dir}" || die " Impossible to create the working directory"
	fi
	
	if check_elements "help" ${tget[@]} ||  [[ -z "${tget[@]}" ]];then
		aur_install_help
		exit 0
	fi
	
	pushd "${work_dir}" &>/dev/null
		
	for tidy_loop in ${tget[@]}; do
		printf "%s\n" "install :: ${bold}${tidy_loop}${reset}"
		printf "\n"
		install_scheme "${tidy_loop}"
		printf "\n"
	done
	
	popd &>/dev/null
	
	unset tidy_loop work_dir
}

aur_build(){
	
	local work_dir scheme
		
	work_dir="${TargetDir:-/tmp}"
	
	check_dir "${work_dir}"
	if (( "$?" )); then
		mkdir -p "${work_dir}" || die " Impossible to create the working directory"
	fi
	
	if check_elements "help" ${tget[@]} ||  [[ -z "${tget[@]}" ]];then
		aur_build_help
		exit 0
	fi
	
	pushd "${work_dir}" &>/dev/null

	for tidy_loop in ${tget[@]}; do
		printf "%s\n" ":: ${bold}${tidy_loop}${reset}"
		printf "\n"
		for scheme in scheme_{get_pkgbuild,build};do 
			"${scheme}" "${tidy_loop}"
			if (( $? )); then
				break
			fi
		done
		printf "\n"
	done
	
	popd &>/dev/null
	
	unset tidy_loop work_dir scheme
}


aur_help(){
	printf "\n"
	printf "%-15s\n" "The following command are available" >&1
	printf "\n"
	printf "%-15s %-15s\n" "     download" "download a pkgbuild for a given package" >&1
	printf "%-15s %-15s\n" "     info" "get info for a given package" >&1
	printf "%-15s %-15s\n" "     msearch" "search for packages maintained by a given name" >&1
	printf "%-15s %-15s\n" "     search" "search for packages with a given name or regex pattern" >&1
	printf "%-15s %-15s\n" "     update" "check if a given packages is out of date" >&1
	printf "%-15s %-15s\n" "     upgrade" "upgrade a given packages" >&1
	printf "%-15s %-15s\n" "     build" "build package(s)" >&1
	printf "%-15s %-15s\n" "     install" "download,build,install package(s) in one pass" >&1
	printf "\n"
	printf "%-15s\n" "The first letter can be used e.g. d for download." >&1
	printf "%-15s\n" "A special case exist for install, enter in." >&1
}

aur_install_help(){
	cat << EOF
${bold}Install a named package or a list of package.${reset}

  The script download the PKGBUILD, build the package then install the package.
  
  If a dependency coming from AUR is detected, 
  the script run again the same scheme (download, build, install) for the dependency.
  This system is done recursively even for a list of packages.
EOF
}

aur_build_help(){
	cat << EOF
${bold}Build a named package or a list of packages.${reset}

  The script download the PKGBUILD then build the package.
  The AUR dependencies is not resolved.
EOF
}
aur_download_help(){
	cat << EOF
${bold}Download the PKGBUILD for a named package or a list of packages.${reset}
  
  The script accept any extra command coming from cower. However, to avoid
  conflicts between pacopts options and cower options, the long options
  MUST be used for cower. Short options for cower will not have any effects.
  e.g :
     
     retrovol --force
     retrovol clipit --force
          
  See man cower for futher informations.
EOF
}

aur_info_help(){
	cat << EOF
${bold}Get information for a named package or a list of packages.${reset}
  
  The script accept any extra command coming from cower. However, to avoid
  conflicts between pacopts options and cower options, the long options
  MUST be used for cower. Short options for cower will not have any effects.
  e.g :
     
     retrovol --format=%D
     retrovol clipit --format=%D
     
  See man cower for more informations.
EOF
}

aur_search_help(){
	cat << EOF
${bold}Search in AUR for a named package or a list of packages.${reset}
  
  The script accept any extra command coming from cower. However, to avoid
  conflicts between pacopts options and cower options, the long options
  MUST be used for cower. Short options for cower will not have any effects.
  e.g :
     
     retrovol --by=name
     retrovol clipit --by=name
     
  See man cower for more informations.
EOF
}

aur_msearch_help(){
	cat << EOF
${bold}Search for packages or a list of packages maintained by a named maintainer.${reset}
  
  The script look forward a triple dash to define the list e.g :
     
     retrovol clipit ---
  
  The script accept any extra command coming from cower. However, to avoid
  conflicts between pacopts options and cower options, the long options
  MUST be used for cower. Short options for cower will not have any effects.
  e.g :
     
     retrovol --format=%a
     retrovol clipit --format=%a
     
  See man cower for more informations.
EOF
}

aur_update_help(){
	cat << EOF
${bold}Check if a named package or a list of packages is/are out of date.
If you leave the name blank, the script check for all installed package
on your system.${reset}
  
  The script accept any extra command coming from cower. However, to avoid
  conflicts between pacopts options and cower options, the long options
  MUST be used for cower. Short options for cower will not have any effects.
  e.g :
     
     retrovol --threads=8
     retrovol clipit --threads=8
     
  See man cower for more informations.
EOF
}
aur_upgrade_help(){
	cat << EOF
${bold}Download,build and install a named package or a list of packages if
the package(s) is out of date.
If you leave the name blank, the script do the same for all installed package
on your system.${reset}
  
  The script accept any extra command coming from cower. However, to avoid
  conflicts between pacopts options and cower options, the long options
  MUST be used for cower. Short options for cower will not have any effects.
  e.g :
     
     retrovol --threads=8
     retrovol clipit --threads=8
     
  See man cower for more informations.
EOF
}
