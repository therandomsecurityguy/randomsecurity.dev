---
author: "dc"
date: 2014-06-25T16:03:24Z
description: ""
draft: false
slug: "openstack-juno"
tags: ["Openstack", "Juno", "CentOS 7"]
title: "Openstack Juno on Centos 7"

---



First, sorry for the delay in posting. I've been busy in rebuilding my lab (4 times) to accommodate parallel testing. In the meantime, I wanted to quickly share my experience with the latest Openstack release: Juno. As of this writing there is a repo available for Ubuntu but for this install I'm using [Centos 7](http://www.centos.org/download/) via [RDO](https://openstack.redhat.com/Quickstart) and the [Packstack installer](https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux_OpenStack_Platform/2/html/Getting_Started_Guide/part-Deploying_OS_using_PackStack.html). Why? Because it's freaking easy....aside from a few minor changes depending on the configuration you choose (single node, multi-node, vlan, vxlan, etc). So let's get started.

## CentOS is the New Pink


 Well...not really....but they've made a lot of progress is packaging Openstack for easy deployment. The [RDO Quickstart Packstack](https://openstack.redhat.com/Quickstart) installer uses puppet modules to deploy Openstack components. All you need is a server that meets the minimum requirements:

* Hardware: Machine with at least 2GB RAM, processors with hardware virtualization extensions, and at least one network adapter

* Software: Red Hat Enterprise Linux (RHEL) 6.5 is the minimum recommended version, or the equivalent version of one of the RHEL-based Linux distributions such as CentOS, Scientific Linux, etc., or Fedora 20 or later. x86_64 is currently the only supported architecture.

With that settled, let's move on to the dependencies...

## Software Repos

 First, update your current packages:

    sudo yum update -y

 Then set SELinux to permissive:

    vi /etc/selinux/config # SELINUX=enforcing SELINUX=permissive

 And reboot (to switch to the updated kernel and enforce the SELinux changes).

Next, install the EPEL (Extra Packages for Enterprise Linux) repo. This is needed to install most of the dependencies required for the packstack install (erlang, rabbitmq, etc):

    sudo yum install epel-release -y

 Now open the EPEL repo config file:

    sudo vi /etc/yum.repos.d/epel.repo

And ensure that the additional EPEL repos are enabled:   	

    [epel]enabled=1
    [epel-debuginfo] enabled=1
    [epel-source] enabled=1

 Finally, you can setup the [RDO repo](https://repos.fedorapeople.org/repos/openstack/):

    yum install https://repos.fedorapeople.org/repos/openstack/openstack-juno/rdo-release-juno-1.noarch.rpm

## Packstack Installer

 This is fairly straight forward and should take less than a minute:

    sudo yum install -y openstack-packstack

## Run Packstack

 As I've stated before, Packstack takes the work out of manually setting up OpenStack by using Puppet modules to deploy each Openstack component. For a single node OpenStack deployment, run the following command:

    packstack --allinone

If you are not root then installer will ask you to enter the root password for each host node you are installing on the network, to enable remote configuration of the host so it can remotely configure each node using Puppet. Also, if you wish to deploy a multi-node setup, look [here](https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux_OpenStack_Platform/2/html/Getting_Started_Guide/part-Deploying_OS_using_PackStack.html).

The setup will take some time, during which you should see manifest entries being added and the application of each Puppet module. Once completed, you should see something similar:

    Applying Puppet manifests 			[ DONE ]
    Finalizing 						   [ DONE ]  

    ****** Installation completed successfully ******

    Additional information: * A new answerfile was created in: /root/packstack-answers-20141025-004039.txt
    * Time synchronization installation was skipped. Please note that unsynchronized time on server instances might be problem for some OpenStack components.
    * File /root/keystonerc_admin has been created on OpenStack client host 10.10.1.102. To use the command line tools you need to source the file.
    * To access the OpenStack Dashboard browse to http://10.10.1.102/dashboard . Please, find your login credentials stored in the keystonerc_admin in your home directory.
    * To use Nagios, browse to http://10.10.1.102/nagios username: nagiosadmin, password: *************
    * The installation log file is available at: /var/tmp/packstack/20141025-004039-oF1wGH/openstack-setup.log
    * The generated manifests are available at: /var/tmp/packstack/20141025-004039-oF1wGH/manifests
    [root@controller ~]#

If you encounter any specific errors, first check and make sure the the EPEL repos above are **enabled**. If problems still persist, please visit the [Workarounds](https://openstack.redhat.com/Workarounds) page. Also, if you have run packstack previously, there will be a file in your home directory named something like packstack-answers-20141025-004039.txt You will probably want to use that file again, using the --answer-file option, so that any passwords you've already set (eg, mysql) will be reused.

## OpenvSwitch Updates

 Since this is a single NIC install, some changes will need to be made. I'm using **eno1** as my "public" interface, so the external OpenvSwitch (OVS) bridge should have a config file created and labeled with the correct matching physical interface. First, switch to the network-scripts directory:

    cd /etc/sysconfig/network-scripts

Create the external bridge configuration file:

    sudo vi ifcfg-br-ex

Add the following with your relevant, public-facing IP/mask/gateway information:

    DEVICE=br-ex
    ONBOOT=yes
    DEVICETYPE=ovs
    TYPE=OVSIntPort
    OVS_BRIDGE=br-ex
    USERCTL=no
    BOOTPROTO=none
    HOTPLUG=no
    IPADDR=x.x.x.x
    NETMASK=x.x.x.x
    GATEWAY=x.x.x.x
    DNS1=8.8.8.8

And change your physical public NIC's configuration (eno1 is my case):

    DEVICE=eno1
    ONBOOT=yes NETBOOT=yes
    IPV6INIT=no BOOTPROTO=none
    NAME=eno1 DEVICETYPE=ovs
    TYPE=OVSPort
    OVS_BRIDGE=br-ex

 Finally, restart your network daemon:

    sudo service network restart

## Neutron/ML2 Updates

 The last thing you'll need to do before you can get started is update the Neutron configuration in the Packstack answers file in your home directory:

    CONFIG_NEUTRON_ML2_TUNNEL_ID_RANGES=1001:2000 CONFIG_NEUTRON_ML2_VXLAN_GROUP=239.1.1.2 CONFIG_NEUTRON_ML2_VNI_RANGES=1001:2000 CONFIG_NEUTRON_OVS_BRIDGE_MAPPINGS=physnet1:br-ex CONFIG_NEUTRON_OVS_TUNNEL_RANGES=1001:2000
    CONFIG_NEUTRON_OVS_TUNNEL_IF=eno1

Re-run the Packstack installer with the answers file option:

    packstack --answer-file=packstack-answers-20141025-004039.txt

 Now you can create your Neutron networks, subnets, and allocation pools as normal. Your Horizon dashboard is reachable via http://$YOURIP/dashboard. Viola! You're done!

## Conclusion


With some minor modifications, the RDO Packstack installer is a very simple way of standing up an Openstack environment in a short amount of time. Although most of us have gotten used to using Ubuntu as a deployment OS, RHEL/CentOS is making a strong push for being the OS of choice due to ease of deployment. Now....onto Docker integration...
