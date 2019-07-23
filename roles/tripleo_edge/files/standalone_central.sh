#!/usr/bin/env bash

set -eu

PATH=$PATH:/usr/sbin:/sbin

export IP=`ip r get 1.1.1.1 | awk '/dev/{print $7}' | tr -d '[[:space:]]'`
export NETMASK=24
export DOMAIN=`dnsdomainname | tr -d '[[:space:]]'`
if [ -z $DOMAIN ]; then export DOMAIN=localdomain;fi

sudo openstack tripleo deploy \
  --templates \
  --local-ip=$IP/$NETMASK \
  -e /usr/share/openstack-tripleo-heat-templates/environments/standalone/standalone-tripleo.yaml \
  -r /usr/share/openstack-tripleo-heat-templates/roles/Standalone.yaml \
  -e $HOME/containers-prepare-parameters.yaml \
  -e $HOME/standalone_parameters.yaml \
  --output-dir $HOME --local-domain ${DOMAIN:-localdomain}  \
  --standalone --keep-running
