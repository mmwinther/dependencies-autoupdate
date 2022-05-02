#!/bin/bash

# fail as soon as any command errors
set -e

token=$1
update_command=$2
update_path=$3
on_changes_command=$4
repo=$GITHUB_REPOSITORY #owner and repository: ie: user/repo
username=$GITHUB_ACTOR

branch_name="automated-dependencies-update"
email="noreply@github.com"

if [ -z "$token" ]; then
    echo "token is not defined"
    exit 1
fi

if [ -z "$update_command" ]; then
    echo "update-command cannot be empty"
    exit 1
fi

# remove optional params markers
update_path_value=${update_path%?}
if [ -n "$update_path_value" ]; then
    # if path is set, use that. otherwise default to current working directory
    echo "Change directory to $update_path_value"
    cd "$update_path_value"
fi

# assumes the repo is already cloned as a prerequisite for running the script

# fetch first to be able to detect if branch already exists 
git fetch

branch_exists=$(git branch --list automated-dependencies-update)

# branch already exists, previous opened PR was not merged
if [ -z "$branch_exists" ]; then
    # create new branch
    git checkout -b $branch_name
else
    echo "Branch name $branch_name already exists"

    # check out existing branch
    echo "Check out branch instead" 
    git checkout $branch_name
    git pull

    # reset with latest from main
    # this avoids merge conflicts when existing changes are not merged
    git reset --hard origin/main
fi

echo "Running update command $update_command"
eval $update_command

git diff --exit-code >/dev/null 2>&1
if [ $? = 1 ]
then
    echo "Updates detected"

    # configure git authorship
    git config --global user.email $email
    git config --global user.name $username

    # format: https://[username]:[token]@github.com/[organization]/[repo].git
    git remote add authenticated "https://$username:$token@github.com/$repo.git"

    # execute command to run when changes are deteced, if provided
    on_changes_command_value=${on_changes_command%?}
    echo $on_changes_command_value
    if [ -n "$on_changes_command_value" ]; then
        echo "Run post-update command"
        eval $on_changes_command_value
    fi

    # explicitly add all files including untracked
    git add -A

    # commit the changes to updated files
    git commit -a -m "Auto-updated dependencies" --signoff
    
    # push the changes
    git push authenticated -f -u origin HEAD

    echo "https://api.github.com/repos/$repo/pulls"

    # create the PR
    # if PR already exists, then update
    response=$(curl --write-out "%{message}\n" -X POST -H "Content-Type: application/json" -H "Authorization: token $token" \
         --data '{"title":"Autoupdate dependencies","head": "'"$branch_name"'","base":"main", "body":"Auto-generated pull request. \nThis pull request is generated by GitHub action based on the provided update commands."}' \
         "https://api.github.com/repos/$repo/pulls")
    
    echo $response   
    
    if [[ "$response" == *"already exist"* ]]; then
        echo "Pull request already opened. Updates were pushed to the existing PR instead"
        exit 0
    fi
else
    echo "No dependencies updates were detected"
    exit 0
fi
