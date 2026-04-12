#!/bin/bash
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

debug() {
    [[ -n "${DEBUG:-}" ]] && echo -e "${YELLOW}[DEBUG] ${FUNCNAME[1]}: $*${NC}" >&2
}

usage() {
    debug "entering"
    echo '''
  Run this script with no arguments to proceed
Process to follow the development branch:
1. git checkout development
2. Do the following optional steps
  a. git fetch
  b. git reset --hard origin/development
3. if you want to:
  a. Add a new branch to development then add it to the end of branches file which could be found at the top of the repo
  b. Remove a branch from development then remove from development_branches file
  c. Pull in the latest copy of a branch alredy in development
'''
}

check_current_branch() {
    debug "entering"
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    debug "current_branch=${current_branch}"
    if [[ "${current_branch}" != "development" ]]; then
        debug "not on development branch -> returning 1"
        echo -e "${RED}restack: Can only be run from the development branch${NC}" >&2
        return 1
    fi
}

refresh_remote() {
    debug "entering"
    echo -e "${GREEN}restack: Refreshing server view${NC}"
    git fetch --prune --tags
    debug "git fetch returned $?"
}

check_in_sync() {
    debug "entering"
    local local_sha remote_sha
    local_sha=$(git rev-parse HEAD)
    remote_sha=$(git rev-parse origin/development)
    debug "local_sha=${local_sha} remote_sha=${remote_sha}"
    if [[ "${local_sha}" != "${remote_sha}" ]]; then
        debug "local development not in sync with origin -> returning 1"
        echo -e "${RED}restack: Someone else has changed development before you please, do the following:${NC}"
        echo -e "${RED}   1. git reset --hard origin/development${NC}"
        echo -e "${RED}   2. edit branches again with your changes if necessary${NC}"
        echo -e "${RED}   3. re-run the restack.sh script${NC}"
        return 1
    fi
}

remove_obsolete_branches() {
    debug "entering topdir=$1 tmpdir=$2"
    local topdir="$1"
    local tmpdir="$2"
    echo -e "${GREEN}restack: Remove obsolete development branches:${NC}"
    git branch -l -r | cut -d'/' -f2- > "${tmpdir}/remote_branches"
    grep -wf "${tmpdir}/remote_branches" "${topdir}/branches" > "${tmpdir}/branches" || true
    diff "${topdir}/branches" "${tmpdir}/branches"
    debug "filtered branches has $(wc -l < "${tmpdir}/branches") entries"

    if [[ ! -s "${tmpdir}/branches" ]]; then
        debug "empty filtered branches -> returning 1"
        echo -e "${RED}restack: Refusing to rebuild development with no development branches: ${NC}"
        return 1
    fi
}

recreate_from_main() {
    debug "entering topdir=$1 tmpdir=$2"
    local topdir="$1"
    local tmpdir="$2"
    echo -e "${GREEN}restack: Recreating development branch from main:${NC}"
    cp -p "${topdir}/restack.sh" "${tmpdir}/restack.sh"
    git reset --hard origin/main
    debug "git reset --hard origin/main returned $?"
    cp "${tmpdir}/branches" "${topdir}/branches"
}

verify_scripts_unchanged() {
    debug "entering topdir=$1 tmpdir=$2"
    local topdir="$1"
    local tmpdir="$2"
    if ! diff -q "${topdir}/restack.sh" "${tmpdir}/restack.sh"; then
        debug "restack.sh content differs -> returning 1"
        echo -e "${RED}restack: restack.sh: Script change detected. Aborting. Please re-run${NC}" >&2
        return 1
    fi
}

merge_branches() {
    debug "entering topdir=$1 tmpdir=$2"
    local topdir="$1"
    local tmpdir="$2"
    while read -r BRANCH; do
        debug "merging ${BRANCH}"
        echo -e "${GREEN}restack: Merging branch ${BRANCH} ...${NC}"
        if ! git merge --no-ff "origin/${BRANCH}"; then
            debug "git merge origin/${BRANCH} failed"
            echo -e "${RED}restack: Problems merging branch. Should flag so someone can investigate. Skipping ${BRANCH}${NC}" >&2
            git merge --abort
            echo "${BRANCH}" >> "${tmpdir}/skipped_branches"
        fi
    done < "${topdir}/branches"

    if [[ -s "${tmpdir}/skipped_branches" ]]; then
        debug "skipped_branches non-empty -> returning 2"
        echo -e "\n${RED}restack: The following branches failed to merge and were skipped:" >&2
        cat "${tmpdir}/skipped_branches" >&2
        echo -e "${NC}" >&2
        return 2
    fi
}

rebuild_development() {
    debug "entering"
    local topdir
    topdir=$(git rev-parse --show-toplevel)
    debug "topdir=${topdir}"

    check_current_branch || { debug "check_current_branch failed"; return 1; }
    refresh_remote
    check_in_sync || { debug "check_in_sync failed"; return 1; }

    local tmpdir
    tmpdir=$(mktemp -d /tmp/rebuild_development.XXX)
    trap "rm -rf '${tmpdir}'" RETURN
    debug "tmpdir=${tmpdir}"
    echo -e "${GREEN}restack: Create temporary area: ${tmpdir}${NC}"

    remove_obsolete_branches "${topdir}" "${tmpdir}" || { debug "remove_obsolete_branches failed"; return 1; }
    recreate_from_main "${topdir}" "${tmpdir}"
    verify_scripts_unchanged "${topdir}" "${tmpdir}" || { debug "verify_scripts_unchanged failed"; return 1; }
    merge_branches "${topdir}" "${tmpdir}"
    local rc=$?
    debug "merge_branches returned ${rc}"
    if [[ $rc -ne 0 ]]; then
        return $rc
    fi

    debug "done, returning 0"
    return 0
}

if [[ $# -gt 0 ]]; then
    usage
    exit 1
fi

TOPDIR=$(git rev-parse --show-toplevel)
LOG="${TOPDIR}/restack_log"
rebuild_development 2>&1 | tee "${LOG}.colour"
RESULT=${PIPESTATUS[0]}

if [[ ${RESULT} -eq 0 ]]; then
    if ! git add "${TOPDIR}/branches"; then
        echo -e "${RED}restack.sh: Failed to add development_branches"
        exit 1
    fi
    echo -e "${GREEN}restack.sh: Diffs to origin...${NC}" | tee -a "${LOG}.colour"
    git diff --name-only origin/development | grep -v 'restack_log' |
        while read -r FILE; do
            echo "${FILE}"
            git diff origin/development "${TOPDIR}/${FILE}" >> "${LOG}.colour"
        done
    sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" "${LOG}.colour" > "${LOG}"
    rm -f "${LOG}.colour"

    git add "${LOG}" && \
        git commit -a -m 'Merge branch information for development'
    COMMIT=$?

    if [[ $COMMIT -eq 0 ]] && git push --force-with-lease; then
        echo -e "${GREEN}restack.sh: Development rebuilt and pushed to origin${NC}"
        exit 0
    else
        echo -e "${RED}restack.sh: Development rebuilt sucessfully but failed to push. Try again as may have clashed with another user${NC}"
    fi
elif [[ ${RESULT} -eq 2 ]]; then
    echo -e "${RED}restack.sh; Development branch failed to rebuild cleanly You can try: ${NC}"
    echo -e "${RED}  1. asking the owners of the branch which failed to merge to rebase to the latest master ${NC}"
    echo -e "${RED}  2. create an integration branch for branches that truly clash to resolve conflicts in and merge that to development instead ${NC}"
    echo -e "${RED}  3. ask for help if the above fails ${NC}"
fi
exit 1
