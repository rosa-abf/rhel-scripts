#!/bin/sh

echo 'rpm-build-script'

git_project_address="$GIT_PROJECT_ADDRESS"
commit_hash="$COMMIT_HASH"
# mdv example:
# git_project_address="https://abf.rosalinux.ru/import/plasma-applet-stackfolder.git"
# commit_hash="bfe6d68cc607238011a6108014bdcfe86c69456a"

# rhel example:
# git_project_address="https://abf.rosalinux.ru/server/gnome-settings-daemon.git"
# commit_hash="fbb2549e44d97226fea6748a4f95d1d82ffb8726"

# repo="http://mirror.rosalinux.com/rosa/rosa2012.1/repository/x86_64/"
# distrib_type="rosa2012.1"
distrib_type="$DISTRIB_TYPE"
# distrib_type="mdv"
# arch="$ARCH"
# arch="x86_64"

echo $git_project_address
echo $commit_hash

archives_path="/home/vagrant/archives"
results_path="/home/vagrant/results"
tmpfs_path="/home/vagrant/tmpfs"
project_path="$tmpfs_path/project"
rpm_build_script_path=`pwd`

# urpmi.addmedia $distrib_type --distrib $repo
# sudo urpmi git-core --auto
# sudo urpmi python-lxml --auto
# sudo urpmi python-rpm --auto
# sudo urpmi mock-urpm --auto
# sudo urpmi mock --auto
# sudo urpmi rpm-build --auto
# sudo urpmi python-gitpython --auto
# sudo urpmi ruby --auto

mkdir $archives_path
mkdir $results_path

# Mount tmpfs
mkdir $tmpfs_path
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
if [ $x -eq '0' ] ; then
  echo "There are no spec files in repository."
  exit 1
else
  if [ $x -ne '1' ] ; then
    echo "There are more then one spec files in repository."
    exit 1
  fi
fi

#create SOURCES folder and move src
mkdir $tmpfs_path/SOURCES
mv $project_path/* $tmpfs_path/SOURCES/

# Init folders for building src.rpm
cd $archives_path
src_rpm_path=$archives_path/SRC_RPM
mkdir $src_rpm_path

rpm_path=$archives_path/RPM
mkdir $rpm_path

mock_command="mock"
config_dir=/etc/mock/
if [ "$distrib_type" == 'mdv' ] ; then
  mock_command="mock-urpm"
  config_dir=/etc/mock-urpm/
fi

# Init config file
sudo rm -rf $config_dir/default.cfg
# default.cfg should be created before running script!!!!
sudo ln -s $rpm_build_script_path/configs/default.cfg $config_dir/default.cfg

# Build src.rpm
$mock_command --buildsrpm --spec $tmpfs_path/SPECS/$spec_name --sources $tmpfs_path/SOURCES/ --resultdir $src_rpm_path --configdir $config_dir

# Build rpm
cd $src_rpm_path
src_rpm_name=`ls -1 | grep 'src.rpm$'`
$mock_command $src_rpm_name --resultdir $rpm_path

# Save exit code
rc=$?

# Save results
# mv $tmpfs_path/SPECS $archives_path/
# mv $tmpfs_path/SOURCES $archives_path/

# Umount tmpfs
cd /
sudo umount $tmpfs_path
rm -rf $tmpfs_path 

# Check exit code after build
if [[ $rc != 0 ]] ; then
  echo "Build failed: mock-urpm problem"
  exit $rc
fi