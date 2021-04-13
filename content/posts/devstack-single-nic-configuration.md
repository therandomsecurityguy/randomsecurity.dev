---
author: "dc"
date: 2014-03-28T22:21:21Z
description: ""
draft: false
slug: "devstack-single-nic-configuration"
tags: ["Openstack", "Devstack", "Single NIC", "How It Works"]
title: "Devstack single NIC configuration"

---



I made a [post](http://randomsecurity.dev/openstack-20-minutes/ "Openstack in 20 minutes") recently on setting up Openstack for development using [Devstack](http://devstack.org/) but failed to mention some other tips on how to build a lab out of anything. I'm a big fan of the [Gigabyte Brix ](http://www.gigabyte.us/products/product-page.aspx?pid=5038#ov)PC kit systems, with the caveat being that they only have a single NIC. You could connect a wireless USB adapter but there is a much easier way to have multiple networks....

### Old fashioned bridging....the joy

Yes....bridging and VLANS still work...and fairly well within a Linux system. First install the dependencies:

    sudo apt-get install bridge-utils

Configure a bridge interface in /etc/network/interfaces with some extra parameters:

    # Bridge interface
    auto br0
    iface br0 inet
    static address 192.168.1.145 # Reserve this IP from your DHCP server
    netmask 255.255.255.0
    broadcast 192.168.0.255
    gateway 192.168.1.1 # Use your local network gateway
    dns-nameserver 8.8.8.8 8.8.4.4
    bridge_ports eth0
    bridge_fd 0
    bridge_hello 2
    bridge_maxage 12
    bridge_stp off

Restart networking:
    sudo service networking restart

Create a VLAN network interface on eth0 using VLAN ID 0 (10.0.0.1 is used as an IP example):

    modprobe 8021q
    vconfig add eth0 5
    ifconfig eth0.0:5 10.0.0.1 netmask 255.255.255.0 up

Ensure you have ip forwarding, proxy ARP and a NAT rule enabled:

    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo 1 > /proc/sys/net/ipv4/conf/eth0/proxy_arp
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

Let's make it permanent in /etc/network/interfaces:  

    auto eth0.5
    iface eth0.5 inet static
    address 10.0.0.1 netmask 255.255.255.0
    vlan-raw-device eth0

Now modify your Devstack local.conf file to include your new VLAN interface and range:

    HOST_IP=192.168.1.145
    FLOATING_RANGE=192.168.1.144/28
    Q_FLOATING_ALLOCATION_POOL=start=192.168.1.150,end=192.168.1.155  PUBLIC_NETWORK_GATEWAY=192.168.1.254
    FIXED_RANGE=10.0.0.0/24
    FIXED_NETWORK_SIZE=256 FLAT_INTERFACE=eth0

Follow the rest of the [instructions](http://randomsecurity.dev/openstack-20-minutes/) and you'll be stacking in no time. Until next time....cheers.
