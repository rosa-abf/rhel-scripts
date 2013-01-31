#!/bin/sh

echo '--> publish-build-list-script: resign.sh'

usermod -a -G vboxsf vagrant

platform_type="$TYPE"
released="$RELEASED"
rep_name="$REPOSITORY_NAME"

# /home/vagrant/share_folder contains:
# - http://abf.rosalinux.ru/downloads/rosa2012.1/repository
repository_path=/home/vagrant/share_folder

# Current path:
# - /home/vagrant/publish-build-list-script
script_path=/home/vagrant/publish-build-list-script

gnupg_path=/home/vagrant/.gnupg
if [ ! -d "$gnupg_path" ]; then
  echo "--> $gnupg_path does not exist"
  exit 0
fi

/bin/bash $script_path/init_rpmmacros.sh


function resign_all_rpm_in_folder {
  folder=$1
  if [ -d "$folder" ]; then
    for file in $( ls -1 $folder/ | grep .rpm$ ) ; do
      chmod 0666 $folder/$file
      rpm --addsign $folder/$file
      chmod 0644 $folder/$file
    done
  fi
}

for arch in SRPMS i586 x86_64 ; do
  for rep in release updates ; do
    resign_all_rpm_in_folder "$repository_path/$arch/$rep_name/$rep"
  done
done

exit 0