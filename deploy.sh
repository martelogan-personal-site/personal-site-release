#!/usr/bin/env bash

#####################################
### Script to automate build and ####
### deployment of personal website. #
### See Readme for details ##########
#####################################

# Source base credit to: 
# https://github.com/X1011/git-directory-deploy/blob/master/deploy.sh

set -o errexit # abort if any command fails
scriptname=$(basename "$0")

help_message="\
Usage: $scriptname
Deploy generated files to a git branch.

Options:

  -h, --help               Show this help information.
  -m, --message MESSAGE    Specify the commit message.
  -n, --no-hash            Don't append the source commit's hash to the message
  -f, --force              Force confirmation to all prompts (as possible)
  -c, --config-file PATH   Override default & environment variables' values
                           with those in set in the file at 'PATH'. Must be the
                           first option specified.
"

parse_args() {
	# Set args from a local environment file.
	if [ -e ".env" ]; then
		source .env
	fi

	# Set args from file specified on the command-line.
	if [[ $1 = "-c" || $1 = "--config-file" ]]; then
		source "$2"
		shift 2
	fi

	# Parse arg flags
	# If something is exposed as an environment variable, set/overwrite it
	# here. Otherwise, set/overwrite the internal variable instead.
	while : ; do
		if [[ $1 = "-h" || $1 = "--help" ]]; then
			echo "$help_message"
			exit 0
		elif [[ ( $1 = "-m" || $1 = "--message" ) && -n $2 ]]; then
			commit_message=$2
			shift 2
		elif [[ $1 = "-n" || $1 = "--no-hash" ]]; then
			GIT_DEPLOY_APPEND_HASH=false
			shift
		elif [[ $1 = "-f" || $1 = "--force" ]]; then
			FORCE_CONFIRM="y"
			shift
		else
			break
		fi
	done
}

prompt_confirmation() {
    CONFIRMATION="n"
    if [ -z $2 ]
    then
        read -p "$1" CONFIRMATION
    else
        CONFIRMATION=$2
    fi
}

main() {
	parse_args "$@"

	# default directories
	if [[ -z $src_directory ]]; then
		src_directory="personal-site-dev"
	fi
	if [[ -z $deploy_directory ]]; then
		deploy_directory="martelogan.github.io"
	fi

	# SOURCE DIRECTORY CHECKS

	cd $src_directory

	if ! git diff --exit-code --quiet --cached; then
		echo Aborting due to uncommitted changes in the index >&2
		return 1
	fi

	commit_title=`git log -n 1 --format="%s" HEAD`
	commit_hash=` git log -n 1 --format="%H" HEAD`
	
	# default commit message uses last title if a custom one is not supplied
	if [[ -z $commit_message ]]; then
		commit_message="$commit_title"
	fi
	
	# append hash to commit message unless no hash flag was found
	if [[ $append_hash = true ]]; then
		commit_message="$commit_message"$'\n\n'"generated from commit $commit_hash"
	fi

	cd ..

	# DEPLOY DIRECTORY CHECKS

	if [[ ! -d "$deploy_directory" ]]; then
		echo "Deploy directory '$deploy_directory' does not exist. Aborting." >&2
		return 1
	fi
	
	# must use short form of flag in ls for compatibility with OS X and BSD
	if [[ -z `ls -A "$deploy_directory" 2> /dev/null` && -z $allow_empty ]]; then
		echo "Deploy directory '$deploy_directory' is empty. Aborting." >&2
		return 1
	fi

	# build distribution
	cd $src_directory
	coffee --compile javascripts/*.coffee
	compass compile sass/*
	minify javascripts/ --clean
	minify stylesheets/ --clean
	git add -A
	git commit -m "Build: $commit_message"
	cd ..

	# publish distribution to local production environment
	cp $src_directory/javascripts/*.min.js $deploy_directory/javascripts/
	cp $src_directory/stylesheets/main.min.css $deploy_directory/stylesheets/
	cp $src_directory/images/* $deploy_directory/images/
	cp $src_directory/index.html $deploy_directory/
	cp $src_directory/LoganMartel.pdf $deploy_directory/

	cd $deploy_directory

	git add -A
	git commit -m "Publish: $commit_message"
	cd ..

	# release latest distribution per environment
	prompt_confirmation "Proceed to publish changes to development repo (y/n)? " $FORCE_CONFIRM
    if [[ $CONFIRMATION =~ ^[Yy]$ ]]; then
    	cd $src_directory
        git push --set-upstream origin master
        cd ..
    fi

    prompt_confirmation "Proceed to publish changes to production repo (y/n)? " $FORCE_CONFIRM
    if [[ $CONFIRMATION =~ ^[Yy]$ ]]; then
    	cd $deploy_directory
        git push --set-upstream origin master
        cd ..
    fi

    prompt_confirmation "Proceed to publish changes to release repo (y/n)? " $FORCE_CONFIRM
    if [[ $CONFIRMATION =~ ^[Yy]$ ]]; then
    	git add -A
    	git commit -m "Release: $commit_message"
        git push --set-upstream origin master
    fi
}

[[ $1 = --source-only ]] || main "$@"
