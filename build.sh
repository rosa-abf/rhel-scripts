#!/bin/sh

echo '--> publish-build-list-script: build.sh'

usermod -a -G vboxsf vagrant

platform_type="$TYPE"
released="$RELEASED"
rep_name="$REPOSITORY_NAME"

echo "TYPE = $platform_type"
echo "RELEASED = $released"
echo "REPOSITORY_NAME = $rep_name"

# Current path:
# - /home/vagrant/publish-build-list-script
script_path=/home/vagrant/publish-build-list-script

# Container path:
# - /home/vagrant/container
container_path=/home/vagrant/container

# /home/vagrant/share_folder contains:
# - http://abf.rosalinux.ru/downloads/rosa2012.1/repository
# - http://abf.rosalinux.ru/downloads/akirilenko_personal/repository/rosa2012.1
platform_path=/home/vagrant/share_folder

repository_path=$platform_path

# Checks 'released' status of platform
status='release'
if [ "$released" == 'true' ] ; then
  status='updates'
fi

# Defines "media_info"/"repodata" folder
m_info_folder='repodata'
if [ "$platform_type" == 'mdv' ] ; then
  m_info_folder='media_info'
fi

# Checks that 'repository' directory exist
mkdir -p $repository_path/{SRPMS,i585,x86_64}/$rep_name/$status/$m_info_folder


rx=0
update_repo=1
arches="SRPMS i585 x86_64"
file_store_url='http://file-store.rosalinux.ru/api/v1/file_stores'
for arch in $arches ; do
  main_folder=$repository_path/$arch/$rep_name
  rpm_backup="$main_folder/$status-rpm-backup"
  rpm_new="$main_folder/$status-rpm-new"
  m_info_backup="$main_folder/$status-$m_info_folder-backup"
  rm -rf $rpm_backup $rpm_new $m_info_backup
  mkdir {$rpm_backup,$rpm_new,$m_info_backup}
  cp -rf $main_folder/$status/$m_info_folder/* $m_info_backup/

  # Downloads new packages
  new_packages="$container_path/new.$arch.list"
  if [ -f "$new_packages" ]; then
    cd $rpm_new
    for sha1 in `cat $new_packages` ; do
      fullname=`ruby $script_path/extract_filename.rb -s $sha1`
      if [ "$fullname" != '' ] ; then
        curl -O -L "$file_store_url/$sha1"
        mv $sha1 $fullname
        echo $fullname >> "$new_packages.downloaded"
        chown root:root $fullname
        chmod 0666 $fullname
        RPM_PATH=$rpm_new/$fullname /bin/bash $script_path/sign_rpm.sh
      else
        echo "--> Package with sha1 '$sha1' does not exist!!!"
      fi
    done
    mv $rpm_new/* $main_folder/$status/
  else
    update_repo=0
  fi  
  rm -rf $rpm_new

  # Creates backup
  old_packages="$container_path/old.$arch.list"
  if [ -f "$old_packages" ]; then
    for fullname in `cat $old_packages` ; do
      package=$rpm_backup/$status/$fullname
      if [ -f "$package" ]; then
        mv $package $rpm_backup/
      fi
    done
    update_repo=1
  else
    update_repo=0
  fi  

  if [ $update_repo != 1 ] ; then
    break
  fi  

  # Build repo
  cd $script_path/
  if [ "$platform_type" == 'mdv' ] ; then
    echo "/usr/bin/genhdlist2 -v -v --nolock --allow-empty-media --xml-info $main_folder/$status"
    /usr/bin/genhdlist2 -v -v --nolock --allow-empty-media --xml-info "$main_folder/$status"
    # Save exit code
    rc=$?
  else
    comps_xml=/home/vagrant/server-comps_xml-master/res6-comps.xml
    if [ ! -f "$comps_xml" ]; then
      cd /home/vagrant
      curl -L -O https://abf.rosalinux.ru/server/comps_xml/archive/server-comps_xml-master.tar.gz
      tar -xzf server-comps_xml-master.tar.gz
      rm server-comps_xml-master.tar.gz
    fi

    echo "createrepo -v --update -d -g $comps_xml -o $main_folder/$status $main_folder/$status"
    createrepo -v --update -d -g "$comps_xml" -o "$main_folder/$status" "$main_folder/$status"
    # Save exit code
    rc=$?
  fi

  # Check exit code
  if [ $rc != 0 ] ; then
    break
  fi

done

# Check exit code after build and rollback
if [ $rc != 0 ] ; then
  TYPE=$platform_type RELEASED=$released REPOSITORY_NAME=$rep_name USE_FILE_STORE=false /bin/bash $script_path/rollback.sh
else
  for arch in SRPMS i585 x86_64 ; do
    main_folder=$repository_path/$arch/$rep_name
    rpm_backup="$main_folder/$status-rpm-backup"
    rpm_new="$main_folder/$status-rpm-new"
    m_info_backup="$main_folder/$status-$m_info_folder-backup"
    rm -rf $rpm_backup $rpm_new $m_info_backup
  done
fi

exit $rc