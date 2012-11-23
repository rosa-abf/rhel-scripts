#!/bin/sh

echo 'rpmbuild script!'

commit_hash="9272c173c517178b5c039c4b196c719b472147a7"
git_project_address="https://abf.rosalinux.ru/import/qtiplot.git"

repo="http://mirror.rosalinux.com/rosa/rosa2012.1/repository/x86_64/"
distrib_type="rosa2012.1"

urpmi.addmedia $distrib_type --distrib $repo
sudo urpmi git-core --auto --force

git clone $git_project_address project
cd project
git checkout $commit_hash





# :plname => save_to_platform.name,
# :arch => arch.name,
# :bplname => (save_to_platform_id == build_for_platform_id ? '' : build_for_platform.name),
# :update_type => update_type,
# :build_requires => build_requires,
# :id => id,
# :include_repos => include_repos_hash,
# :priority => priority,
# :git_project_address => project.git_project_address