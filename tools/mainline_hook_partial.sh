#!/bin/bash
#set -x

# used for projects where some files are mainline, some are not
# we get a list of the files/directories out of the project's root.
#
# invocation   $0  ${repo_root} ${preupload_files}
#
# Example PREUPLOAD.cfg:
#
# [Hook Scripts]
# mainline_hook = ${REPO_ROOT}/frameworks/av/tools/mainline_hook_partial.sh ${REPO_ROOT} ${PREUPLOAD_FILES}
#
# MainlineFiles.cfg syntax:
#
# ignore comment (#) lines and blank lines
# rest are path prefixes starting at root of the project
# (so OWNERS, not frameworks/av/OWNERS)
# 
# path
# INCLUDE path
# EXCLUDE path
#
# 'path' and 'INCLUDE path' are identical -- they both indicate that this path
# is part of mainline
# EXCLUDE indicates that this is not part of mainline,
# so 'foo/' and 'EXCLUDE foo/nope'
# means everything under foo/ is part of mainline EXCEPT foo/nope.
# INCLUDE/EXCLUDE/INCLUDE nested structuring is not supported
#
# matching is purely prefix
# so 'foo' will match 'foo', 'foo.c', 'foo/bar/baz'
# if you want to exclude a directory, best to use a pattern like "foo/"
#

## tunables:
##
## as of 2024/5, things are all on the same branch.
DEV_BRANCH=main
MAINLINE_BRANCH=main
filelist_file=MainlineFiles.cfg

###

REPO_ROOT=$1; shift
# the rest of the command line is the file list
PREUPLOAD_FILES="$*"

RED=$(tput setaf 1)
NORMAL=$(tput sgr0)

## get the active branch:
## * <localbranch> <shainfo> [goog/master] Fix to handle missing checks on error returned
## strip this down to "master"
## * b157501573_advisory 25521834a6 [goog/sc-dev] Merge "PlayerBase: add audio session ID" into sc-dev
##
current=`git branch -vv | grep -P "^\*[^\[]+\[goog/"|sed -e 's/^.*\[//' | sed -e 's/\].*$//'|sed -e 's/:.*$//'| sed -e 's/^goog\///'`
if [ "${current}" = "" ] ; then
        current=unknown
fi

## figure out whether which files are for mainline and which are not
if [ "${PREUPLOAD_FILES}" = "" ] ; then
    # empty files? what's up there, i suppose we'll let that go
    exit 0
fi

## get the list of files out of the project's root
## figure out which way I'm going .. 
## use list of files to scan PREUPLOAD_FILES
## use PREUPLOAD_FILES to scan the list of good/bad from the project root
##
## remember to do an exclude, so I can say
## include/these/files/
## EXCLUDE include/these/files/nested/
##
## and it should all be prefix based stuff...

if [ ! -f ${REPO_ROOT}/${REPO_PATH}/${filelist_file} ] ; then
    echo "Poorly Configured project, missing ${filelist_file} in root of project"
    exit 1
fi

# is 1st arg a prefix of 2nd arg
beginswith() { case $2 in "$1"*) true;; *) false;; esac; }

exclusions=""
inclusions=""
while read p1 p2
do
    # ignore comment lines in the file
    # ignore empty lines in the file
    if beginswith "#" "${p1}" ; then
        # ignore this line
        true
    elif [ -z "${p1}" ] ; then
        # ignore blanks
        true
    elif [ ${p1} = "EXCLUDE" ] ; then
        # add to the exclusion list
        if [ ! -z ${p2} ] ; then
            exlusions="${exclusions} ${p2}"
        fi
    elif [ ${p1} = "INCLUDE" ] ; then
        # add to the inclusion list
        if [ ! -z ${p2} ] ; then
            inclusions="${inclusions} ${p2}"
        fi
    elif [ ! -z ${p1} ] ; then
        inclusions="${inclusions} ${p1}"
    fi
done < ${REPO_ROOT}/${REPO_PATH}/${filelist_file}

# so we can play with array syntax
#INCLUSIONS=( ${inclusions} )
#EXCLUSIONS=( ${exclusions} )

mainline_yes=""
mainline_no=""

# is it part of the list of mainline files/directories?
for path in ${PREUPLOAD_FILES} ; do
    #echo is ${path} a mainline file...
    for aprefix in ${inclusions} .. ; do
        #echo compare against ${aprefix} ...
        if [ "${aprefix}" = ".." ] ; then
            mainline_no="${mainline_no} ${path}"
        elif beginswith ${aprefix} ${path} ; then
            mainline_yes="${mainline_yes} ${path}"
            break       # on to next uploaded file
        fi
    done
done

# TODO: audit the yes list to see if some should be moved to the no list

# 3 situations
# -- everything is on mainline (mainline_yes non-empty, other empty)
# -- some is mainline, some is not (files_* both non-empty)
# -- none is mainline   (mainline_yes empty, other non_empty
# -- both empty only happens if PREUPLOAD_FILES is empty, covered above

if [ -z "${mainline_yes}" ] ; then
    # no mainline files, everything else is non-mainline, let it go 
    exit 0
fi

#
# exit 0 is "all good, no output passed along to user"
# exit 77 is "a warning, pass along the output to the user"
# exit 1 will be a failure.
#
result=0

# simple reminder that it should also land in mainline branch
#
if [ "${current}" != "${MAINLINE_BRANCH}" ] ; then
        # simple reminder to ensure it hits mainline
        result=77
        cat - <<EOF
You are uploading repo  ${RED}${REPO_PATH}${NORMAL} to branch ${RED}${current}${NORMAL}.
The mainline branch for ${RED}${REPO_PATH}${NORMAL} is branch ${RED}${MAINLINE_BRANCH}${NORMAL}.

Ensure an appropriate cherry pick or equivalent lands in branch ${RED}${MAINLINE_BRANCH}${NORMAL}.
Security bulletin timing or unreleased functionality may drive when this can be landed.
EOF
fi

# watch for the mixed some mainline / some not CL
# we usually want to reject such mixed CLs
#

if [ ! -z "${mainline_no}" ] ; then
        # mixed bag, suggest (not insist) that developer split them.
        result=1
        cat - <<EOF
This change contains both mainline and non-mainline files.  Please separate
them into separate CLs. It may also be appropriate to update the list of mainline
files in ${RED}${REPO_ROOT}/${filelist_file}${NORMAL}.

EOF
        echo "===== Mainline files ====="
        echo -e ${RED}
        echo ${mainline_yes} | sed -e 's/ //g'
        echo -e ${NORMAL}

        echo "===== Non-Mainline files ====="
        echo -e ${RED}
        echo ${mainline_no} | sed -e 's/ //g'
        echo -e ${NORMAL}

    cat - <<EOF

If you are sure you want to proceed uploading to branch ${RED}${current}${NORMAL},
re-run your repo upload command with the '--no-verify' option

EOF
fi

# result will be:
# 0: all good, no output passed to user
# 77: warnings (but we pass), output passed along to user
# else: failure, output passed along to the user

exit ${result}

