#!/bin/sh

echo '--> publish-build-list-script: rollback.sh'

platform_type="$TYPE"
released="$RELEASED"
rep_name="$REPOSITORY_NAME"
arch="$ARCH"

echo "TYPE = $platform_type"
echo "RELEASED = $released"
echo "REPOSITORY_NAME = $rep_name"
echo "ARCH = $arch"

# Container path:
# - /home/vagrant/container
container_path=/home/vagrant/container

repository_path=/home/vagrant/share_folder
srpms_rep_path=$repository_path/SRPMS/$rep_name/release
rpms_rep_path=$repository_path/$arch/$rep_name/release
if [ "$released" == 'true' ] ; then
  srpms_rep_path=$repository_path/SRPMS/$rep_name/updates
  rpms_rep_path=$repository_path/$arch/$rep_name/updates
fi

m_info_folder='repodata'
if [ "$platform_type" == 'mdv' ] ; then
  m_info_folder='media_info'
fi

# Rollback SRPM packages
if [ -d "$srpms_rep_path-backup" ]; then
  cp -f $srpms_rep_path-backup/* $srpms_rep_path/
  rm -rf $srpms_rep_path-backup
fi
# Rollback RPM packages
if [ -d "$rpms_rep_path-backup" ]; then
  cp -f $rpms_rep_path-backup/* $rpms_rep_path/
  rm -rf $rpms_rep_path-backup
fi

# Rollback "media_info"/"repodata" folder
if [ -d "$srpms_rep_path/$m_info_folder-backup" ]; then
  rm -rf "$srpms_rep_path/$m_info_folder"
  mv "$srpms_rep_path/$m_info_folder-backup" $srpms_rep_path/$m_info_folder
fi
if [ -d "$rpms_rep_path/$m_info_folder-backup" ]; then
  rm -rf "$rpms_rep_path/$m_info_folder"
  mv "$rpms_rep_path/$m_info_folder-backup" $rpms_rep_path/$m_info_folder
fi

for file in $( ls -1 $container_path/SRC_RPM ) ; do
  rm $srpms_rep_path/$file
done
for file in $( ls -1 $container_path/RPM ) ; do
  rm $rpms_rep_path/$file
done
exit 0