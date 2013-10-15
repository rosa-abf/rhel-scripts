#!/bin/sh

sudo yum install -y tree git rpm mock ruby
sudo /bin/bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

# sudo usermod -a -G vboxsf vagrant
sudo usermod -a -G  mock vagrant

exit 0