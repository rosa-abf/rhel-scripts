#!/bin/sh

echo '--> rhel-scripts/build-packages: build.sh'

# rhel example:
# git_project_address="https://abf.rosalinux.ru/server/gnome-settings-daemon.git"
# commit_hash="fbb2549e44d97226fea6748a4f95d1d82ffb8726"
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
git submodule update --init
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


config_dir=/etc/mock/
config_name="rhel-$platform_arch.cfg"

# Init config file
default_cfg=$rpm_build_script_path/configs/default.cfg
cp $rpm_build_script_path/configs/$config_name $default_cfg
media_list=/home/vagrant/container/media.list

echo "config_opts['macros']['%packager'] = '$uname <$email>'" >> $default_cfg
echo '
config_opts["yum.conf"] = """
[main]
cachedir=/var/cache/yum
debuglevel=1
reposdir=/dev/null
logfile=/var/log/yum.log
retries=20
obsoletes=1
gpgcheck=0
assumeyes=1
syslog_ident=mock
syslog_device=

# repos
  ' >> $default_cfg
while read CMD; do
  name=`echo $CMD | awk '{ print $1 }'`
  url=`echo $CMD | awk '{ print $2 }'`
  echo "
[$name]
name=$name
enabled=1
baseurl=$url
failovermethod=priority

  " >> $default_cfg
done < $media_list
echo '"""' >> $default_cfg

sudo rm -rf $config_dir/default.cfg
sudo ln -s $default_cfg $config_dir/default.cfg

# Build src.rpm
echo '--> Build src.rpm'
mock --buildsrpm --spec $tmpfs_path/SPECS/$spec_name --sources $tmpfs_path/SOURCES/ --resultdir $src_rpm_path --configdir $config_dir -v --no-cleanup-after
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
mock $src_rpm_name --resultdir $rpm_path -v --no-cleanup-after --no-clean
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
  sudo yum -v --installroot=$chroot_path install -y $rpm_path/*.rpm >> $test_log 2>&1
  test_code=$?
  rm -rf $test_root
fi

if [ $rc == 0 ] && [ $test_code == 0 ] ; then
  ls -la $src_rpm_path/ >> $test_log
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
