# Restack

Implementation of a simple git workflow.

This self-contained bash script implements a simple git workflow which assumes the usage of main, development, and feature branches.

## How the workflow is supposed to be used

This script rebuilds (restacks — thus the name) the development branch by taking a snapshot of the main branch and then merging, one by one, feature branches listed in the `branches` file, which needs to exist in the development branch.

If the process of restacking (rebuilding) the development branch completes successfully, it gets force-pushed to `origin/development`. Otherwise, in case of conflicts, the error is displayed and the conflict between the feature branches needs to be resolved.

This workflow solves a general problem when working in a team of developers with multiple projects — the issue of integrating and testing all the features and making sure that the development branch is always in sync with the main branch.

Releases are done from the main branch after all the feature branches required for the release have been merged. After that, rerunning `restack.sh` will remove redundant (merged) branches from the `branches` file.

## Workflow example

Each developer, while starting a new feature branch, always creates it off the main branch.

```bash
git fetch
git checkout main
git reset --hard origin/main
git checkout -b feature_1
```

Then the work is done on `feature_1`.

When the time comes to add `feature_1` to the `development` branch:

```bash
git checkout feature_1
git fetch
git rebase origin/main
git push --force-with-lease
git checkout development
git reset --hard origin/development

# edit 'branches' file and add feature_1 to the end of file
./restack.sh
```

In the happy case of no conflicts, the development branch is restacked cleanly and pushed to origin.

In case of conflict, the conflict needs to be resolved.

