#!/usr/bin/env bash

sudo tee -a /etc/yum.repos.d/deloreantemp.repo <<EOF
[deloran-temp]
name=delorean-temp
baseurl=https://trunk.rdoproject.org/centos7-master/current
gpgcheck=0
enabled=1
EOF

sudo yum -y install python2-tripleo-repos

sudo rm -rf /etc/yum.repos.d/deloreantemp.repo
sudo -E tripleo-repos current-tripleo-dev 
sudo yum install -y python2-tripleoclient


sudo dd if=/dev/zero of=/swapfile-additional bs=1M count=8384
sudo mkswap /swapfile-additional
sudo chmod 600 /swapfile-additional
echo "/swapfile-additional swap swap 0 0" | sudo tee -a /etc/fstab
sudo mount -a
sudo swapon -a
sudo swapon -s

