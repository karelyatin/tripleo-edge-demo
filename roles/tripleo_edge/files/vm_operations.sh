export OS_CLOUD=standalone

# nova flavor
openstack flavor create --ram 512 --disk 1 --vcpu 1 --public tiny
# basic cirros image
curl -O https://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
openstack image create cirros --container-format bare --disk-format qcow2 --public --file cirros-0.4.0-x86_64-disk.img
# nova keypair for ssh
test -f ~/.ssh/id_rsa.pub || ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
openstack keypair create --public-key ~/.ssh/id_rsa.pub default

# create basic security group to allow ssh/ping/dns
openstack security group create basic
# allow ssh
openstack security group rule create basic --protocol tcp --dst-port 22:22 --remote-ip 0.0.0.0/0
# allow ping
openstack security group rule create --protocol icmp basic
# allow DNS
openstack security group rule create --protocol udp --dst-port 53:53 basic

neutron net-create public --router:external --provider:network_type flat --provider:physical_network datacentre

export GATEWAY=`ip r get 1.1.1.1 | awk '/dev/{print $3}' | tr -d '[[:space:]]'`
export CIDR=`ip r|grep br-ctlplane|cut -d" " -f1|tail -1| tr -d '[[:space:]]'`
neutron subnet-create --name public --enable_dhcp=False --allocation-pool=start=${GATEWAY%.*}.220,end=${GATEWAY%.*}.225 --gateway=$GATEWAY public $CIDR

openstack network create net1
openstack subnet create subnet1 --network net1 --subnet-range 192.0.2.0/24
neutron router-create router1
neutron router-gateway-set router1 public
neutron router-interface-add router1 subnet1
neutron floatingip-create public
netid=$(openstack network show net1 -f value -c id)
floatip=$(openstack floating ip list -f value -c "Floating IP Address"|head -1)
openstack server create --nic net-id=$netid --image cirros --security-group basic --key-name default --flavor tiny testvm
sleep 20
openstack server add floating ip testvm $floatip

# VM is ready and can be accessed with ssh cirros@$floatip
