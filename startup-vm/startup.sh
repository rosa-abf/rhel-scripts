#!/bin/sh

sudo yum install -y tree nfs-utils
sudo /bin/bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

exit 0