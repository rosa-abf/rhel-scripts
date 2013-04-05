#!/bin/sh

echo '--> rhel-scripts/publish-packages: init_rpmmacros.sh'

gnupg_path=/home/vagrant/.gnupg

gpg --list-keys
cp -f $gnupg_path/* /root/.gnupg/
gpg --list-keys
rpmmacros=~/.rpmmacros

rm -f $rpmmacros
keyname=`gpg --with-fingerprint $gnupg_path/secring.gpg | sed -n 1p | awk '{ print $2 }' | awk '{ sub(/.*\//, ""); print }'`
echo "%_signature gpg"        >> $rpmmacros
echo "%_gpg_name $keyname"    >> $rpmmacros
echo "%_gpg_path $gnupg_path" >> $rpmmacros
echo "%_gpgbin /usr/bin/gpg"  >> $rpmmacros
echo "%__gpg /usr/bin/gpg"    >> $rpmmacros
echo "--> keyname: $keyname"
exit 0