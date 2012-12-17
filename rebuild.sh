#!/bin/sh

echo '--> publish-build-list-script: rebuild.sh'

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

# /home/vagrant/share_folder contains:
# - http://abf.rosalinux.ru/downloads/rosa2012.1/repository
# - http://abf.rosalinux.ru/downloads/akirilenko_personal/repository/rosa2012.1
platform_path=/home/vagrant/share_folder

# Checks 'released' status of platform
srpms_rep_path=$repository_path/SRPMS/$rep_name/release
rpms_rep_path=$repository_path/$arch/$rep_name/release
if [ "$released" == 'true' ] ; then
  srpms_rep_path=$repository_path/SRPMS/$rep_name/updates
  rpms_rep_path=$repository_path/$arch/$rep_name/updates
fi

rx=0
# Build repo
if [ "$platform_type" == 'mdv' ] ; then
  /usr/bin/genhdlist2 --xml-info $srpms_rep_path
  /usr/bin/genhdlist2 --xml-info $rpms_rep_path
else
  cd /home/vagrant
  curl -L -O https://abf.rosalinux.ru/server/comps_xml/archive/server-comps_xml-master.tar.gz
  tar -xzf server-comps_xml-master.tar.gz
  rm server-comps_xml-master.tar.gz

  comps_xml=/home/vagrant/server-comps_xml-master/res6-comps.xml

  createrepo -d -g $comps_xml -o $srpms_rep_path $srpms_rep_path
  createrepo -d -g $comps_xml -o $rpms_rep_path $rpms_rep_path
fi

exit 0