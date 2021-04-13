---
author: "dc"
date: 2014-08-19T14:19:00Z
description: ""
draft: false
slug: "openstack-ipv6"
tags: ["Openstack", "Icehouse", "IPv6"]
title: "Openstack with IPv6"

---



## Openstack....now with lots of addresses!

After being inspired to update my IPv6 experience in my [previous post](https://randomsecurity.dev/ipv6-sage/), I figured it was time to start enabling IPv6 within my Openstack lab environment. It's surprisingly easy as it's similar to many dual-stacked environments that support IPv4/IPv6 today. The following is a basic Openstack Icehouse single node install with a Single Flat Network (I'll explain shortly), dual-stacked topology. Sound good? Let's get started!

## Requirements


### Server

For this setup, I'm using a spare tower with a single NIC (you only need one for testing). I'm using the Single Flat Network topology as it is simple, yet effective with IPv6. Although Neutron L3 Routers are [not supported](https://blueprints.launchpad.net/neutron/+spec/neutron-ipv6-ra) as of yet, you can still have a succesful dual-stacked network. IPv6 Stateless Address Autoconfiguration ([SLAAC](http://en.wikipedia.org/wiki/IPv6#Stateless_address_autoconfiguration_.28SLAAC.29)) is not supported so each instance will have to have addresses statically assigned. At least IPv6 Security Groups work!

### Network

You have to have an IPv6 enabled network, plain and simple. Many ISP's are now providing some form of IPv6 capability (usually 6rd) to a residential modem (for home lab testing) or you could enable this in a closed lab. The other option was discussed in my [previous post](https:/randomsecurity.dev/ipv6-sage/) regarding setting up a tunnel broker service from [Hurricane Electric](https://ipv4.tunnelbroker.net/), [Gogonet](http://www.gogo6.com/freenet6/tunnelbroker), or several others out there. For now, I'll use the /60 given to me by my own ISP for testing.

### Components

So, aside from a vanilla Ubuntu 14.04 LTS install, we will be installing and configuring the following:

* Open vSwitch
* RabbitMQ
* MySQL
* Keystone
* Glance
* Nova
* Neutron (ML2 plugin)
* Cinder
* Horizon
* SPICE Console

This configuration does **not** have the following: - NAT (you have **18,446,744,073,709,551,615** IP's at your disposal, so forget about it)

* Neutron L3 virtual routers (not supported yet)
* VXLAN tunnels (again....not needed)
* Floating IP's (no NAT involved. We have real dual-stacked hosts!)

Ready? Let's begin!

### Controller Setup

From a brand new Ubuntu 14.04 install, log in as root and run the following:

    apt-get update
    apt-get dist-upgrade -y
    apt-get install openvswitch-switch -y

This will make sure you are running the latest kernel and install the ever so import Open vSwitch (for a good primer on Open vSwitch, check out [David Mahler's YouTube channel](https://www.youtube.com/watch?v=rYW7kQRyUvA&list=TLe-OWaOm_IN_yw-mKMhyoxLC8pzW0GBvU)) Make sure you have a hostname in /etc/hosts that includes your IPv6 IP mapped to your hostname. Here is an example of mine:

    127.0.0.1 localhost
    127.0.1.1 controller.derekchamorro.info controller

    # The following lines are desirable for IPv6 capable hosts  2002:306:837c:5670::5 controller.derekchamorro.info controller
    ::1 localhost ip6-localhost ip6-loopback
    ff02::1 ip6-allnodes
    ff02::2 ip6-allrouters

### Network configuration

You'll need to statically assign your IP addresses in use. Open your interfaces file:

    vim /etc/network/interfaces

And configure it with your respective IP address ranges. I've used the following (public side obfuscated for obvious reasons):

    # The loopback network interface
    auto lo iface lo inet loopback

    # The primary network interface - bridges to br-eth0
    auto eth0 iface eth0 inet manual
    up ip link set $IFACE up
    up ip address add 0.0.0.0 dev $IFACE
    down ip link set $IFACE down

    # br-eth0
    auto br-eth0
    iface br-eth0 inet static address 10.10.10.10
    netmask 24
    gateway 10.10.10.1
    # Google IPv4 DNS servers
    dns-nameservers 8.8.8.8 8.8.4.4

    # IPv6 eth0
    iface br-eth0 inet6 static
    address 2002:306:837c:5670::5
    netmask 64
    gateway 2002:306:837c:5670::1

    # Google IPv6 DNS servers
    dns-nameservers 2001:4860:4860::8844 2001:4860:4860::8888

Once your interfaces file is complete, you'll need to enable IPv4/v6 packet forwarding:  

    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
    sysctl -p

With networking completed, let's create our OVS bridges:

    ovs-vsctl add-br br-int
    ovs-vsctl add-br br-eth0

Finally, you'll bridge your eth0 and new bridge interface. Running the following will kick you out of the server if you are managing it via eth0 (which you probably are) so hence we reboot after:

    ovs-vsctl add-port br-eth0 eth0 && reboot

Also, you'll probably see the following message upon reboot:

    “Waiting for network configuration”

To fix this edit the following file as root:

    vim /etc/init/failsafe.conf

Change the first sleep command to:

    sleep 5

And comment out the following lines:

    $PLYMOUTH message --text="Waiting for network configuration..." || :
    sleep 40
    $PLYMOUTH message --text="Waiting up to 60 more seconds for network configuration..." || :
    sleep 59

## Install Openstack dependencies

Install the following:

    apt-get install mysql-server python-mysqldb openssl rabbitmq-server python-keyring ntp curl -y

Change the default **guest** account password in RabbitMQ

    rabbitmqctl change_password guest yournewpassword

### MySQL configuration

You'll need to make some modifications to the my.cnf file. Edit my.cnf:

    vim /etc/mysql/my.cnf

And add the following under [mysqld]:

    [mysqld]
    #
    # * Support OpenStack utf8 encoding
    #
    default-storage-engine = innodb
    collation-server = utf8_general_ci
    init-connect='SET NAMES utf8'
    character-set-server = utf8 innodb_file_per_table

And change the bind address from 127.0.0.1 to the following:

    bind-address = ::

Save the file and restart MySQL:

    service mysql restart

Now initialize the MySQL data directory:

    mysql_install_db

And secure the installation:

    mysql_secure_installation

Now we can make the required databases:

    mysql -u root -p

Once at the MySQL prompt, create the databases as documented [here](http://docs.openstack.org/icehouse/install-guide/install/apt/content/basics-database-controller.html):

    CREATE DATABASE keystone;
    GRANT ALL ON keystone.* TO 'keystoneUser'@'%' IDENTIFIED BY 'keystonePass';
    CREATE DATABASE glance;
    GRANT ALL ON glance.* TO 'glanceUser'@'%' IDENTIFIED BY 'glancePass';
    CREATE DATABASE nova;
    GRANT ALL ON nova.* TO 'novaUser'@'%' IDENTIFIED BY 'novaPass';
    CREATE DATABASE cinder;
    GRANT ALL ON cinder.* TO 'cinderUser'@'%' IDENTIFIED BY 'cinderPass';
    CREATE DATABASE neutron;
    GRANT ALL ON neutron.* TO 'neutronUser'@'%' IDENTIFIED BY 'neutronPass';
    CREATE DATABASE heat;
    GRANT ALL ON heat.* TO 'heatUser'@'%' IDENTIFIED BY 'heatPass';
    quit;


Use your own users and passwords if you want, just remember what they were :)

 ### Keystone

Self explanatory from the [Keystone install page](http://docs.openstack.org/icehouse/install-guide/install/apt/content/keystone-install.html):

    apt-get install keystone -y

Update the keystone configuration file:

    vim /etc/keystone/keystone.conf

Uncomment this line:

    #admin_token=ADMIN

Add this line (with your controller IPv6 address):

    bind_host = 2002:306:837c:5670::5

Find this line:

    connection = sqlite:////var/lib/keystone/keystone.db

And replace it with your FDQN info:

    connection = mysql://keystoneUser:keystonePass@controller.putyourowndomainhere.com/keystone

Remember...if you changed any of the default passwords to make the proper changes. After than, run the following:

    rm /var/lib/keystone/keystone.db
    su -s /bin/sh -c "keystone-manage db_sync" keystone
    service keystone restart

### Populate Keystone Data

Once you've restarted keystone, you have to bootstrap keystone database with an admin user account and set the API endpoints. You can use the script found [here](https://github.com/openstack/keystone/blob/master/tools/sample_data.sh) or use the ones I've forked:

    cd ~
    wget https://gist.githubusercontent.com/therandomsecurityguy/c984a87f33114968aa63/raw/96fa7db48d6d04a784250d11784de92bbaf5233c/keystone_data.sh
    wget https://gist.githubusercontent.com/therandomsecurityguy/a0a5e18308df54dbe841/raw/63597a0c9abbc69b2c99c51559e96f3a52dde903keystone_endpoint_data.sh

    vim keystone_data.sh

    ## Modify following line:
    HOST_IP=controller.putyourowndomainhere.com

    vim keystone_sample_data.sh

    ## Modify following line:
    HOST_IP=controller.putyourowndomainhere.com

    chmod +x keystone_data.sh
    chmod +x keystone_sample_data.sh

    ./keystone_data.sh
    ./keystone_endpoint_data.sh

 ** Remember if you change any of the default passwords, please make the respective modifications in the script.

Run curl to test the keystone install:

    curl http://controller.putyourowndomainhere.com:35357/v2.0/endpoints -H 'x-auth-token: ADMIN' | python -m json.tool


Run the following to delete expired tokens, since they are kept in your database indefinitely:

    (crontab -l 2>&1 | grep -q token_flush) || echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' >> /var/spool/cron/crontabs/root

Last steps for this are to create your Nova Resource Configuration (RC) file:

    vim ~/.novarc

And add the following:

    export SERVICE_TOKEN=ADMIN
    export OS_USERNAME=admin
    export OS_PASSWORD=admin_pass
    export OS_TENANT_NAME=admin
    export OS_AUTH_URL="http://controller.putyourowndomainhere.com:5000/v2.0/"
    export SERVICE_ENDPOINT="http://controller.putyourowndomainhere.com:35357/v2.0/"
    export OS_AUTH_STRATEGY=keystone
    export OS_NO_CACHE=1
    export NOVA_USERNAME=${OS_USERNAME}
    export NOVA_PROJECT_ID=${OS_TENANT_NAME}
    export NOVA_PASSWORD=${OS_PASSWORD}
    export NOVA_API_KEY=${OS_PASSWORD}
    export NOVA_URL=${OS_AUTH_URL}
    export NOVA_VERSION=1.1
    export NOVA_REGION_NAME=RegionOne

Append to your bashrc file:

    vim ~/.bashrc

With:

    if [ -f ~/.novarc ]; then . ~/.novarc fi

Load it:

    source ~/.bashrc

And finally...test Keystone with a basic list function:

    root@controller:~# keystone tenant-list

    +----------------------------------+---------+---------+
    |                id                |   name  | enabled |
    +----------------------------------+---------+---------+
    | 5d356e2c4f144f6fb397491150d74483 |  admin  |   True  |
    | 6683b0739df04093aebf1616ca8b9b18 | service |   True  |
    +----------------------------------+---------+---------+

### Glance

Installing Glance is easy, just use the [Glance install page](http://docs.openstack.org/icehouse/install-guide/install/apt/content/glance-install.html).

First, run the following:

    apt-get install glance python-mysqldb -y

Edit the Glance API configuration:

    vim /etc/glance/glance-api.conf

With your controller information:

    [DEFAULT]
    bind_host = 2002:306:837c:5670::5

    registry_host = controller.putyourowndomainhere.com  

    rabbit_host = controller.putyourowndomainhere.com

    [database]
    connection =    mysql://glanceUser:glancePass@controller.putyourowndomainhere.com/glance

    [keystone_authtoken]
    auth_uri = http://controller.putyourowndomainhere.com:5000  
    auth_host = controller.putyourowndomainhere.com
    auth_port = 35357
    auth_protocol = http
    admin_tenant_name = service
    admin_user = glance
    admin_password = service_pass

    [paste_deploy]
    flavor = keystone

Now to the same editing to the Glance registry configuration:

    vim /etc/glance/glance-registry.conf

With:

    [DEFAULT]
    bind_host = 2002:306:837c:5670::5
    [database]
    connection = mysql://glanceUser:glancePass@controller.putyourowndomainhere.com/glance
    [keystone_authtoken]
    auth_uri = http://controller.putyourowndomainhere.com:5000
    auth_host = controller.putyourowndomainhere.com
    auth_port = 35357
    auth_protocol = http
    admin_tenant_name = service
    admin_user = glance
    admin_password = service_pass

    [paste_deploy]
    flavor = keystone

Then run the following to remove the sqlite config (if it exists) and sync the db:

    rm /var/lib/glance/glance.sqlite su -s /bin/sh -c "glance-manage db_sync" glance
    service glance-api restart; service glance-registry restart

#### Add Images to Glance

Run the following to add images (in this case CirrOS and Ubuntu 64-bit) to the Glance repo:

    glance image-create --location http://download.cirros-cloud.net/0.3.2/cirros-0.3.2-x86_64-disk.img --name "CirrOS 0.3.2" --is-public true --container-format bare --disk-format qcow2
    glance image-create --location http://uec-images.ubuntu.com/releases/14.04/release/ubuntu-14.04-server-cloudimg-amd64-disk1.img --name "Ubuntu 14.04 LTS" --is-public true --container-format bare --disk-format qcow2

You can use any image you want. If you already have an ISO then you'll have to create an .img file. Use the following [link](http://docs.openstack.org/image-guide/content/centos-image.html) for the step by step process.

Once completed, list your images to verify:

    root@controller:~# glance image-list
    +--------------------------------------+------------------+--  
    -----------+------------------+-----------+--------+
    | ID                                   | Name             |   
    Disk Format | Container Format | Size      | Status |
    +--------------------------------------+------------------+--  
    -----------+------------------+-----------+--------+
    | 0318f977-6319-4461-943d-99a90e9272bc | CirrOS 0.3.2     |  
    qcow2       | bare             | 13167616  | active |
    | 578a47ea-29e1-48c4-8647-c0b6a4afe22b | Ubuntu 14.04 LTS |
    qcow2       | bare             | 255132160 | active |
    +--------------------------------------+------------------+--  
    -----------+------------------+-----------+--------+

### Nova

Most most of this is taken from the [Nova install page](http://docs.openstack.org/icehouse/install-guide/install/apt/content/nova-controller.html). Since this is a single machine install (controller, compute and service nodes into one), I'm installing the libvirt dependencies as well as the other nova components. 

First, run the following:

    apt-get install python-novaclient nova-api nova-cert nova-consoleauth nova-scheduler nova-conductor nova-spiceproxy linux-image-extra-`uname -r` ubuntu-virt-server libvirt-bin pm-utils nova-compute-kvm python-guestfs -y

If you are using a separate physical host as a compute node, then only run the following on that host (as well as update your /etc/hosts file with the proper host entries):

    apt-get install linux-image-extra-`uname -r` ubuntu-virt-server libvirt-bin pm-utils nova-compute-kvm python-guestfs -y

Make the current kernel readable and destroy the libvirt default networks:

    dpkg-statoverride --update --add root root 0644 /boot/vmlinuz-$(uname -r)

    virsh net-destroy default
    virsh net-undefine default
    service libvirtd restart

Make sure the vhost_net module loads during boot:

    echo vhost_net>> /etc/modules

Add the following libvirt configurations:

    sed -i 's/^#listen_tls = 0/listen_tls = 0/' /etc/libvirt/libvirtd.conf
    sed -i 's/^#listen_tcp = 1/listen_tcp = 1/' /etc/libvirt/libvirtd.conf
    sed -i 's/^#auth_tcp = "sasl"/auth_tcp = "none"/' /etc/libvirt/libvirtd.conf
    sed -i 's/^env libvirtd_opts="-d"/env libvirtd_opts="-d -l"/' /etc/init/libvirt-bin.conf
    sed -i 's/^libvirtd_opts="-d"/libvirtd_opts="-d -l"/' /etc/default/libvirt-bin

Download a custom nova.conf file:

    cd /etc/nova mv nova.conf /nova.conf.bak

    wget     https://gist.githubusercontent.com/therandomsecurityguy/a7ca930d74991484aad2/raw/43f9b2cad6e899bd43f9341e059d2846125493d7/nova.conf

Modify the nova.conf with your own host information, then change ownership:

    chown nova: nova.conf
    chmod 640 nova.conf

Remove the sqlite library and sync the nova db:

    rm /var/lib/nova/nova.sqlite
    su -s /bin/sh -c "nova-manage db sync" nova

Finally restart nova services:

    cd /etc/init/; for i in $(ls nova-* | cut -d \. -f 1 | xargs); do sudo service $i restart; done

### Neutron

First, install the following:

    apt-get install neutron-server neutron-plugin-ml2 neutron-plugin-openvswitch-agent neutron-dhcp-agent neutron-metadata-agent -y

Next, get your "SERVICE TENANT ID" with the following command:

    root@controller:~# keystone tenant-get service
    +-------------+----------------------------------+
    |   Property  |              Value               |
    +-------------+----------------------------------+
    | description |                                  |
    |   enabled   |               True               |
    |      id     | e1c66cceefe543919c19b8e5533966c7 |
    |     name    |             service              |
    +-------------+----------------------------------+

Next edit the neutron configuration file:

    vim /etc/neutron/neutron.conf

And edit the following fields:

    [DEFAULT]
    bind_host = put your IPv6 address here
    auth_strategy = keystone
    allow_overlapping_ips = True
    rabbit_host = controller.putyourowndomainhere.com     
    notify_nova_on_port_status_changes = True
    notify_nova_on_port_data_changes = True
    nova_url = http://controller.putyourowndomainhere.com:8774/v2
    nova_region_name = RegionOne
    nova_admin_username = nova
    nova_admin_tenant_id = put your SERVICE TENANT ID here
    nova_admin_password = service_pass
    nova_admin_auth_url = http://controller.putyourowndomainhere.com:35357/v2.0

    core_plugin = neutron.plugins.ml2.plugin.Ml2Plugin

    service_plugins = neutron.services.l3_router.l3_router_plugin.L3RouterPlugin

    [keystone_authtoken]
    auth_uri = http://controller.putyourowndomainhere.com:5000  
    auth_host = controller.putyourowndomainhere.com
    auth_port = 35357
    auth_protocol = http
    admin_tenant_name = service
    admin_user = neutron
    admin_password = service_pass
    signing_dir = $state_path/keystone-signing

    [database]
    connection = mysql://neutronUser:neutronPass@controller.putyourowndomainhere.com/neutron

Now edit the [ML2 plugin](https://wiki.openstack.org/wiki/Neutron/ML2) ini file:

    vim /etc/neutron/plugins/ml2/ml2_conf.ini

With the following:

    [ml2]
    type_drivers = local,flat
    mechanism_drivers = openvswitch,l2population

    [ml2_type_flat]
    flat_networks = *

    [securitygroup]
    enable_security_group = True
    firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

    [ovs]
    enable_tunneling = False
    local_ip = insert your IPv4 address here
    network_vlan_ranges = physnet1 bridge_mappings = physnet1:br-eth0

Now edit the metadata agent INI file:

    vim /etc/neutron/metadata_agent.ini

With:

    # The Neutron user information for accessing the Neutron API.     
    auth_url = http://controller.putyourowndomainhere.com:5000/v2.0
    auth_region = RegionOne
    admin_tenant_name = service
    admin_user = neutron
    admin_password = service_pass
    nova_metadata_ip = your IPv4 address
    nova_metadata_port = 8775
    metadata_proxy_shared_secret = secretPass

Ok....almost there. Now edit the DHCP INI file:

    vim /etc/neutron/dhcp_agent.ini

And add the following:

    interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
    use_namespaces = True
    enable_isolated_metadata = True
    dhcp_domain = putyourowndomainhere.com

Finally, do a neutron service restart and you're done with neutron:

    cd /etc/init/; for i in $(ls -1 neutron-* | cut -d \. -f 1); do sudo service $i restart; done

#### Creating a Neutron Network

Although this is a flat topology using a single IPv4 and IPv6 subnet, it is easy to add additional subnets. I was just too lazy to add another vlan to my trunk :) You'll create two Neutron networks, one for each inet family (IPv4 and IPv6). You'll use the subnets defined in your network configuration file. I'm giving you the example of my home lab network. The IPv4 address space has public access outbound (via SNAT). For other types of configuration, use the Neutron/ML2 link[ here](http://docs.openstack.org/icehouse/install-guide/install/apt/content/section_neutron-networking-ml2.html). So first, create a physical "mapping":

    neutron net-create --tenant-id $ADMIN_TENTANT_ID ext-netaccess --shared --provider:network_type flat --provider:physical_network physnet1

Next create an IPv4 subnet for the "ext-netaccess":

    neutron subnet-create --ip-version 4 --tenant-id $ADMIN_TENANT_ID ext-netaccess 10.10.10.0/24 --allocation-pool start=10.10.10.128,end=10.10.10.254 --dns_nameservers list=true 8.8.4.4 8.8.8.8

And then create an IPv6 subnet for the "ext-netaccess":

    neutron subnet-create --ip-version 6 --disable-dhcp --tenant-id $ADMIN_TENANT_ID ext-netaccess 2002:306:837c:5670::/64 --allocation-pool start=2002:306:837c:5670::6,end=2002:306:837c:5670:ffff:ffff:ffff:fffe

### Cinder

Install the Cinder components as listed in the [Cinder install page](http://docs.openstack.org/icehouse/install-guide/install/apt/content/ch_cinder.html):

    apt-get install cinder-api cinder-scheduler -y

Edit the cinder.conf file:

    vim /etc/cinder/cinder.conf

With your own IP and host information:

    [DEFAULT]
    my_ip = 2002:306:837c:5670::5
    glance_host = 2002:306:837c:5670::5
    osapi_volume_listen = 2002:306:837c:5670::5

    rpc_backend = cinder.openstack.common.rpc.impl_kombu
    rabbit_host = controller.putyourowndomainhere.com

    connection = mysql://cinderUser:cinderPass@controller.putyourowndomainhere.com/cinder

    [keystone_authtoken]
    auth_uri = http://controller.putyourowndomainhere.com:5000
    auth_host = controller.putyourowndomainhere.com
    auth_port = 35357
    auth_protocol = http admin_tenant_name =
    service admin_user = cinder
    admin_password = service_pass

If you've configured a separate LVN volume for block storage, then follow this [link](http://docs.openstack.org/icehouse/install-guide/install/apt/content/cinder-node.html) to create the Cinder LVM grouping.

### Horizon

Last, but not least, install the Horizon dashboard:

    apt-get install openstack-dashboard memcached -y

Just edit the dashboard config file:

    vim /etc/openstack-dashboard/local_settings.py

With your host information:

    OPENSTACK_HOST = "controller.putyourowndomainhere.com"

And you're done. You should be able to reach your Horizon dashboard now.

### Building Your First Instance

Ok...let's make an instance. First, list your current images and get an image ID:

```
root@controller:~# glance image-list +--------------------------------------+-------------------------+-------------+------------------+-----------+--------+ | ID | Name | Disk Format | Container Format | Size | Status | +--------------------------------------+-------------------------+-------------+------------------+-----------+--------+ | 0318f977-6319-4461-943d-99a90e9272bc | CirrOS 0.3.2 | qcow2 | bare | 13167616 | active | | 578a47ea-29e1-48c4-8647-c0b6a4afe22b | Ubuntu 14.04 LTS | qcow2 | bare | 255132160 | active | | 04988647-8634-46f3-aa06-11290b24d8d8 | Ubuntu 14.04 LTS 32-bit | qcow2 | bare | 250872320 | active | +--------------------------------------+-------------------------+-------------+------------------+-----------+--------+
```

I'm using the Ubuntu 14.04 LTS 32-bit image (04988647-8634-46f3-aa06-11290b24d8d8). Remember, **your** image ID's will be unique. Now we'll pick a flavor:

```
root@stackiswhack:~# nova flavor-list +----+-----------+-----------+------+-----------+------+-------+-------------+-----------+ | ID | Name | Memory_MB | Disk | Ephemeral | Swap | VCPUs | RXTX_Factor | Is_Public | +----+-----------+-----------+------+-----------+------+-------+-------------+-----------+ | 1 | m1.micro | 256 | 5 | 0 | 128 | 1 | 1.0 | True | | 2 | m1.tiny | 512 | 10 | 25 | 256 | 1 | 1.0 | True | | 3 | m1.small | 1024 | 10 | 50 | 512 | 1 | 1.0 | True | | 4 | m1.medium | 2048 | 10 | 100 | 1024 | 2 | 1.0 | True | | 5 | m1.large | 4096 | 10 | 200 | 2048 | 4 | 1.0 | True | | 6 | m1.xlarge | 8192 | 10 | 400 | 4096 | 8 | 1.0 | True | +----+-----------+-----------+------+-----------+------+-------+-------------+-----------+
```

I'll use a micro image (ID 1). Now let's build:

    nova boot --image 04988647-8634-46f3-aa06-11290b24d8d8 --key-name dc_key --flavor 1 ubuntu32

This may take some time as it pulls the image and builds your instance. Once completed run the following to get your instance's information:

```
root@controller:~# nova list +--------------------------------------+----------+---------+------------+-------------+---------------------------------------------------+ | ID | Name | Status | Task State | Power State | Networks | +--------------------------------------+----------+---------+------------+-------------+---------------------------------------------------+ | 0e30631e-6700-4c45-84c8-935dc30b75c1 | ubuntu32 | ACTIVE | - | Running | ext-netaccess=2002:306:837c:5670::6, 10.10.10.128 | +--------------------------------------+----------+---------+------------+-------------+---------------------------------------------------+
```

The IPv4 address has been assigned and configured for your host. The IPv6 address has been assigned but not configured, so we have to do it manually:

    ssh -i dc_key.pem ubuntu@10.10.10.128
    sudo ip -6 address add 2002:306:837c:5670::6/64 dev eth0
    sudo ip -6 route add default via 2002:306:837c:5670::1

And we're done!

## Conclusion

This is a standard single node build for Openstack Icehouse that supports dual-stack IPv6. Mind you, this is only built for lab purposes and testing, but I did it because most of the guides did not show a complete single node build or show how to enable v6. I hope this helps you in your testing. And now...on to Openstack flow analysis. Cheers!
