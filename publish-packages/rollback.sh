#!/bin/sh

echo '--> rhel-scripts/publish-packages: rollback.sh'

released="$RELEASED"
rep_name="$REPOSITORY_NAME"
use_file_store="$USE_FILE_STORE"

echo "RELEASED = $released"
echo "REPOSITORY_NAME = $rep_name"

# Container path:
# - /home/vagrant/container
container_path=/home/vagrant/container

repository_path=/home/vagrant/share_folder
status='release'
if [ "$released" == 'true' ] ; then
  status='updates'
fi

arches="SRPMS i586 x86_64"
for arch in $arches ; do
  main_folder=$repository_path/$arch/$rep_name
  rpm_backup="$main_folder/$status-rpm-backup"
  repodata_backup="$main_folder/$status-repodata-backup"

  if [ -d "$rpm_backup" ] && [ "$(ls -A $rpm_backup)" ]; then
    mv $rpm_backup/* $main_folder/$status/
  fi

  if [ -d "$repodata_backup" ] && [ "$(ls -A $repodata_backup)" ]; then
    rm -rf $main_folder/$status/repodata
    cp -rf $repodata_backup $main_folder/$status/repodata
    rm -rf $repodata_backup
  fi

  # Remove new packages
  if [ "$use_file_store" != 'false' ]; then
    new_packages="$container_path/new.$arch.list"
    if [ -f "$new_packages" ]; then
      for sha1 in `cat $new_packages` ; do
        fullname=`sha1=$sha1 /bin/bash $script_path/extract_filename.sh`
        if [ "$fullname" != '' ] ; then
          rm -f $main_folder/$status/$fullname
        fi
      done
    fi
  else
    new_packages="$container_path/new.$arch.list.downloaded"
    if [ -f "$new_packages" ]; then
      for fullname in `cat $new_packages` ; do
        rm -f $main_folder/$status/$fullname
      done
      rm -rf $new_packages
    fi 
  fi

  rm -rf $rpm_backup $repodata_backup
done

# Unlocks repository for sync
for arch in $arches ; do
  rm -f $repository_path/$arch/$rep_name/.publish.lock
done

exit 0