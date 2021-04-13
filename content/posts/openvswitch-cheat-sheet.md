---
author: "dc"
date: 2015-12-28T06:39:29Z
description: "Open vSwitch troubleshooting commands."
draft: false
slug: "openvswitch-cheat-sheet"
tags: ["Openstack", "OpenvSwitch", "SDN"]
title: "Open vSwitch Cheat Sheet"

---


Before I begin, for those unfamiliar with [Open vSwitch](http://openvswitch.org), please check out my friend David Mahler's YouTube [page](https://www.youtube.com/user/mahler711) for comprehensive introductory videos.

Over the past year I've spent some time compiling  troubleshooting documents and procedures for all things cloud (OpenStack, SDN, Open vSwitch, etc). I wanted to make a series on 'cheat sheets', or common day to day configuration/troubleshooting commands and techniques for different cloud components.

First on the list is Open vSwitch (aka OVS), which has become an integral part of OpenStack networking. It provides the ability to replicate many of the features of a traditional layer 2 switch, while providing advanced features that allow organizations to scale their cloud environments quickly.

Let's get started!

### Base commands

OVS is feature rich with different configuration commands, but the majority of your configuration and troubleshooting can be accomplished with the following 4 commands:

* ovs-vsctl : Used for configuring the ovs-vswitchd configuration database (known as ovs-db)
* ovs-ofctl : A command  line  tool  for monitoring and administering OpenFlow switches
* ovs-dpctl : Used to administer Open vSwitch datapaths
* ovs−appctl : Used for querying and controlling Open vSwitch daemons

#### ovs-vsctl

This tool is used for configuration and viewing OVS switch operations. Port configuration, bridge additions/deletions, bonding, and VLAN tagging are just some of the options that are available with this command.

Below are the most useful 'show' commands:

`ovs-vsctl –V` : Prints the current version of openvswitch.<br>
`ovs-vsctl show` : Prints a brief overview of the switch database configuration.<br>
`ovs-vsctl list-br` : Prints a list of configured bridges<br>
`ovs-vsctl list-ports <bridge>` : Prints a list of ports on a specific bridge.<br>
`ovs-vsctl list interface` : Prints a list of interfaces.<br>

The above should be fairly self explanatory. Below are the common switch configuration commands:

`ovs-vsctl add-br <bridge>` : Creates a bridge in the switch database.<br>
`ovs-vsctl add-port <bridge> <interface>` : Binds an interface (physical or virtual) to a bridge.<br>
`ovs-vsctl add-port <bridge> <interface> tag=<VLAN number>` : Converts port to an access port on specified VLAN (by default all OVS ports are VLAN trunks).<br>
`ovs-vsctl set interface <interface> type=patch options:peer=<interface>` : Used to create patch ports to connect two or more bridges together.<br>

The first 3 commands above are fairly standard, so why did I include the last one? This is a configuration I've been using for traffic interception when connecting one bridge to another. I'll explain in more in detail in a future post :)

#### ovs-ofctl

This tool is used for administering and monitoring [OpenFlow](http://en.wikipedia.org/wiki/OpenFlow) switches. Even if OVS isn't configured for centralized administration, ovs-ofctl can be used to show the current state of OVS including features, configuration, and table entries.

Below are common show commands:

`ovs-ofctl show <bridge>` : Shows OpenFlow features and port descriptions.<br>
`ovs-ofctl snoop <bridge>` : Snoops traffic to and from the bridge and prints to console.<br>
`ovs-ofctl dump-flows <bridge> <flow>` : Prints flow entries of specified bridge. With the flow specified, only the matching flow will be printed to console. If the flow  is omitted, all flow entries of the bridge will be printed. <br>
`ovs-ofctl dump-ports-desc <bridge>` : Prints port statistics. This will show detailed information about interfaces in this bridge, include the state, peer, and speed information. *Very useful*<br>
`ovs-ofctl dump-tables-desc <bridge>` : Similar to above but prints the descriptions of tables belonging to the stated bridge.

ovs-ofctl dump-ports-desc is useful for viewing port connectivity. This is useful in detecting errors in your NIC to bridge bonding.

Below are the common configurations used with the ovs-ofctl tool:

`ovs-ofctl add-flow <bridge> <flow>` : Add a static flow to the specified bridge. Useful in defining conditions for a flow (i.e. prioritize, drop, etc).<br>
`ovs-ofctl del-flows <bridge> <flow>` : Delete the flow entries from flow table of stated bridge. If the flow is omitted, all flows in specified bridge will be deleted.<br>

The above commands can take many arguments regarding different field to match. They can be used for simple source/destination flow additions to complex L3 rewriting (SNAT, DNAT, etc). You can even build a functional router with them :)


#### ovs-dpctl

ovs-dpctl is very similar to ovs-ofctl in that they both show flow table entries. The flows that ovs-dpctl prints are always an exact match and reflect packets that have actually passed through the system within the last few seconds. ovs-dpctl queries a kernel datapath and not an OpenFlow switch. This is why it's useful for debugging flow data.

Starting in version 1.9, OVS switched to using a single datapath that is shared by all bridges of that type. In order to create a new datapath, use the following:

`ovs-dpctl add-dp dp1`<br>
`ovs-dpctl add-if dp1 eth0`

Then use the following to view flow table data:

`ovs-dpctl dump-flows`

#### ovs-appctl

OVS is comprised of several daemons that manage and control an Open vSwitch switch. ovs-appctl is a utility for managing these daemons at runtime. It is useful for configuring log module settings as well as viewing all OpenFlow flows, including hidden ones.

The following are useful commands to use:

`ovs-appctl bridge/dump-flows <bridge>` : Dumps OpenFlow flows, including hidden flows. Useful for troubleshooting in-band issues.<br>
`ovs-appctl dpif/dump-flows <bridge>` : Dumps datapath flows for only the specified bridge, regardless of the type.<br>
`ovs-appctl vlog/list` : Lists the known logging modules and their current levels. Use ovs-appctl vlog/set <module> <level> to set/change the module log level.<br>
`ovs-appctl ofproto/trace` : Used to show entire flow field of a given flow (flow, matched rule, action taken).

Now, with all of these tools at your disposal, let's go over some common troubleshooting scenarios.

### Troubleshooting

One of the most common issues I've encountered has been problems with linking an interface to an OVS bridge. Take this configuration for example:

ovs-vsctl add-br brbm
ovs-vsctl add-port brbm eth2

The above configuration creates an OVS bridge (brbm) and links the physical interface eth2 to brbm. If you've enabled ip_forwarding and have created the bridge interfaces in your network interfaces file but have zero connectivity to the new interface, then how do you troubleshoot? Let's use some of the tools above to verify our configuration:

    root@testnode1:~# ovs-vsctl show
    cae63bc8-ba98-451a-a652-a3b0e8a0f553
        Bridge brbm
            Port "eth2"
                Interface "eth2"
            Port brbm
                Interface brbm
                    type: internal


    root@testnode1:~# ovs-vsctl list-ports brbm
    eth2

    root@testnode1:~# ovs-ofctl dump-ports brbm
    OFPST_PORT reply (xid=0x2): 1 ports
      port LOCAL: rx pkts=23, bytes=1278, drop=0, errs=0, frame=0, over=0, crc=0
               tx pkts=369369, bytes=62820789, drop=0, errs=0, coll=0

    root@testnode1:~# ovs-ofctl dump-ports-desc brbm
    OFPST_PORT_DESC reply (xid=0x2):
     LOCAL(brbm): addr:78:e7:d1:24:73:85
     config:     0
     state:      0
     speed: 0 Mbps now, 0 Mbps max

    root@testnode1:/etc/network# ifconfig
    brbm      Link encap:Ethernet  HWaddr 78:e7:d1:24:73:85  
              inet addr:10.23.32.15  Bcast:0.0.0.0  Mask:255.255.248.0
              inet6 addr: fe80::16:e1ff:fe1f:f3e4/64 Scope:Link
              UP BROADCAST RUNNING  MTU:1500  Metric:1
              RX packets:369369 errors:0 dropped:159944 overruns:0 frame:0
              TX packets:23 errors:0 dropped:0 overruns:0 carrier:0
              collisions:0 txqueuelen:0
              RX bytes:62820789 (62.8 MB)  TX bytes:1278 (1.2 KB)

    eth2      Link encap:Ethernet  HWaddr 78:e7:d1:24:73:85  
              inet6 addr: fe80::7ae7:d1ff:fe24:7385/64 Scope:Link
              UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
              RX packets:14148 errors:0 dropped:68 overruns:0 frame:0
              TX packets:8 errors:0 dropped:0 overruns:0 carrier:0
              collisions:0 txqueuelen:1000
              RX bytes:2198636 (2.1 MB)  TX bytes:648 (648.0 B)

    lo        Link encap:Local Loopback  
              inet addr:127.0.0.1  Mask:255.0.0.0
          	inet6 addr: ::1/128 Scope:Host
          	UP LOOPBACK RUNNING  MTU:65536  Metric:1
          	RX packets:17701 errors:0 dropped:0 overruns:0 frame:0
          	TX packets:17701 errors:0 dropped:0 overruns:0 carrier:0
          	collisions:0 txqueuelen:0
              RX bytes:1487216 (1.4 MB)  TX bytes:1487216 (1.4 MB)

    root@testnode1:/etc/network# cat /proc/sys/net/ipv4/ip_forward
	1


From the output above I see that although the OVS and interfaces file looks correct, I do not see any port traffic aside from LOCAL. LOCAL traffic is traffic generated from the host (ICMP in/out, ARP, etc). What is missing from the original OVS configuration statement is a restart of the networking stack. After the restart, we can see proper flow generation:

	root@testnode1:~# ovs-ofctl dump-ports-desc brbm
	OFPST_PORT_DESC reply (xid=0x2):
 	1(eth2): addr:78:e7:d1:24:73:85
     	config:     0
     	state:      0
     	current:    10GB-FD FIBER
     	advertised: 10GB-FD FIBER
     	supported:  10GB-FD FIBER
     	speed: 10000 Mbps now, 10000 Mbps max


	root@testnode1:~# ovs-ofctl dump-ports brbm
	OFPST_PORT reply (xid=0x2): 3 ports
  	port  5: rx pkts=6071934, bytes=37086750067, drop=0, errs=0, frame=0, over=0, crc=0
           tx pkts=6888905, bytes=626021363, drop=0, errs=0, coll=0
 	 port  1: rx pkts=32317009, bytes=32290813174, drop=0, errs=0, frame=0, over=0, crc=0
           tx pkts=25212056, bytes=83553302356, drop=0, errs=0, coll=0
  	port LOCAL: rx pkts=12293904, bytes=1780442549, drop=0, errs=0, frame=0, over=0, crc=0
           tx pkts=24816664, bytes=31363410668, drop=0, errs=0, coll=0

Now that's a proper link :)

## Conclusion

Open vSwitch provides a handful of useful tools for troubleshooting different configurations. I've only covered a handful of commands that I've used but may turn this into a more in depth series.

Until next time...
