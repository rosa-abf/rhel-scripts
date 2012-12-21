#!/bin/sh

echo '--> publish-build-list-script: sign_rpm.sh'

rpm_path="$RPM_PATH"

gnupg_path=/home/vagrant/.gnupg
if [ ! -d "$gnupg_path" ]; then
  echo "--> $gnupg_path does not exist"
  exit 0
fi

keyname=`gpg --with-fingerprint $gnupg_path/secring.gpg | sed -n 1p | awk '{ print $2 }' | awk '{ sub(/.*\//, ""); print }'`
rpm --addsign $rpm_path --define="_gpg_path ~/.gnupg" --define="_gpg_name $keyname"
# Save exit code
rc=$?

printf "--> Package '$rpm_path' has"
if [[ $rc == 0 ]] ; then
  echo 'been signed successfully.'
else
  echo 'not been signed successfully!!!'
fi

exit 0