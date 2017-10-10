#!@BINDIR@/bash
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

# ${1} array to parse
manage_aur_is_array(){
	
	local -a _array
	_array=( ${1} )

	if check_elements "${SP}" ${_array[@]}; then
		parse_ans=${ans[@]}
		named=${ans[@]}
		named=${named%%---*}
		ans_args=${parse_ans##*---}
		return 0
	else
		parse_ans=${ans[@]}
		named=${parse_ans%%' '*}
		ans_args=${parse_ans##*${named}}
		if [[ "${named}" == "${ans_args}" ]]; then
			unset ans_args
		fi
		return 1
	fi
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
	
	local named scheme_functions
	local -a installed_yet installed_version aur_version exist
	
	named="${1}"
	
	installed_yet=$(pacman -Qsq ${named})
	installed_version=$(expac -Q %v ${named}|sed "s:-:.:")
	aur_version=$(cower -i ${named} --format=%v|sed "s:-:.:")
	exist=( $(cower_cmd "-sq" ${named}) )
	
	if ! check_elements "${named}" ${exist[@]}; then
		printf "%s\n" "${info} :: ${bold}${named}${reset} doesn't exist"
		return 1
	fi
	
	# already installed or not
	if (( "${#installed_yet}" )); then
		if check_elements "${named}" ${installed_yet[@]}; then
			# check the version, if differ then install it
			if ! check_elements ${installed_version} ${aur_version}; then
				# check the upper version
				awk -v n1=${aur_version} -v n2=${installed_version} 'BEGIN {if (n1>n2) exit 1; exit 0}'
				if (( $? )); then
					rc=1
				else
					rc=0
					printf "\n"
					printf "%s\n" "${info} :: ${bold}${named}${reset} already up to date"
					printf "\n"
				fi
			else
				rc=0
				printf "\n"
				printf "%s\n" "${info} :: ${bold}${named}${reset} already up to date"
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
	
	unset named scheme_functions installed_yet installed_version aur_version exist
}

# ${1} name of the package
scheme_get_pkgbuild(){
	
	local named real_name
		
	named="${1}"
	
	printf "\n"
	printf "%s\n" "${info} :: Get ${bold}${named}${reset} PKGBUILD"
	printf "\n"
	
	real_name=$(cower -i ${named} --format=%b)
	
	search_in_dir "${work_dir}" "${real_name}" "PKGBUILD" &>/dev/null
	if (( ! $? )); then
		printf "%s" "Manage ${bold}${info}${reset} :: ${named} exist, overwrite it?[y|n] > "
		reply_answer
		if (( ! $? )); then
			cower_cmd "-df" "${named} ${ans_args[@]} ${OPTS_COWER[@]}" 
		else
			return 1
		fi
	else	
		cower_cmd "-d" "${named} ${ans_args[@]} ${OPTS_COWER[@]}" 
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
	printf "%s\n" "${info} :: Check dependencies for ${bold}${named}${reset}"
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
	printf "%s\n" "${info} :: Build ${bold}${named}${reset}"
	printf "\n"
	
	real_name=$(cower -i ${named} --format=%b)
	
	pushd "${real_name}" &>/dev/null
	
	search_in_dir "${work_dir}" "${real_name}" "${real_name}"*.pkg.tar.xz &>/dev/null
	
	if (( ! "$?" )); then
		printf "%s" "Manage ${bold}${info}${reset} :: ${named} compiled package exist, overwrite it?[y|n] > "
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
	printf "%s\n" "${info} :: Install ${bold}${named}${reset}"
	printf "\n"
	
	real_name=$(cower -i ${named} --format=%b)
	cache=($(pacman --verbose 2>/dev/null|awk -F"Cache Dirs: " '{print $2}'))
	
	pushd "${real_name}" &>/dev/null
	
	su -c "pacman ${OPTS_PACMAN[@]} ${real_name}-*.pkg.tar.xz; cp -f ${real_name}-*.pkg.tar.xz ${cache}" || return 1
	
	popd &>/dev/null
	
	unset named real_name
	
	return 0
}

manage_aur_download(){
	
	local info named rc tidy_loop
	local -a parse_ans ans_args ans
	
	info="${1}"
		
	while true; do
		
		unset named
		
		printf "\n"
		read -ep "Manage ${bold}${info}${reset} :: enter a name > " ans
		printf "\n"
		
		named="${ans}"
		
		case "${ans}" in
			"")
				printf "%s\n" "${info} :: enter a name please"
				;;
			@(info|msearch|search|update|install|build)) 
				rc=1
				break
				;;
			help)
				manage_aur_download_help
				;;
			quit) 
				exit
				;;
			*) 	manage_aur_is_array "${ans[@]}"
				
				if (( ! "$?" )); then
					for tidy_loop in ${named[@]}; do
						printf "%s\n" "${info} :: ${bold}${tidy_loop}${reset}"
						printf "\n"
						cower_cmd "-d" "${tidy_loop} ${ans_args[@]} ${OPTS_COWER[@]}"
						printf "\n"
					done
				else
					cower_cmd "-d" "${named[@]} ${ans_args[@]} ${OPTS_COWER[@]}"
				fi
				;;
		esac
	done
	if (( $rc )); then
		manage_aur 0 "${ans}"
	fi
	
	unset info named rc parse_ans ans_args ans tidy_loop
}

manage_aur_info(){
	
	local info named rc tidy_loop
	local -a parse_ans ans_args ans
	
	info="${1}"
	
	while true; do
		
		unset named
		
		printf "\n"
		read -ep "Manage ${bold}${info}${reset} :: enter a name > " ans
		printf "\n"
			
		named="${ans}"
			
		case "${ans}" in
			"")
				printf "%s\n" "${info} :: enter a name please"
				;;
			@(download|msearch|search|update|install|build)) 
				rc=1
				break
				;;
			help)
				manage_aur_info_help
				;;
			quit) 
				exit
				;;
			*) 	manage_aur_is_array "${ans[@]}"
				
				if (( ! "$?" )); then
					for tidy_loop in ${named[@]}; do
						printf "%s\n" "${info} :: ${bold}${tidy_loop}${reset}"
						cower_cmd "-i" "${tidy_loop} ${ans_args[@]} ${OPTS_COWER[@]}"
						printf "\n"
					done
				else
					cower_cmd "-i" "${named[@]} ${ans_args[@]} ${OPTS_COWER[@]}"
				fi
				;;
		esac
	done
	if (( $rc )); then
		manage_aur 0 "${ans}"
	fi
	
	unset info named rc parse_ans ans_args ans tidy_loop
}

manage_aur_msearch(){
	
	local info named rc tidy_loop
	local -a parse_ans ans_args ans
	
	info="${1}"
	
	while true; do
		
		unset named
		
		printf "\n"
		read -ep "Manage ${bold}${info}${reset} :: enter a name > " ans
		printf "\n"
		
		named="${ans}"
		
		case "${ans}" in
			"")
				printf "%s\n" "${info} :: enter a name please"
				;;
			@(download|info|search|update|install|build)) 
				rc=1
				break
				;;
			help)
				manage_aur_msearch_help
				;;
			quit) 
				exit
				;;
			*) 	manage_aur_is_array "${ans[@]}"
				
				if (( ! "$?" )); then
					for tidy_loop in ${named[@]}; do
						printf "%s\n" "${info} :: ${bold}${tidy_loop}${reset}"
						printf "\n"
						cower_cmd "-m" "${tidy_loop} ${ans_args[@]} ${OPTS_COWER[@]}"
						printf "\n"
					done
				else
					cower_cmd "-m" "${named[@]} ${ans_args[@]} ${OPTS_COWER[@]}"
				fi
				;;
		esac
	done
	if (( $rc )); then
		manage_aur 0 "${ans}"
	fi
	
	unset info named rc parse_ans ans_args ans tidy_loop
}

manage_aur_search(){
	
	local info named rc tidy_loop
	local -a parse_ans ans_args ans
	
	info="${1}"
	
	while true; do
		
		unset named
		
		printf "\n"
		read -ep "Manage ${bold}${info}${reset} :: enter a name > " ans
		printf "\n"
		
		named="${ans}"
		
		case "${ans}" in
			"")
				printf "%s\n" "${info} :: enter a name please"
				;;
			@(download|info|msearch|update|install|build)) 
				rc=1
				break
				;;
			help)
				manage_aur_search_help
				;;
			quit) 
				exit
				;;
			*) 	manage_aur_is_array "${ans[@]}"
				
				if (( ! "$?" )); then
					for tidy_loop in ${named[@]}; do
						printf "%s\n" "${info} :: ${bold}${tidy_loop}${reset}"
						printf "\n"
						cower_cmd "-s" "${tidy_loop} ${ans_args[@]} ${OPTS_COWER[@]}"
						printf "\n"
					done
				else
					cower_cmd "-s" "${named[@]} ${ans_args[@]} ${OPTS_COWER[@]}"
				fi
				;;
		esac
	done
	if (( $rc )); then
		manage_aur 0 "${ans}"
	fi
	
	unset info named rc parse_ans ans_args ans tidy_loop
}

manage_aur_update(){
	
	local info named rc tidy_loop pack
	local -a parse_ans ans_args ans update_list
	
	info="${1}"
	work_dir="${TargetDir:-/tmp}"
	
	check_dir "${work_dir}"
	if (( "$?" )); then
		mkdir -p "${work_dir}" || die " Impossible to create the working directory"
	fi
	
	while true; do
	
		unset named

		printf "\n"
		read -ep "Manage ${bold}${info}${reset} :: enter a name > " ans
		printf "\n"
		
		named="${ans}"
		
		case "${ans}" in
			@(download|info|msearch|search|install|build)) 
				rc=1
				break
				;;
			all)
				update_list=$(cower_cmd "-uq")
				if (( ${#update_list} )); then
					pushd "${work_dir}" &>/dev/null
					for pack in ${update_list[@]}; do
						printf "%s\n" "${info} :: ${bold}${pack}${reset}"
						install_scheme "${pack}"
						printf "\n"
					done
					popd &>/dev/null
				else
					printf "%s\n" "${info} :: ${bold}nothing to do${reset}"
				fi
				;;
			help)
				manage_aur_update_help
				;;
			quit) 
				exit
				;;
			*) 	if (( ! ${#ans} )); then ## no name, so check all packages
					cower_cmd "-u" "${OPTS_COWER[@]}"
					continue
				fi
				manage_aur_is_array "${ans[@]}"
				
				if (( ! "$?" )); then
					for tidy_loop in ${named[@]}; do
						printf "%s\n" "${info} :: ${bold}${tidy_loop}${reset}"
						cower_cmd "-u" "${tidy_loop} ${ans_args[@]} ${OPTS_COWER[@]}"
						printf "\n"
					done
				else
					cower_cmd "-u" "${named[@]} ${ans_args[@]} ${OPTS_COWER[@]}"
				fi
				;;
		esac
	done
	if (( $rc )); then
		manage_aur 0 "${ans}"
	fi
	
	unset info named rc parse_ans ans_args ans tidy_loop update_list pack
}

manage_aur_install(){
	
	local info named rc work_dir
	local -a parse_ans ans_args ans
	
	info="${1}"
	work_dir="${TargetDir:-/tmp}"
	
	check_dir "${work_dir}"
	if (( "$?" )); then
		mkdir -p "${work_dir}" || die " Impossible to create the working directory"
	fi
	
	while true; do
		
		pushd "${work_dir}" &>/dev/null
		
		unset named
		
		printf "\n"
		read -ep "Manage ${bold}${info}${reset} :: enter a name > " ans
		printf "\n"
			
		named="${ans}"
		
		case "${ans}" in
			"")
				printf "%s\n" "${info} :: enter a name please"
				;;
			@(download|info|msearch|search|update|build)) 
				rc=1
				break
				;;
			help)
				manage_aur_install_help
				;;
			quit) 
				exit
				;;
			*) manage_aur_is_array "${ans[@]}"
				
				if (( ! "$?" )); then
					for tidy_loop in ${named[@]}; do
						printf "%s\n" "${info} :: ${bold}${tidy_loop}${reset}"
						printf "\n"
						install_scheme "${tidy_loop}"
						printf "\n"
					done
				else
					install_scheme "${named}"
				fi
				;;
		esac
	done
	if (( $rc )); then
		manage_aur 0 "${ans}"
	fi
	
	unset info named rc parse_ans ans_args ans tidy_loop work_dir
}

manage_aur_build(){
	
	local info named rc work_dir scheme
	local -a parse_ans ans_args ans
	
	info="${1}"
	work_dir="${TargetDir:-/tmp}"
	
	check_dir "${work_dir}"
	if (( "$?" )); then
		mkdir -p "${work_dir}" || die " Impossible to create the working directory"
	fi
	
	while true; do
		
		pushd "${work_dir}" &>/dev/null
		
		unset named
		
		printf "\n"
		read -ep "Manage ${bold}${info}${reset} :: enter a name > " ans
		printf "\n"
		
		named="${ans}"
		
		case "${ans}" in
			"")
				printf "%s\n" "${info} :: enter a name please"
				;;
			@(download|info|msearch|search|update|install)) 
				rc=1
				break
				;;
			help)
				manage_aur_build_help
				;;
			quit) 
				exit
				;;
			*) manage_aur_is_array "${ans[@]}"
				
				
				if (( ! "$?" )); then
					for tidy_loop in ${named[@]}; do
						printf "%s\n" "${info} :: ${bold}${tidy_loop}${reset}"
						printf "\n"
						for scheme in scheme_{get_pkgbuild,build};do 
							"${scheme}" "${tidy_loop}"
							if (( $? )); then
								break
							fi
						done
						printf "\n"
					done
				else
					for scheme in scheme_{get_pkgbuild,build};do 
						"${scheme}" "${named}"
						if (( $? )); then
							break
						fi
					done
				fi
				;;
		esac
	done
	
	if (( $rc )); then
		manage_aur 0 "${ans}"
	fi
	
	popd &>/dev/null
	
	unset info named rc parse_ans ans_args ans tidy_loop work_dir scheme
}

# ${1} first pass or not : 0 for not, 1 for yes
# ${2} cower command or extra command e.g. install

manage_aur(){
	
	if [[ ! -f "${COWER_CONFIG}" ]]; then
		out_info "A configuration file for cower need to be present at $HOME/.config/cower/"
		out_info "Please make a copy of /usr/share/doc/cower/config file at ${COWER_CONFIG}"
		die " Impossible to find the file ${COWER_CONFIG}"
	else
		source "${COWER_CONFIG}"
	fi
	
	local cower_cmd _pass
	_pass="${1}"
	manage_cmd="${2}"
	
	if (( "${_pass}" )); then
		printf "\n"
		
		read -ep "Manage :: please enter your command > " ans
		manage_cmd="${ans}"
	fi
	
	case $manage_cmd in
			@(d|download))
				manage_aur_download "download"
				;;
			@(i|info))
				manage_aur_info "info"
				;;
			@(m|msearch))
				manage_aur_msearch "msearch"
				;;
			@(s|search))
				manage_aur_search "search"
				;;
			@(u|update))
				manage_aur_update "update"
				;;
			@(in|install))
				manage_aur_install "install"
				;;
			@(b|build))
				manage_aur_build "build"
				;;
			quit)
				exit
				;;
			*)
				manage_aur_help
				manage_aur 1
				;;
	esac
}

manage_aur_help(){
	printf "\n"
	printf "%-15s\n" "The following command are available" >&1
	printf "\n"
	printf "%-15s %-15s\n" "     download" "download a pkgbuild for a given package" >&1
	printf "%-15s %-15s\n" "     info" "get info for a given package" >&1
	printf "%-15s %-15s\n" "     msearch" "search for packages maintained by a given name" >&1
	printf "%-15s %-15s\n" "     search" "search for packages with a given name or regex pattern" >&1
	printf "%-15s %-15s\n" "     update" "check for updates for a given packages" >&1
	printf "%-15s %-15s\n" "     build" "build package(s)" >&1
	printf "%-15s %-15s\n" "     install" "download,build,install package(s) in one pass" >&1
	printf "%-15s %-15s\n" "     quit" "exit from the script" >&1
	printf "\n"
	printf "%-15s\n" "The first letter can be used e.g. d for download." >&1
	printf "%-15s\n" "A special case exist for install, enter in." >&1
}

manage_aur_install_help(){
	cat << EOF
${bold}Install a named package or a list of package.${reset}

  The script look forward a triple dash to define the list e.g :
     
     retrovol clipit ---
  
  Without this regex only the first name is took.
  A whitespace need to be present before and after the triple dash.
  
  The script download the PKGBUILD, build the package then install the package.
  
  If a dependency coming from AUR is detected, 
  the script run again the same scheme (download, build, install) for the dependency.
  This system is done recursively even for a list of package.
  
  You can switch to the main command entering his name e.g :
     download #switch to the download command
     build #switch to the build command
     quit #to exit from the script
EOF
}

manage_aur_build_help(){
	cat << EOF
${bold}Build a named package or a list of package.${reset}

  The script look forward a triple dash to define the list e.g :
     
     retrovol clipit ---
  
  Without this regex only the first name is took.
  A whitespace need to be present before and after the triple dash.
  
  The script download the PKGBUILD then build the package.
  The AUR dependencies is not resolved.
  
  You can switch to the main command entering his name e.g :
     download #switch to the download command
     build #switch to the build command
     quit #to exit from the script
EOF
}
manage_aur_download_help(){
	cat << EOF
${bold}Download the PKGBUILD for a named package or a list of package.${reset}
  
  The script look forward a triple dash to define the list e.g :
     
     retrovol clipit ---
  
  Without this regex only the first name is took.
  A whitespace need to be present before and after the triple dash.

  The script accept any extra command coming from cower e.g :
     
     retrovol -f
     retrovol clipit --- -f
     
  See man cower for more informations.
  
  You can switch to the main command entering his name e.g :
     download #switch to the download command
     build #switch to the build command
     quit #to exit from the script
EOF
}

manage_aur_info_help(){
	cat << EOF
${bold}Get information for a named package or a list of package.${reset}
  
  The script look forward a triple dash to define the list e.g :
     
     retrovol clipit ---
  
  Without this regex only the first name is took.
  A whitespace need to be present before and after the triple dash.

  The script accept any extra command coming from cower e.g :
     
     retrovol --format=%D
     retrovol clipit --- --format=%D
     
  See man cower for more informations.
  
  You can switch to the main command entering his name e.g :
     download #switch to the download command
     build #switch to the build command
     quit #to exit from the script
EOF
}

manage_aur_search_help(){
	cat << EOF
${bold}Search in AUR for a named package or a list of package.${reset}
  
  The script look forward a triple dash to define the list e.g :
     
     retrovol clipit ---
  
  Without this regex only the first name is took.
  A whitespace need to be present before and after the triple dash.

  The script accept any extra command coming from cower e.g :
     
     retrovol --by=name
     retrovol clipit --- --by=name
     
  See man cower for more informations.
  
  You can switch to the main command entering his name e.g :
     download #switch to the download command
     build #switch to the build command
     quit #to exit from the script
EOF
}

manage_aur_msearch_help(){
	cat << EOF
${bold}Search for packages or a list of package maintained by a named maintainer.${reset}
  
  The script look forward a triple dash to define the list e.g :
     
     retrovol clipit ---
  
  Without this regex only the first name is took.
  A whitespace need to be present before and after the triple dash.

  The script accept any extra command coming from cower e.g :
     
     retrovol --format=%a
     retrovol clipit --- --format=%a
     
  See man cower for more informations.
  
  You can switch to the main command entering his name e.g :
     download #switch to the download command
     build #switch to the build command
     quit #to exit from the script
EOF
}

manage_aur_update_help(){
	cat << EOF
${bold}Check for update in AUR for a named package or a list of package.
If you enter all as arguments, all installed packages will be updated on 
your system.${reset}
  
  The script look forward a triple dash to define the list e.g :
     
     retrovol clipit ---
  
  Without this regex only the first name is took.
  A whitespace need to be present before and after the triple dash.

  The script accept any extra command coming from cower e.g :
     
     retrovol --threads=8
     retrovol clipit --- --threads=8
     
  See man cower for more informations.
  
  If you leave the name blank, the script check for all installed package coming from AUR.
  
  You can switch to the main command entering his name e.g :
     download #switch to the download command
     build #switch to the build command
     quit #to exit from the script
EOF
}
