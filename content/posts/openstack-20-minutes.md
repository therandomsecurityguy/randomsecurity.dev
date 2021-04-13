---
author: "dc"
date: 2014-02-28T14:58:56Z
description: ""
draft: false
slug: "openstack-20-minutes"
tags: ["Openstack", "Devstack", "Icehouse"]
title: "Openstack in 20 minutes"

---



Openstack for the lazy
----------------------

If you are like me, you do a lot of testing.  I have built and rebuilt Openstack single (all in one) and multi-node installations hundreds of times. With [Devstack](http://devstack.org/ "Devstack"), you have the ability of creating an Openstack single node instance within minutes. While the default settings should suffice for most, I'll add some additional details that may help with all of the testing you wish to accomplish.

### The 'server'

It's best to start with a dedicated system (laptop, desktop, or server) but this can be accomplished with a virtual machine ([KVM](http://www.linux-kvm.org/page/Main_Page), [VirtualBox](https://www.virtualbox.org/), [VMFusion](http://www.vmware.com/products/fusion), etc). If going with a virtual machine, provision your server with at least 1GB of memory 4GB of virtual hard drive space and 1 CPU core. Install [Ubuntu](http://www.ubuntu.com/) (12.04 LTS or 14.04 LTS). The step by step is fairly easy and shouldn't take more than a few minutes. The default user account will be setup with sudo access.

### Download/install dependencies and Devstack

Create an Openstack user account and install Git:  

    sudo su -
    adduser stack
    echo "stack ALL=(ALL) NOPASSWD: ALL" » /etc/sudoers
    exit
    su stack
    sudo apt-get install git -y
    git clone https://github.com/openstack-dev/devstack.git
    cd devstack

### Openstack user account

Devstack will complain if you try to run it as root, so if you didn't create a user account 'stack' it will prompt you to create one:

    $ sudo ./stack.sh You are running this script as root. Cut it out. Really. If you need an account to run DevStack, do this (as root, heh) to create stack: /opt/devstack/tools/create-stack-user.sh

### Create a configuration file for Devstack

Although you can run the Devstack install script with the default parameters, I'd recommend creating a local configuration file to determine a few components. Those familiar with Openstack will know that each service requires a specific configuration file (Keystone, Cinder, etc). You can create a master file that Devstack uses to build all of the configuration files for you called local.conf. Here is a sample:

    [[local|localrc]]
    FLOATING_RANGE=192.168.1.144/28
    FIXED_RANGE=10.0.1.0/24
    FIXED_NETWORK_SIZE=256
    FLAT_INTERFACE=eth0 LOGFILE=/opt/devstack/stack.sh.log
    Q_FLOATING_ALLOCATION_POOL=start=192.168.1.150,end=192.168.1.155 PUBLIC_NETWORK_GATEWAY=192.168.1.254 ADMIN_PASSWORD=mydevstackpassword MYSQL_PASSWORD=mydevstackpassword RABBIT_PASSWORD=mydevstackpassword SERVICE_PASSWORD=mydevstackpassword SERVICE_TOKEN=mydevstackpassword
    disable_service rabbit
    enable_service qpid
    enable_service quantum
    enable_service n-cpu
    enable_service n-cond
    disable_service n-net
    enable_service q-svc
    enable_service q-dhcp
    enable_service q-l3
    enable_service q-meta
    enable_service quantum
    enable_service tempest

Here is what each one means:

- FLOATING_RANGE - A range of IP's not in use on your local network. In the example above I use 192.168.1.0/25 for various machines and have reserved the upper block for testing.
- FIXED_RANGE - This is the internal range that VM's pull from. If you keep this value the same across multiple deployments then you can leverage overlay technologies such as [VXLAN](https://randomsecurity.dev/vxlan/ "VXLAN").
- FIXED_NETWORK_SIZE - The maximum amount of hosts allowed within the FIXED_RANGE.
- FLAT_INTERFACE - Indicates the network interface card that devstack will use for network access. I assume you are using eth0 but it depends on your environment.
- LOGFILE - Self explanatory.
- Q_FLOATING_ALLOCATION_POOL - This value lets you explicitly set the pool of IPs used for this Devstack instance.
- PUBLIC_NETWORK_GATEWAY - Self explanatory

Most of the services listed will be enabled but this also ensures you are using Neutron networking and keeping Nova networking (deprecated) disabled. I'll give more examples in future blog posts regarding OVS and ML2.

### Optional - enable Icehouse branch

Use the following to checkout the latest Openstack branch - Icehouse:

    git checkout stable/icehouse

### Setup physical host network environment

The following commands will ensure network traffic will be correctly routed in and out of the Devstack VMs:

    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo 1 > /proc/sys/net/ipv4/conf/eth0/proxy_arp
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

The ip_forward and proxy_arp changes will be reset when the machice reboots. You can make these changes permanent by editing /etc/sysctl.conf and adding the following lines:

    net.ipv4.conf.eth0.proxy_arp = 1 net.ipv4.ip_forward = 1

### Run ./stack.sh and grab some popcorn

No really....grab some popcorn. The stack script will install MySQL, RabbitMQ, additional binaries and dependencies. This can take anywhere from 10-20 minutes. Once completed, point your browser to http://hostip and log in with the admin credentials listed above.

### Upload image

Once logged in, you'll need some images to start. On the dashboard -> go to Admin Tab → Images → Create Image. Name the image whatever you want and set the location to where ever your image is located. You can use the following to get you started:

[CirrOS 0.3.2](http://download.cirros-cloud.net/0.3.2/cirros-0.3.2-x86_64-disk.img)

[Ubuntu Precise](http://uec-images.ubuntu.com/precise/current/precise-server-cloudimg-amd64-disk1.img)

Set the image format to QCOW2, and click ‘Create Image’. Devstack will pull the image, convert it and make it available for VM use. Wash, rinse and repeat

When you are done, run the following commands to shutdown, clean up files (if you want to start from scratch, and to rejoin after a reboot:

Shutdown devstack: `./unstack.sh`

Remove files that Devstack installed: `./clean.sh`

Rejoin Devstack after reboot: `./rejoin-stack.sh`

Conclusion
----------

Devstack is a simple, yet powerful way of testing Openstack and various SDN components. With minimal resources, and defined configuration files, one can setup a virtual environment for testing without the hassle of breaking production equipment. Until next time...
