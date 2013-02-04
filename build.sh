#!/bin/sh

echo 'rpm-build-script'

git_project_address="$GIT_PROJECT_ADDRESS"
commit_hash="$COMMIT_HASH"
uname="$UNAME"
email="$EMAIL"
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

echo $git_project_address | awk '{ gsub(/\:\/\/.*\:\@/, "://[FILTERED]@"); print }'
echo $commit_hash
echo $distrib_type
echo $uname
echo $email

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
# Fix for: 'fatal: index-pack failed'
git config --global core.compression -1
git clone $git_project_address $project_path
cd $project_path
git remote rm origin
git checkout $commit_hash

# TODO: build changelog
# python $rpm_build_script_path/changelog.py $project_path
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
  echo '--> There are no spec files in repository.'
  exit 1
else
  if [ $x -ne '1' ] ; then
    echo '--> There are more then one spec files in repository.'
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
  echo "Will be use 'mock-urpm'..."
  mock_command="mock-urpm"
  config_dir=/etc/mock-urpm/
  # Change output format for mock-urpm
  sed '17c/format: %(message)s' $config_dir/logging.ini > ~/logging.ini
  sudo mv -f ~/logging.ini $config_dir/logging.ini
fi

# Init config file
sudo rm -rf $config_dir/default.cfg
# default.cfg should be created before running script!!!!
sudo ln -s $rpm_build_script_path/configs/default.cfg $config_dir/default.cfg
%mock_command --define="packager $uname $email"


# Build src.rpm
echo '--> Build src.rpm'
$mock_command --buildsrpm --spec $tmpfs_path/SPECS/$spec_name --sources $tmpfs_path/SOURCES/ --resultdir $src_rpm_path --configdir $config_dir -v
# Save exit code
rc=$?
echo '--> Done.'

# Move all logs into the results dir.
function move_logs {
  prefix=$2
  for file in $1/*.log ; do
    name=`basename $file`
    if [[ "$name" =~ .*\.log$ ]] ; then
      echo "--> mv $file $results_path/$prefix-$name"
      mv $file "$results_path/$prefix-$name"
    fi
  done
}

move_logs $src_rpm_path 'src-rpm'

# Check exit code after build
if [[ $rc != 0 ]] ; then
  echo '--> Build failed: mock-urpm problem.'
  exit $rc
fi

# Build rpm
cd $src_rpm_path
src_rpm_name=`ls -1 | grep 'src.rpm$'`
echo '--> Build rpm'
$mock_command $src_rpm_name --resultdir $rpm_path -v --no-cleanup-after
# Save exit code
rc=$?
echo '--> Done.'

# Save results
# mv $tmpfs_path/SPECS $archives_path/
# mv $tmpfs_path/SOURCES $archives_path/

# Remove src.rpm from RPM dir
src_rpm_name=`ls -1 $rpm_path/ | grep 'src.rpm$'`
if [ "$src_rpm_name" != '' ] ; then
  rm $rpm_path/*.src.rpm
fi

r=`head -1 $config_dir/default.cfg |
  sed -e "s/config_opts//g" |
  sed -e "s/\[//g" |
  sed -e "s/\]//g" |
  sed -e "s/root//g" |
  sed -e "s/=//g" |
  sed -e "s/'//g"|
  sed -e "s/ //g"`
chroot_path=$tmpfs_path/$r/root
# echo '--> Checks internet connection...'
# sudo chroot $chroot_path ping -c 1 google.com

test_log=$results_path/tests.log
for file in $( ls -1 $rpm_path/ | grep .rpm$ ) ; do
  f=$rpm_path/$file
  if [ "$distrib_type" == 'mdv' ] ; then
    sudo urpmi --test $f --root $chroot_path --auto >> $test_log 2>&1
  else
    sudo yum --installroot=$chroot_path install -y $f >> $test_log 2>&1
  fi
done

for file in $( ls -1 $src_rpm_path/ | grep .rpm$ ) ; do
  f=$rpm_path/$file
  if [ "$distrib_type" == 'mdv' ] ; then
    sudo urpmi --test --buildrequires $f --root $chroot_path --auto >> $test_log 2>&1
  fi
done

# Umount tmpfs
cd /
sudo umount $tmpfs_path
rm -rf $tmpfs_path 


move_logs $rpm_path 'rpm'

# Check exit code after build
if [[ $rc != 0 ]] ; then
  echo '--> Build failed: mock-urpm problem.'
  exit $rc
fi

# Generate data for container
c_data=$results_path/container_data.json
echo '[' > $c_data
for rpm in $rpm_path/*.rpm $src_rpm_path/*.src.rpm ; do
  name=`rpm -qp --queryformat %{NAME} $rpm`
  if [ "$name" != '' ] ; then
    fullname=`basename $rpm`
    version=`rpm -qp --queryformat %{VERSION} $rpm`
    release=`rpm -qp --queryformat %{RELEASE} $rpm`
    sha1=`sha1sum $rpm | awk '{ print $1 }'`

    echo '{' >> $c_data
    echo "\"fullname\":\"$fullname\","  >> $c_data
    echo "\"sha1\":\"$sha1\","          >> $c_data
    echo "\"name\":\"$name\","          >> $c_data
    echo "\"version\":\"$version\","    >> $c_data
    echo "\"release\":\"$release\""     >> $c_data
    echo '},' >> $c_data
  fi
done
# Add '{}'' because ',' before
echo '{}' >> $c_data
echo ']' >> $c_data

# Move all rpms into results folder
echo "--> mv $rpm_path/*.rpm $results_path/"
mv $rpm_path/*.rpm $results_path/
echo "--> mv $src_rpm_path/*.rpm $results_path/"
mv $src_rpm_path/*.rpm $results_path/

# Remove archives folder
rm -rf $archives_path