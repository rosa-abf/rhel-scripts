#!/bin/sh

echo '--> publish-build-list-script: sign_rpm.sh'

rpm_path="$RPM_PATH"
gnupg_path=/home/vagrant/.gnupg
if [ ! -d "$gnupg_path" ]; then
  echo "--> $gnupg_path does not exist"
  exit 0
fi

# Hot fix
# TODO: Fix me!!!
# see: http://file-store.rosalinux.ru/api/v1/file_stores/6af8c79d307b437a56a01b031e052b88b1d310d8.log?show=true
cp -rf $gnupg_path /root/.gnupg

keyname=`gpg --with-fingerprint $gnupg_path/secring.gpg | sed -n 1p | awk '{ print $2 }' | awk '{ sub(/.*\//, ""); print }'`
rpm -vv --  $rpm_path --define="_gpg_path $gnupg_path" --define="_gpg_name $keyname" --define="_signature gpg" --define="_gpgbin /usr/bin/gpg"
# Save exit code
rc=$?

if [[ $rc == 0 ]] ; then
  echo "--> Package '$rpm_path' has been signed successfully."
else
  echo "--> Package '$rpm_path' has not been signed successfully!!!"
fi

exit 0