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
	
${bold}Usage: ${0} [options] [args]${reset}

${bold}options:${reset}
    
    origin : check origin of packages
    applysys : wrap up a sysusers file 
    applytmp : wrap up all tmpfiles
    aur : manage package from AUR repositories
    
${bold}args :${reset}
    
    for origin :
        give the name of the repo to check.
        if an empty value is detected,
        obarun is picked by default.
	
    for applysys :
        name of the file to parse.
        can be a list e.g. nbd.conf qemu.conf
    
    for applytmp :
        this option do not accept any args.
        
    for	aur :
        this option do not accept any args.
EOF
	exit 0
}

##			ORIGIN FUNCTIONS

# ${1} name of the repos to use
find_origin(){
	local ori check ver repo_origin parse_ori parse_ori_repo parse_ori_name parse_ori_version
	
	repo_origin="${1}"
	
	for check in ${both[@]};do 
		
		if [[ "$check" != obarun-@(mkiso|install|build) ]]; then
		
			printf "\r${bold}     -> Check %s package${reset}" "$check"
			tput el #return to the last line
		
			while read ori; do
			
				parse_ori=${ori}
				
				#retrieve only the repo
				parse_ori_repo=${parse_ori%%/*}
			
				# retrieve only the name
				parse_ori_name=${parse_ori##*/}
				parse_ori_name=${parse_ori_name%%' '*}
				
				#retrieve only the version
				#if the value not return a version format then the package do not come from $repo_origin
				if [[ "${parse_ori_name}" == "$check" ]]; then ## avoid search regex on packages description
					parse_ori_version=${parse_ori##*[}
					ver=$(grep ":" <<< "${parse_ori_version}")
					
					if (( "${#ver}" ));then
						parse_ori_version=${parse_ori_version##*' '}
						parse_ori_version=${parse_ori_version%%]*}
					else
						unset parse_ori_version
					fi
					unset ver
				fi
				
				check_var(){
					printf "\n"
					echo ori :: ${ori}
					echo parse_ori :: ${parse_ori}
					echo parse_ori_repo :: ${parse_ori_repo%%/}
					echo parse_ori_name :: ${parse_ori_name}
					echo ver :: ${ver}
					echo parse_ori_version :: ${parse_ori_version}
				}
				#check_var
				
				# version is not empty, the package installed do not come from $repo_origin
				if (( ${#parse_ori_version} )); then
					false+=("$check")
				fi
				
				unset parse_ori parse_ori_repo parse_ori_name parse_ori_version
			
			done < <(pacman -Ss "$check" | grep "${repo_origin}")
		fi
	done
	 
	printf "\n${bold}==>> Finished ${reset}\n"

	unset ori check ver repo_origin parse_ori parse_ori_repo parse_ori_name parse_ori_version
}

# ${1} name of the repos to use
# if empty, obarun is set by default
check_package(){
	
	local named item repo
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
	
	out_action "Verifying ${repo} packages repository"
	
	#check origin of package
	find_origin "${repo}"
	
	if (( "${#false}" )); then 
		printf "${byellow}==>> These/those package(s) do not come from ${repo} repository :${reset}\n" 
		for no in "${false[@]}"; do
			echo_bold "	-> $no"
		done
		out_action "Do you want to replace this/those package(s) [y|n]"
		reply_answer
		if (( ! $? )); then
			for i in "${false[@]}"; do
				pacman -S "${repo}"/$i
			done
		fi
	fi
	
	unset named item repo both false repo_db
}

##				TMPFILE FUNCTION

tmpfiles(){
	/etc/s6/data/scripts/tmpfiles.sh --create
}
