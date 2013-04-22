#!/bin/sh

echo '--> rhel-scripts/publish-packages: build.sh'

released="$RELEASED"
rep_name="$REPOSITORY_NAME"
is_container="$IS_CONTAINER"
id="$ID"
platform_name="$PLATFORM_NAME"
regenerate_metadata="$REGENERATE_METADATA"

echo "RELEASED = $released"
echo "REPOSITORY_NAME = $rep_name"

# Current path:
# - /home/vagrant/scripts/publish-packages
script_path=`pwd`

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

repo_file="$platform_path/$id.repo"
if [ "$is_container" == 'true' ] ; then
  rm -f $repo_file
fi

# Checks that 'repository' directory exist
mkdir -p $repository_path/{SRPMS,i586,x86_64}/$rep_name/$status/repodata

sign_rpm=0
gnupg_path=/home/vagrant/.gnupg
if [ ! -d "$gnupg_path" ]; then
  echo "--> $gnupg_path does not exist"
else
  sign_rpm=1
  /bin/bash $script_path/init_rpmmacros.sh
fi


comps_xml=/home/vagrant/comps_xml-master/res6-comps.xml
if [ ! -f "$comps_xml" ]; then
  cd /home/vagrant
  curl -L -O https://abf.rosalinux.ru/server/comps_xml/archive/comps_xml-master.tar.gz
  tar -xzf comps_xml-master.tar.gz
  rm comps_xml-master.tar.gz
fi

function build_repo {
  path=$1
  arch=$2
  regenerate=$3
  # Build repo
  tmp_dir="~/tmp-$arch"
  rm -rf $tmp_dir $path/.olddata
  mkdir $tmp_dir
  cd $tmp_dir/
  echo "--> [`LANG=en_US.UTF-8  date -u`] Generating repository..."
  if [ "$regenerate" != 'true' ] ; then
    echo "createrepo -v --update -d -g $comps_xml -o $path $path"
    createrepo -v --update -d -g "$comps_xml" -o "$path" "$path"
  else
    echo "createrepo -v -d -g $comps_xml -o $path $path"
    createrepo -v -d -g "$comps_xml" -o "$path" "$path"
  fi
  # Save exit code
  echo $? > "$container_path/$arch.exit-code"
  rm -rf $tmp_dir
  echo "--> [`LANG=en_US.UTF-8  date -u`] Done."
}

rx=0
arches="SRPMS i586 x86_64"
file_store_url='http://file-store.rosalinux.ru/api/v1/file_stores'
for arch in $arches ; do
  update_repo=0
  main_folder=$repository_path/$arch/$rep_name
  rpm_backup="$main_folder/$status-rpm-backup"
  rpm_new="$main_folder/$status-rpm-new"
  repodata_backup="$main_folder/$status-repodata-backup"
  rm -rf $rpm_backup $rpm_new $repodata_backup
  mkdir {$rpm_backup,$rpm_new}
  cp -rf $main_folder/$status/repodata $repodata_backup

  # Downloads new packages
  echo "--> [`LANG=en_US.UTF-8  date -u`] Downloading new packages..."
  new_packages="$container_path/new.$arch.list"
  if [ -f "$new_packages" ]; then
    cd $rpm_new
    for sha1 in `cat $new_packages` ; do
      fullname=`sha1=$sha1 /bin/bash $script_path/extract_filename.sh`
      if [ "$fullname" != '' ] ; then
        curl -O -L "$file_store_url/$sha1"
        mv $sha1 $fullname
        echo $fullname >> "$new_packages.downloaded"
        # Add signature to RPM
        if [ $sign_rpm != 0 ] ; then
          chmod 0666 $fullname
          rpm --addsign $rpm_new/$fullname
          # Save exit code
          rc=$?
          if [[ $rc == 0 ]] ; then
            echo "--> Package '$fullname' has been signed successfully."
          else
            echo "--> Package '$fullname' has not been signed successfully!!!"
          fi
        fi
        chmod 0644 $rpm_new/$fullname
      else
        echo "--> Package with sha1 '$sha1' does not exist!!!"
      fi
    done
    update_repo=1
  fi
  echo "--> [`LANG=en_US.UTF-8  date -u`] Done."

  # Creates backup
  echo "--> [`LANG=en_US.UTF-8  date -u`] Creating backup..."
  old_packages="$container_path/old.$arch.list"
  if [ -f "$old_packages" ]; then
    for fullname in `cat $old_packages` ; do
      package=$main_folder/$status/$fullname
      if [ -f "$package" ]; then
        echo "mv $package $rpm_backup/"
        mv $package $rpm_backup/
      fi
    done
    update_repo=1
  fi
  echo "--> [`LANG=en_US.UTF-8  date -u`] Done."

  if [ -f "$new_packages" ]; then
    mv $rpm_new/* $main_folder/$status/
  fi
  rm -rf $rpm_new

  if [ $update_repo != 1 ] ; then
    if [ "$is_container" == 'true' ] ; then
      rm -rf $repository_path/$arch
    fi
    if [ "$regenerate_metadata" != 'true' ] ; then
      continue
    fi
  fi

  build_repo "$main_folder/$status" "$arch" "$regenerate_metadata" &

  if [ "$is_container" == 'true' ] ; then
    name="container-$id-$arch"
    echo "[$name]"    >> $repo_file
    echo "name=$name" >> $repo_file
    echo "enabled=1"  >> $repo_file
    echo "gpgcheck=0" >> $repo_file
    echo "baseurl=http://abf.rosalinux.ru/downloads/$platform_name/container/$id/$arch/$rep_name/$status" >> $repo_file
    echo "failovermethod=priority" >> $repo_file
  fi

done

# Waiting for createrepo...
wait

rc=0
# Check exit codes
for arch in SRPMS i586 x86_64 ; do
  path="$container_path/$arch.exit-code"
  if [ -f "$path" ] ; then
    rc=`cat $path`
    if [ $rc != 0 ] ; then
      rpm -qa | grep genhdlist2
      break
    fi
  fi
done

# Check exit code after build and rollback
if [ $rc != 0 ] ; then
  cd $script_path/
  sudo RELEASED=$released REPOSITORY_NAME=$rep_name USE_FILE_STORE=false /bin/bash $script_path/rollback.sh
else
  for arch in SRPMS i586 x86_64 ; do
    main_folder=$repository_path/$arch/$rep_name
    rpm_backup="$main_folder/$status-rpm-backup"
    rpm_new="$main_folder/$status-rpm-new"
    repodata_backup="$main_folder/$status-repodata-backup"
    rm -rf $rpm_backup $rpm_new $repodata_backup
  done
fi

exit $rc