#!/bin/bash
#
# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 3 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE Linux GmbH.
#
# ------------------------------------------------------------------------------
# Author: Sören Schmidt <soeren.schmidt@suse.com>
#
# saptune_collector 
#
# Collects data about the saptune configuration on this host and writes them to stdout as a prometheus metrics.
# This collector only supports saptune v3 for now. 
#
# Changelog:    28.02.2022  v0.1     first incarnation
#               09.03.2022  v0.2     heavy rework
#               11.03.2022  v0.3     some bug fixing
#               11.03.2022  v0.4     added GPL header and saptune version metric
#               16.03.2022  v0.5     fixed issue with list output ('Remember...' lines)
#                                    sc_saptune{version=...} also set, if package is != v3
#                                    sc_timestamp now printed even with reduced metric
#                                    added information about how Note was enabled/applied
#               16.03.2022  v0.5.1   get rid of typos...
#               17.03.2022  v0.6     added `sc_saptune_service_active` and `sc_saptune_service_enabled`
#                                    added `sc_saptune_note_verify`
#               18.03.2022  v0.7     fixed brace error in metric
#                                    `sc_saptune_service_active` and `sc_saptune_service_enabled` report 0/1
#                                    verify output now base64 and newline stripped
#               18.03.2022  v0.8     verify output removed
#               22.03.2022  v0.9     change note verify to get results from every available_notes
#
# Exit codes:
#
#   0   everything is fine 
#   1   the saptune binary is not present
#   2   saptune version is not supported
#   3   saptune data could not be collected
#

version="0.8"

# Define exit codes.
exit_ok=0
exit_no_saptune=1
exit_unsupported=2
exit_retrieval_error=3

# Path to the saptune executable.
saptune_exe='/usr/sbin/saptune'

# ---- functions ----

function print_time_and_version_metric() {
    # Print the timestamp and version metric on stdout.
    #
    # Param:  version, package
    # Return: -

    local saptune_presence=1

    # If version information is missing, we assume saptune is missing.
    [ -z "${1}" -o -z "${2}" ] && saptune_presence=0

    echo "# HELP sc_timestamp Timestamp (epoch) when metrics were generated."
    echo "# TPYE sc_timestamp counter"
    echo "sc_timestamp $(date +'%s')"
    echo 
    echo "# HELP sc_saptune Version information of saptune."
    echo "# TPYE sc_saptune gauge"
    echo "sc_saptune{version=\"${1}\",package=\"${2}\"} ${saptune_presence}"
    echo 
}

# ---- main ----

# Terminate if there is no saptune executable.
[ -e "${saptune_exe}" ] || 
    { print_time_and_version_metric "" "" ; exit ${exit_no_saptune} ; }

# Get saptune package version.
saptune_package=$(rpm -q saptune) || exit ${exit_retrieval_error}
saptune_package_version="${saptune_package#saptune-}" ; saptune_package_version="${saptune_package_version%%.*}"

# Check for configured version.
saptune_version=$("${saptune_exe}" version) || exit ${exit_retrieval_error}
saptune_version="${saptune_version: -2:1}"  # Works only with one digit version numbers enclosed by ' at the end of the output!

# Exit in case it is not v3.
[ "${saptune_package_version}" != '3' -o "${saptune_version}" != '3'  ] && 
    { print_time_and_version_metric "${saptune_version}" "${saptune_package}" ; exit ${exit_unsupported} ; }

# Get information about saptune service unit.
saptune_service_active=0
saptune_service_enabled=0
systemctl is-active saptune.service > /dev/null 2>&1 && saptune_service_active=1
systemctl is-enabled saptune.service > /dev/null 2>&1 && saptune_service_enabled=1

# Retrieve all available Notes (available_notes) and there status (note_status) and Solutions (available_solutions).
declare -A available_notes available_solutions note_status
shopt -s extglob
while read line ; do 
    line="${line#*:}"
    status="${line:1:6}"
    line="${line:7}"
    id="${line%% *}"   
    name="${line:${#id}}" ; name="${name##*( )}"
    available_notes[${id}]=${name}
    case "${status}" in 
        *\**)   note_status[${id}]=1 ;;  # 1 -> enabled by solution
        *\+*)   note_status[${id}]=2 ;;  # 2 -> enabled manually
        *\-*)   note_status[${id}]=3 ;;  # 3 -> reverted from solution
        *)      note_status[${id}]=0 ;;  # 0 == not enabled
    esac
done < <(saptune note list |  sed '/^Remember/,$d' | grep -v -e 'current order of enabled note' -e '^[[:space:]]*Version [0-9]* from' -e '^All notes (+ denotes manually enabled' -e '^$' | expand -t 7 | nl -s :)
while read line ; do 
    id="${line%% - *}" ; id="${id%%*( )}"  
    name="${line##* - }"   
    available_solutions[${id}]=${name}
done < <(saptune solution list |  sed '/^Remember/,$d' | grep -v -e '^All solutions' -e '^$' | expand -t 7 | cut -c 8- )

# Retrieve enabled Notes.
notes=$(saptune note enabled) || exit ${exit_retrieval_error}
declare -A saptune_enabled_notes
for note in ${notes} ; do 
    saptune_enabled_notes[${note}]=1
done

# Retrieve applied Notes.
notes=$(saptune note applied) || exit ${exit_retrieval_error}
declare -A saptune_applied_notes
for note in ${notes} ; do 
    saptune_applied_notes[${note}]=1
done

# Retrieve enabled Solution.
saptune_enabled_solution=$(saptune solution enabled | tr -d '\n') || exit ${exit_retrieval_error}

# Retrieve applied Solution.
saptune_applied_solution=$(saptune solution applied | tr -d '\n') || exit ${exit_retrieval_error}

# Check compliance of all applied Notes.
saptune_compliance=1
declare -A saptune_verify_status
for id in "${!saptune_applied_notes[@]}"; do 
    status=1
    saptune note verify "${id}" > /dev/null 2>&1 || status=0
    saptune_verify_status[${id}]="${status}"
    saptune_compliance=$(( saptune_compliance && status ))
done 

# Output of full metrics.
print_time_and_version_metric "${saptune_version}" "${saptune_package}"
echo "# HELP sc_saptune_service_active Tells if saptune.service is active (1) or not (0)."
echo "# TYPE sc_saptune_service_active gauge"
echo "sc_saptune_service_active ${saptune_service_active}"
echo
echo "# HELP sc_saptune_service_enabled Tells if saptune.service is enabled (1) or not (0)."
echo "# TYPE sc_saptune_service_enabled gauge"
echo "sc_saptune_service_enabled ${saptune_service_enabled}"
echo
echo "# HELP sc_saptune_note_enabled Lists all available Notes and if they're enabled by a solution (1), enabled manually (2), reverted (3) or not enabled at all (3)."
echo "# TYPE sc_saptune_note_enabled gauge"
for id in "${!available_notes[@]}"; do 
    echo "sc_saptune_note_enabled{note_desc=\"${available_notes[$id]}\",note_id=\"${id}\"} ${note_status[$id]}"
done
echo 
echo "# HELP sc_saptune_note_applied Lists all available Notes and if they're applied (1) or not (0)."
echo "# TYPE sc_saptune_note_applied gauge"
for id in "${!available_notes[@]}"; do 
    status=0
    [ -n "${saptune_applied_notes[${id}]}" ] && status=1
    echo "sc_saptune_note_applied{note_desc=\"${available_notes[$id]}\",note_id=\"${id}\"} ${note_status[$id]}"
done
echo 
echo "# HELP sc_saptune_solution_enabled Lists all available Solutions and if it is enabled (1) or not (0)."
echo "# TYPE sc_saptune_solution_enabled gauge"
for id in "${!available_solutions[@]}"; do 
    status=0
    [ "${id}" = "${saptune_enabled_solution}" ] && status=1
    echo "sc_saptune_solution_enabled{note_list=\"${available_solutions[$id]}\",solution_id=\"${id}\"} ${status}"
done
echo 
echo "# HELP sc_saptune_solution_applied Lists all available Solutions and if it is applied (1) or not (0)."
echo "# TYPE sc_saptune_solution_applied gauge"
for id in "${!available_solutions[@]}"; do 
    status=0
    [ "${id}" = "${saptune_applied_solution}" ] && status=1
    echo "sc_saptune_solution_applied{note_list=\"${available_solutions[$id]}\",solution_id=\"${id}\"} ${status}"
done
echo 
echo "# HELP sc_saptune_note_verify Shows for each applied Notes if it is compliant (1) or not (0) and why."
echo "# TYPE sc_saptune_note_verify gauge"
for id in "${!available_notes[@]}"; do
    status=0
    [ -n "${saptune_verify_status[${id}]}" ] && status=1
    echo "sc_saptune_note_verify{note_id=\"${id}\"} $status"
done 
echo 
echo "# HELP sc_saptune_compliance Shows if applied Notes are compliant (1) or not (0)."
echo "# TYPE sc_saptune_compliance gauge"
echo "sc_saptune_compliance ${saptune_compliance}"

# Bye.
exit ${exit_ok}






