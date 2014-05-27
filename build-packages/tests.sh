#!/bin/sh

echo '--> rhel-scripts/build-packages: tests.sh'

rerun_tests=${RERUN_TESTS}
packages=${PACKAGES}
rc=${RC}
rpm_path=${RPM_PATH}

results_path=/home/vagrant/results
tmpfs_path=/home/vagrant/tmpfs
config_dir=/etc/mock/
prefix=''

r=`head -1 ${config_dir}/default.cfg |
  sed -e "s/config_opts//g" |
  sed -e "s/\[//g" |
  sed -e "s/\]//g" |
  sed -e "s/root//g" |
  sed -e "s/=//g" |
  sed -e "s/'//g"|
  sed -e "s/ //g"`
chroot_path=${tmpfs_path}/${r}/root
echo '--> Checking internet connection...'
sudo chroot $chroot_path ping -c 1 google.com

if [ "${rerun_tests}" == 'true' ] ; then
  [[ "${packages}" == '' ]] && echo '--> No packages!!!' && exit 1

  prefix='rerun-tests-'
  rc=0
  rpm_path=${tmpfs_path}/RPM
  mkdir -p ${rpm_path}
  cd ${rpm_path}

  arr=($packages)
  for package in ${arr[@]} ; do
    echo "--> Downloading '${package}'..."
    wget http://file-store.rosalinux.ru/api/v1/file_stores/${package} --content-disposition --no-check-certificate
  done
  mock --init --configdir ${config_dir} -v --no-cleanup-after --no-clean
fi

# Tests
test_log=${results_path}/${prefix}tests.log
test_code=0
rpm -qa --queryformat "%{name}-%{version}-%{release}.%{arch}.%{disttag}%{distepoch}\n" --root ${chroot_path} >> ${results_path}/${prefix}rpm-qa.log
if [ ${rc} == 0 ] ; then
  ls -la ${rpm_path}/ >> ${test_log}
  sudo yum -v --installroot=${chroot_path} install -y ${rpm_path}/*.rpm >> ${test_log} 2>&1
  test_code=$?
fi

if [ ${rc} == 0 ] && [ ${test_code} == 0 ] ; then
  ls -la ${src_rpm_path}/ >> ${test_log}
fi

if [ ${rc} != 0 ] || [ ${test_code} != 0 ] ; then
  tree ${chroot_path}/builddir/build/ >> ${results_path}/${prefix}chroot-tree.log
fi

# Umount tmpfs
cd /
# 'mock' of fedora18 does not support tmpfs
# if [ "$platform_name" != 'fedora18' ] ; then
#   sudo umount $tmpfs_path
# fi
sudo rm -rf $tmpfs_path

exit ${test_code}
