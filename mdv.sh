#!/bin/sh

echo 'rpm-build-script: mdv.sh'

# mdv example:
# git_project_address="https://abf.rosalinux.ru/import/plasma-applet-stackfolder.git"
# commit_hash="bfe6d68cc607238011a6108014bdcfe86c69456a"
git_project_address="$GIT_PROJECT_ADDRESS"
commit_hash="$COMMIT_HASH"

uname="$UNAME"
email="$EMAIL"
platform_name="$PLATFORM_NAME"
platform_arch="$ARCH"

echo $git_project_address | awk '{ gsub(/\:\/\/.*\:\@/, "://[FILTERED]@"); print }'
echo $commit_hash
echo $uname
echo $email

archives_path="/home/vagrant/archives"
results_path="/home/vagrant/results"
tmpfs_path="/home/vagrant/tmpfs"
project_path="$tmpfs_path/project"
rpm_build_script_path=`pwd`

rm -rf $archives_path $results_path $tmpfs_path $project_path
mkdir  $archives_path $results_path $tmpfs_path $project_path

# Mount tmpfs
sudo mount -t tmpfs tmpfs -o size=30000M,nr_inodes=10M $tmpfs_path

# Download project
# Fix for: 'fatal: index-pack failed'
git config --global core.compression -1
git clone $git_project_address $project_path
cd $project_path
git remote rm origin
git checkout $commit_hash

# TODO: build changelog

# Downloads extra files by .abf.yml
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
    echo '--> There are more than one spec file in repository.'
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


config_name="mdv-$platform_arch.cfg"
config_dir=/etc/mock-urpm/
# Change output format for mock-urpm
sed '17c/format: %(message)s' $config_dir/logging.ini > ~/logging.ini
sudo mv -f ~/logging.ini $config_dir/logging.ini
if [[ "$platform_name" =~ .*lts$ ]] ; then
  config_name="mdv-lts-$platform_arch.cfg"
fi

# Init config file
default_cfg=$rpm_build_script_path/configs/default.cfg
cp $rpm_build_script_path/configs/$config_name $default_cfg
media_list=/home/vagrant/container/media.list

echo 'config_opts["urpmi_media"] = {' >> $default_cfg
first='1'
while read CMD; do
  name=`echo $CMD | awk '{ print $1 }'`
  url=`echo $CMD | awk '{ print $2 }'`
  if [ "$first" == '1' ] ; then
    echo "\"$name\": \"$url\"" >> $default_cfg
    first=0
  else
    echo ", \"$name\": \"$url\"" >> $default_cfg
  fi
done < $media_list
echo '}' >> $default_cfg


sudo rm -rf $config_dir/default.cfg
sudo ln -s $default_cfg $config_dir/default.cfg
mock-urpm --define="packager $uname $email"


# Build src.rpm
echo '--> Build src.rpm'
mock-urpm --buildsrpm --spec $tmpfs_path/SPECS/$spec_name --sources $tmpfs_path/SOURCES/ --resultdir $src_rpm_path --configdir $config_dir -v --no-cleanup-after
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
if [ $rc != 0 ] ; then
  echo '--> Build failed: mock-urpm encountered a problem.'
  exit 1
fi

# Build rpm
cd $src_rpm_path
src_rpm_name=`ls -1 | grep 'src.rpm$'`
echo '--> Building rpm...'
mock-urpm $src_rpm_name --resultdir $rpm_path -v --no-cleanup-after --no-clean
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
echo '--> Checking internet connection...'
sudo chroot $chroot_path ping -c 1 google.com

# Tests
test_log=$results_path/tests.log
test_root=$tmpfs_path/test-root
test_code=0
rpm -qa --queryformat "%{name}-%{version}-%{release}.%{arch}.%{disttag}%{distepoch}\n" --root $chroot_path >> $results_path/rpm-qa.log
if [ $rc == 0 ] ; then
  ls -la $rpm_path/ >> $test_log
  mkdir $test_root
  sudo urpmi -v --debug --no-verify --no-suggests --test $rpm_path/*.rpm --root $test_root --urpmi-root $chroot_path --auto >> $test_log 2>&1
  test_code=$?
  rm -rf $test_root
fi

if [ $rc == 0 ] && [ $test_code == 0 ] ; then
  ls -la $src_rpm_path/ >> $test_log
  mkdir $test_root
  sudo urpmi -v --debug --no-verify --test --buildrequires $src_rpm_path/*.rpm --root $test_root --urpmi-root $chroot_path --auto >> $test_log 2>&1
  test_code=$?
  rm -rf $test_root
fi

if [ $rc != 0 ] || [ $test_code != 0 ] ; then
  tree $chroot_path/builddir/build/ >> $results_path/chroot-tree.log
fi

# Umount tmpfs
cd /
sudo umount $tmpfs_path
rm -rf $tmpfs_path


move_logs $rpm_path 'rpm'

# Check exit code after build
if [ $rc != 0 ] ; then
  echo '--> Build failed!!!'
  exit 1
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

# Check exit code after testing
if [ $test_code != 0 ] ; then
  echo '--> Test failed, see: tests.log'
  exit 5
fi
echo '--> Build has been done successfully!'
exit 0
