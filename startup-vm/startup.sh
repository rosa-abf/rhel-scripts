#!/bin/sh

sudo yum install -y tree git rpm mock ruby
sudo /bin/bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

# sudo usermod -a -G vboxsf vagrant
sudo usermod -a -G  mock vagrant

# ABF_DOWNLOADS_PROXY, see: /etc/profile
if [ "$ABF_DOWNLOADS_PROXY" != '' ] ; then
  sudo /bin/bash -c "echo 'export http_proxy=$ABF_DOWNLOADS_PROXY' >> /etc/profile"
fi

exit 0