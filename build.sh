#!/bin/sh

echo 'rpm-build-script'

git_project_address="$GIT_PROJECT_ADDRESS"
# git_project_address="https://abf.rosalinux.ru/import/qtiplot.git"
commit_hash="$COMMIT_HASH"
# commit_hash="9272c173c517178b5c039c4b196c719b472147a7"

# repo="http://mirror.rosalinux.com/rosa/rosa2012.1/repository/x86_64/"
# distrib_type="rosa2012.1"

echo $git_project_address
echo $commit_hash

archives_path="/home/vagrant/archives"
results_path="/home/vagrant/results"
tmpfs_path="/home/vagrant/tmpfs"
project_path="$tmpfs_path/project"
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

# Mount tmpfs
mkdir $tmpfs_folder
sudo mount -t tmpfs tmpfs -o size=30000M,nr_inodes=10M $tmpfs_path

# Download project
mkdir $project_path
git clone $git_project_address $project_path
cd $project_path
git checkout $commit_hash


python $rpm_build_script_path/changelog.py $project_path
ruby $rpm_build_script_path/abf_yml.rb -p $project_path

# Remove .git folder
rm -rf $project_path/.git


# create SPECS folder and move *.spec
mkdir $tmpfs_path/SPECS
mv $project_path/*.spec $tmpfs_path/SPECS/
# Check count of *.spec files (should be one)
cd $tmpfs_path/SPECS
x=`ls -1 | grep '.spec$' | wc -l | sed 's/^ *//' | sed 's/ *$//'`
spec_name=`ls -1 | grep '.spec$'`
if [ $x -eq '0' ]
then
  echo "There are no spec files in repository."
  exit 1
else
  if [ $x -ne '1' ]
  then
    echo "There are more then one spec files in repository."
    exit 1
  fi
fi

#create SOURCES folder and move src
mkdir $tmpfs_path/SOURCES
mv $project_path/* $tmpfs_path/SOURCES/

# Buildsrpm
cd $archives_path
mock --buildsrpm --spec=$tmpfs_path/SPECS/$spec_name --sources=$tmpfs_path/SOURCES/
mock src.rpm

# Umount tmpfs
cd /
sudo umount $project_path

# :plname => save_to_platform.name,
# :arch => arch.name,
# :bplname => (save_to_platform_id == build_for_platform_id ? '' : build_for_platform.name),
# :update_type => update_type,
# :build_requires => build_requires,
# :id => id,
# :include_repos => include_repos_hash,
# :priority => priority,
# :git_project_address => project.git_project_address