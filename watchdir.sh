#!/bin/bash



# VARIABLES
# Seconds each sleep will sleep for (was used for testing, but only created issues due to the non-atomicness)
	sleep_timer=1

# Directory we will monitor for changes
	watch_filedir='/home/dtorma/Materia/testing/beans'

# Path to log files directory
	watchlog_location="${HOME}/.watchlog"

# Log file of the main script
	mainlog=${watchlog_location}'watch.log'

# Log file where the original filelist along with inode number, file size in bytes, and modify times will be logged
	watchlog_orig=${watchlog_location}'watchlog_orig.temp'

# Log file where the directory will be re-checked and compared to the original watchlog log
	watchlog_new=${watchlog_location}'watchlog_new.temp'

# Queue log for updated files
	queuelog=${watchlog_location}'queue.temp'



# Check if the filepath input as the first argument exists, if it does, set it up as the directory to watch
	if [[ -d "${1}" ]]; then watch_filedir="${1}"; fi


# Create log file location if it does not exist in /home/USERNAME/.watchlog
	if [[ ! -d "${watchlog_location}" ]]
	then
		mkdir "${watchlog_location}"
	fi

# FUNCTIONS
# Save the list of files of the specified watch_filedir directory into the specified log file
function save_dir_contents () {
	while IFS= read -r line; do	printf "%s %s\n" "$(stat -c %i" "%s" "%Y "${line}")" "${line}" >> "${1}"; done < <(find "${watch_filedir}" -maxdepth 1 -type f)
}

# Just clear the specified log file after some change
function clear_logfile () { 
	# This IF is just here so we don't accidentally empty some other random files, with this, we that we only empty the log files we already defined.
	if [[ "${1}" == "${watchlog_orig}" ]] || [[ "${1}" == "${watchlog_new}" ]] || [[ "${1}" == "${queuelog}" ]]; then
		> "${1}" 
	fi
}

# Send string of text into main log file of the script
function send_to_main_log {
	printf "%s: %s\n" "$(date +%s)" "${1}" >> "${mainlog}"
}


# MAIN
# Send some starting info into the main log file of the script
	echo "" >> "${mainlog}"
	send_to_main_log "$(printf "Starting script at: %s" "$(date +%T" "%d/%m/%Y)")"
	send_to_main_log "$(printf "Watching dir: %s" "${watch_filedir}")"

# Clear out the original file log file in case there's anything left from any previous runs; give it a fresh kick and repopulate it afterwards
	clear_logfile "${watchlog_orig}"; save_dir_contents "${watchlog_orig}"
	update_original_watchlog=0

# Start of main loop of the script	
while true; do

	# (Clear it first and then) save the list of files of the directory into a new log file and compare if there are any discrepancies with the original log file.
		clear_logfile "${watchlog_new}"; save_dir_contents "${watchlog_new}"


		while IFS= read -r line
		do 
			# CREATED # 
				if [[ -z "$(grep "$(echo "${line}" | awk '{print $1}')" "${watchlog_orig}")" ]]
				then
					send_to_main_log "$(printf "CREATED: %s" "${line}")"
					update_original_watchlog=1
				
			# UPDATE COMPLETED #
				elif [[ "${update_queue}" -eq 1 ]] && [[ ! -z "$(grep ^"$(echo "${line}" | awk '{print $1}')"$ "${queuelog}")" ]]
				then
					if [[ ! -z "$(grep "$(echo "${line}" | awk '{print $1}')" "${watchlog_orig}" | grep "$(echo "${line}" | awk '{print $4}')"$ | grep "$(echo "${line}" | awk '{print $2}')")" ]]
					then
						send_to_main_log "$(printf "UPDATE_COMPLETED: %s" "${line}")"
						update_original_watchlog=1
						clear_update_queue=1
						sed -i "s/$(echo "${line}" | awk '{print $1}')/ /g" "${queuelog}"

						curl -s -v -H 'X-GitHub-Event: pull_request' -H 'Content-Type: application/json' -d '{"repository": {"clone_url": "'"${2}"'"}, "pull_request": {"head": {"sha": "master"}}}' "${3}" > /dev/null
					fi
				fi
		done < "${watchlog_new}"


		if [[ "${clear_update_queue}" -eq 1 ]]; then clear_update_queue=0; update_queue=0; fi


		while IFS= read -r line
		do 

			# DELETED # IF inode is not found in the new watchlog >> THEREFORE file is deleted
				# With this we GREP for the inode number, if there is NO inode number found with GREP, we can safely assume the file has been removed (if we take into account what inodes are and how they work)
				if [[ -z "$(grep "$(echo "${line}" | awk '{print $1}')" "${watchlog_new}")" ]]
				then
					send_to_main_log "$(printf "DELETED: %s" "${line}")"
					update_original_watchlog=1


			# RENAMED # IF inode is found but the name is NOT found in the new watchlog >> THEREFORE file is renamed
				# With this we GREP for the inode number, AND then we GREP for the filename (which is an && basically), and IF there are no results, that would mean the file on the inode number was renamed (since we already checked if the inode number does not exist anymore with previous IF)
				elif [[ -z "$(grep "$(echo "${line}" | awk '{print $1}')" "${watchlog_new}" | grep "$(echo "${line}" | awk '{print $4}')"$ )" ]]
				then
					send_to_main_log "$(printf "RENAMED: From %s to %s" "$(echo "${line}" | awk '{print $4}')" "$(grep "$(echo "${line}" | awk '{print $1}')" "${watchlog_new}" | awk '{print $4}')" )"
					update_original_watchlog=1


			# MODIFIED # ONLY MODIFICATION TIME # IF inode is found, AND name is found, AND filesize is same BUT modify time is not >> THEREFORE file was modified
				# With this two IFs, we take a look if the modify time has changed AND that the file size in bytes remained the same in the original and new watchlog file (which would simply not occur IF the file is being copied over)
				elif [[ ! -z "$(grep "$(echo "${line}" | awk '{print $1}')" "${watchlog_new}" | grep "$(echo "${line}" | awk '{print $4}')"$ | grep " $(echo "${line}" | awk '{print $2}') ")" ]] && [[ -z "$(grep "$(echo "${line}" | awk '{print $1}')" "${watchlog_new}" | grep "$(echo "${line}" | awk '{print $4}')"$ | grep "$(echo "${line}" | awk '{print $3}')")" ]]
				then
					send_to_main_log "$(printf "MODIFIED: %s" "${line}")"
					update_original_watchlog=1
			

			# UPDATE # IF inode is found, AND name is found, AND filesize has changed >> THEREFORE, file is being copied over
				# 
				elif [[ -z "$(grep "$(echo "${line}" | awk '{print $1}')" "${watchlog_new}" | grep "$(echo "${line}" | awk '{print $4}')"$ | grep "$(echo "${line}" | awk '{print $3}')")" ]]
				then
					send_to_main_log "$(printf "UPDATED: %s" "${line}")"
					update_original_watchlog=1
					update_queue=1

					if [[ -z "$(grep "$(echo "${line}" | awk '{print $1}')" "${queuelog}")" ]]
					then
						printf "%s\n" "$(echo "${line}" | awk '{print $1}')" >> "${queuelog}"
					fi	

				fi
		done < "${watchlog_orig}"


	# Sleep a little bit, since everyone needs a little bit of sleep from time to time!
		sleep "${sleep_timer}"


	# The flag is set once a change is noticed in the new log but it doesn't reflect in the original watchlog log
		if [[ "${update_original_watchlog}" -ne 0 ]]
		then
			cp "${watchlog_new}" "${watchlog_orig}"
			update_original_watchlog=0
		fi
done
