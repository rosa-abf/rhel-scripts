#!/bin/sh

echo '--> publish-build-list-script: resign.sh'

usermod -a -G vboxsf vagrant

platform_type="$TYPE"
released="$RELEASED"
rep_name="$REPOSITORY_NAME"

# /home/vagrant/share_folder contains:
# - http://abf.rosalinux.ru/downloads/rosa2012.1/repository
repository_path=/home/vagrant/share_folder

gnupg_path=/home/vagrant/.gnupg
if [ ! -d "$gnupg_path" ]; then
  echo "--> $gnupg_path does not exist"
  exit 0
fi

keyname=`gpg --with-fingerprint $gnupg_path/secring.gpg | sed -n 1p | awk '{ print $2 }' | awk '{ sub(/.*\//, ""); print }'`

function resign_all_rpm_in_folder {
  folder=$1
  if [ -d "$folder" ]; then
    for file in $( ls -1 $folder/ | grep .rpm$ ) ; do
      rpm --addsign $folder/$file --define="_gpg_path ~/.gnupg" --define="_gpg_name $keyname"
    done
  fi
}

repos="release updates"
arches="SRPMS i585 x86_64"
for arch in $arches ; do
  for rep in $repos ; do
    resign_all_rpm_in_folder "$repository_path/$arch/$rep_name/$rep"
  done
done

exit 0