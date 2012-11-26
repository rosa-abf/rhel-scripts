#!/bin/sh

echo 'rpm-build-script'

commit_hash="9272c173c517178b5c039c4b196c719b472147a7"
git_project_address="https://abf.rosalinux.ru/import/qtiplot.git"

repo="http://mirror.rosalinux.com/rosa/rosa2012.1/repository/x86_64/"
distrib_type="rosa2012.1"

project_path="/home/vagrant/project"
archives_path="/home/vagrant/archives"
results_path="/home/vagrant/results"
rpm_build_script_path=`pwd`

# urpmi.addmedia $distrib_type --distrib $repo
sudo urpmi git-core --auto
sudo urpmi python-lxml --auto
sudo urpmi python-rpm --auto
# sudo urpmi mock-urpm --auto
sudo urpmi rpm-build --auto
sudo urpmi python-gitpython --auto
sudo urpmi ruby --auto

mkdir $archives_path
mkdir $results_path

# Create tmpfs
sudo mount -t tmpfs tmpfs -o size=30000M,nr_inodes=10M $project_path

git clone $git_project_address $project_path
cd $project_path
git checkout $commit_hash


python $rpm_build_script_path/changelog.py $project_path
ruby $rpm_build_script_path/abf_yml.rb -p $project_path



# :plname => save_to_platform.name,
# :arch => arch.name,
# :bplname => (save_to_platform_id == build_for_platform_id ? '' : build_for_platform.name),
# :update_type => update_type,
# :build_requires => build_requires,
# :id => id,
# :include_repos => include_repos_hash,
# :priority => priority,
# :git_project_address => project.git_project_address