# Restack 
implementation of a simple git workflow

This self-contained bash script implements a simple git workflow which assumes the usages of main, development and feature branches.

## How the workflow supposed to be used

This script rebuilds ( restacks - thus the name ) of the development branch by taking a snapshot of main branch and then merging, one by one, feature branches from the 'branch' file which needs to existing in development branch.

If the process of restacking (rebuilding ) development branch completed ok - it gets force-pushed to the origin/development. Otherwise, in case of conflicts - the error is displayed
and the conflict between the feature branches needs to be resolved.

This workflow solves a general problem while working in a team of developers with multiple projects - the issue of integrating and testing all the features and 
making sure that development branch is always in synch with the main branch.

The releases are done from main branch after all the required for the release feature branches have been merged.
After that rerunning restack.sh - would remove redundant ( merged ) branches from 'branch' file

## Worklow example

Each developer, while starting a new feature branch, always creates it off main.

'''
git fetch
git checkout main
git reset --hard origin/main
git checkout -b feature_1
'''

then the work is done on feature_1.

When the time comes to add feature_1 to the 'development' branch 

'''
git checkout feature_1
git fetch
git rebase origin/main
git push --force-with-lease
git checkout development
git reset --hard origin/development

edit 'branches' file and add feature_1 to the end of file
./restack.sh
'''

in a happy case of no conflics - the development branch is restacked cleanly and pushed to origin.

In case of conflict - the conflict need to be resolved

