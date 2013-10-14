#!/bin/sh

sudo yum install -y tree git
sudo /bin/bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

sudo usermod -a -G vboxsf vagrant

exit 0