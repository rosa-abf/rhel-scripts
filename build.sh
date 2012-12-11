#!/bin/sh

echo 'publish-build-list-script'

platform_type="$TYPE"
released="$RELEASED"
rep_name="$REPOSITORY_NAME"
arch="$ARCH"

echo "TYPE = $platform_type"
echo "RELEASED = $released"
echo "REPOSITORY_NAME = $rep_name"
echo "ARCH = $arch"

# Current path:
# - /home/vagrant/publish-build-list-script
script_path=/home/vagrant/publish-build-list-script

# Container path:
# - /home/vagrant/container
container_path=/home/vagrant/container

# /home/vagrant/share_folder contains:
# - http://abf.rosalinux.ru/downloads/rosa2012.1
# - http://abf.rosalinux.ru/downloads/akirilenko_personal/rosa2012.1
platform_path=/home/vagrant/share_folder

# Checks that 'repository' directory exist
repository_path=$platform_path/repository
if [ ! -d "$repository_path" ]; then
  mkdir $repository_path
fi

# Checks that 'arch' directory exist
if [ ! -d "$repository_path/$arch" ]; then
  mkdir $repository_path/$arch
fi

# Checks that 'SRPMS' directory exist
if [ ! -d "$repository_path/SRPMS" ]; then
  mkdir $repository_path/SRPMS
fi

# Checks that repository with name 'rep_name' exist
if [ ! -d "$repository_path/SRPMS/$rep_name" ]; then
  mkdir $repository_path/SRPMS/$rep_name
fi
if [ ! -d "$repository_path/$arch/$rep_name" ]; then
  mkdir $repository_path/$arch/$rep_name
fi

# Checks 'released' status of platform
srpms_rep_path=$repository_path/SRPMS/$rep_name/release
rpms_rep_path=$repository_path/$arch/$rep_name/release
if [ "$released" == 'true' ] ; then
  srpms_rep_path=$repository_path/SRPMS/$rep_name/updates
  rpms_rep_path=$repository_path/$arch/$rep_name/updates
fi
if [ ! -d "$srpms_rep_path" ]; then
  mkdir $srpms_rep_path
fi
if [ ! -d "$rpms_rep_path" ]; then
  mkdir $rpms_rep_path
fi

# Creates backup of "media_info" folder
if [ -d "$srpms_rep_path/media_info" ]; then
  mkdir $srpms_rep_path/media_info_backup
  cp $srpms_rep_path/media_info/* $srpms_rep_path/media_info_backup/
fi
if [ -d "$rpms_rep_path/media_info" ]; then
  mkdir $rpms_rep_path/media_info_backup
  cp $rpms_rep_path/media_info/* $rpms_rep_path/media_info_backup/
fi

# Copy (src.)rpm to repository
for file in $( ls -1 $container_path/SRC_RPM ) ; do
  cp $container_path/SRC_RPM/$file $srpms_rep_path/
done
for file in $( ls -1 $container_path/RPM ) ; do
  cp $container_path/RPM/$file $rpms_rep_path/
done

rx=0
# Build repo
if [ "$platform_type" == 'mdv' ] ; then
  /usr/bin/genhdlist2 --xml-info $srpms_rep_path
  # Save exit code
  rc=$?
  # Check exit code after build and build rpm repo
  if [[ $rc == 0 ]] ; then
    /usr/bin/genhdlist2 --xml-info $rpms_rep_path
    # Save exit code
    rc=$?
  fi
else
  cd /home/vagrant
  curl -L -O https://abf.rosalinux.ru/server/comps_xml/archive/server-comps_xml-master.tar.gz
  tar -xzf server-comps_xml-master.tar.gz
  rm server-comps_xml-master.tar.gz

  comps_xml=/home/vagrant/server-comps_xml-master/res6-comps.xml

  createrepo -d -g $comps_xml -o $srpms_rep_path $srpms_rep_path
  # Save exit code
  rc=$?
  # Check exit code after build and build rpm repo
  if [[ $rc == 0 ]] ; then
    createrepo -d -g $comps_xml -o $rpms_rep_path $rpms_rep_path
    # Save exit code
    rc=$?
  fi
fi

# Check exit code after build and rollback
if [[ $rc != 0 ]] ; then
  for file in $( ls -1 $container_path/SRC_RPM ) ; do
    rm $srpms_rep_path/$file
  done
  for file in $( ls -1 $container_path/RPM ) ; do
    rm $rpms_rep_path/$file
  done
  exit $rc
fi