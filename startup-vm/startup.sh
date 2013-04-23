#!/bin/sh

sudo yum install -y tree nfs-utils
sudo /bin/bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo /bin/bash -c 'echo "185.4.234.68 file-store.rosalinux.ru" >> /etc/hosts'
sudo /bin/bash -c 'echo "195.19.76.241 abf.rosalinux.ru" >> /etc/hosts'

exit 0