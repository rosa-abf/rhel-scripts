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

