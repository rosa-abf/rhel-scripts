#!/bin/sh
results=`curl -sL http://file-store.rosalinux.ru/api/v1/file_stores?hash=$sha1 |
  grep -Po '"file_name":".*",' |
  sed -e 's/"file_name":"//g' |
  sed -e 's/",//g'`
echo $results