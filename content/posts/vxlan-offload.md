---
author: "dc"
date: 2015-03-08T01:04:21Z
draft: false
slug: "vxlan offload"
tags: ["VXLAN", "OpenvSwitch", "How It Works"]
title: "VXLAN Offload"

---


It's been a while since I last posted due to work and life in general. I've been working on several NFV projects and thought I'd share some recent testing that I've been doing...so here we go :)

## Let me offload that for ya!

In a multi-tenancy environment (OpenStack, Docker, LXC, etc), VXLAN solves the limitation of 4094 VLANs/networks, but introduces a few caveats:

* Performance impact on the data path due to encapsulation overhead
* Inability of hardware offload capabilities on the inner packet

These extra packet processing workloads are handled by the host operating system in software, which can result in increased overall CPU utilization and reduced packet throughput.

Network interface cards like the Intel X710 and Emulex OneConnect can offload some of the CPU resources by processing the workload in the physical NIC.

Below is a simple lab setup to test VXLAN offload data path with offload hardware. The main focus is to compare the effect of VXLAN offloading and how it performs directly over a physical or bridge interface.

## Test Configuration

The lab topology consists of the following:

* Nexus 9372 (tenant leaf) w/ jumbo frames enabled
* Cisco UCS 220 M4S (client)
* Cisco UCS 240 M4X (server)
* Emulex OneConnect NICs

<b>Specs:</b>
<table border="3" style="background-color:#FFFFFF; solid #000000;color:#000000;width:100%" cellpadding="0" cellspacing="0">
	<tr>
		<td><b>Client</td>
		<td><b>Server</td>
	</tr>
	<tr>
		<td>2 x Intel Xeon CPU E5-2680 v3 @ 2.50GHz</td>
		<td>2 x Intel Xeon CPU E5-2680 v3 @ 2.50GHz</td>
	</tr>
	<tr>
		<td>256GB RAM </td>
		<td>256GB RAM</td>
	</tr>
	<tr>
		<td>Emulex OneConnect NIC (Skyhawk) (rev 10)</td>
		<td>Emulex OneConnect NIC (Skyhawk) (rev 10)</td>
	</tr>
</table>
<br>
*Red Hat Enterprise Linux Server release 7.1 with the standard supported kernel (3.10.0-229.1.2.el7.x86_64) was used for this test.*


#### Lab topology

![](/images/VXLAN-Emulex-lab-2.png)

Four types of traffic flows have been used to compare the impact of Emulex's VXLAN offload when the feature has been enabled or disabled:

    ethtool -k <eth0/eth1> tx-udp_tnl-segmentation <on/off>

<table border="1" style="background-color:#FFFFFFF;border-collapse:collapse;border:1px solid #000000;color:#000000;width:100%" cellpadding="3" cellspacing="3">
	<tr>
		<td><b>Traffic Flow Type</b></td>
		<td><b>Data Path</b></td>
	</tr>
	<tr>
		<td>Physical-to-physical (baseline test)</td>
		<td>client eth1 -> leaf -> server eth1</td>
	</tr>
	<tr>
		<td>VXLAN-to-VXLAN over physical</td>
		<td>client vxlan1 -> eth1 -> leaf -> eth1 -> server vxlan1</td>
	</tr>
	<tr>
		<td>VXLAN-to-VXLAN over bridge</td>
		<td>client vxlan10 -> br-int -> eth0 -> leaf -> eth1 -> br-int - > server vxlan10</td>
	</tr>
</table>

#### Tools

Netperf was used to generate TCP traffic between client and server. It is a light user-level process that is widely used for networking measurement. The tool consists of two binaries:

* netperf - user-level process that connects to the server and generates traffic
* netserver - user-level process that listens and accepts connection requests

**MTU considerations: VXLAN tunneling adds 50 bytes (14-eth + 20-ip + 8-udp + 8-vxlan) to the VM Ethernet frame. You should make sure that the MTU of the NIC that sends the packets takes into account the tunneling overhead (the configuration below shows the MTU adjustment).

### Client Configuration

    # Update system
    yum update -y

    # Install and start OpenvSwitch
    yum install -y openvswitch
    service openvswitch start

    # Create bridge
    ovs-vsctl add-br br-int

    # Create VXLAN interface and set destination VTEP
    ovs-vsctl add-port br-int vxlan0 -- set interface vxlan0 type=vxlan options:remote_ip=<server ip> options:key=10 options:dst_port=4789

    # Create tenant namespaces
    ip netns add tenant1

    # Create veth pairs
    ip link add host-veth0 type veth peer name host-veth1
    ip link add tenant1-veth0 type veth peer name tenant1-veth1

    # Link primary veth interfaces to namespaces
    ip link set tenant1-veth0 netns tenant1

    # Add IP addresses
    ip a add dev host-veth0 192.168.0.10/24
    ip netns exec tenant1 ip a add dev tenant1-veth0 192.168.10.10/24

    # Bring up loopback interfaces
    ip netns exec tenant1 ip link set dev lo up

    # Set MTU to account for VXLAN overhead
    ip link set dev host-veth0 mtu 8950
    ip netns exec tenant1 ip link set dev tenant1-veth0 mtu 8950

    # Bring up veth interfaces
    ip link set dev host-veth0 up
    ip netns exec tenant1 ip link set dev tenant1-veth0 up

    # Bring up host interfaces and set MTU
    ip link set dev host-veth1 up
    ip link set dev host-veth1 mtu 8950
    ip link set dev tenant1-veth1 up
    ip link set dev tenant1-veth1 mtu 8950

    # Attach ports to OpenvSwitch
    ovs-vsctl add-port br-int host-veth1
    ovs-vsctl add-port br-int tenant1-veth1

    # Enable VXLAN offload
    ethtool -k eth0 tx-udp_tnl-segmentation on
    ethtool -k eth1 tx-udp_tnl-segmentation on

### Server Configuration

    # Update system
    yum update -y

    # Install and start OpenvSwitch
    yum install -y openvswitch
    service openvswitch start

    # Create bridge
    ovs-vsctl add-br br-int

    # Create VXLAN interface and set destination VTEP
    ovs-vsctl add-port br-int vxlan0 -- set interface vxlan0 type=vxlan options:remote_ip=<client ip> options:key=10 options:dst_port=4789

    # Create tenant namespaces
    ip netns add tenant1

    # Create veth pairs
    ip link add host-veth0 type veth peer name host-veth1
    ip link add tenant1-veth0 type veth peer name tenant1-veth1

    # Link primary veth interfaces to namespaces
    ip link set tenant1-veth0 netns tenant1

    # Add IP addresses
    ip a add dev host-veth0 192.168.0.20/24
    ip netns exec tenant1 ip a add dev tenant1-veth0 192.168.10.20/24

    # Bring up loopback interfaces
    ip netns exec tenant1 ip link set dev lo up

    # Set MTU to account for VXLAN overhead
    ip link set dev host-veth0 mtu 8950
    ip netns exec tenant1 ip link set dev tenant1-veth0 mtu 8950

    # Bring up veth interfaces
    ip link set dev host-veth0 up
    ip netns exec tenant1 ip link set dev tenant1-veth0 up

    # Bring up host interfaces and set MTU
    ip link set dev host-veth1 up
    ip link set dev host-veth1 mtu 8950
    ip link set dev tenant1-veth1 up
    ip link set dev tenant1-veth1 mtu 8950

    # Attach ports to OpenvSwitch
    ovs-vsctl add-port br-int host-veth1
    ovs-vsctl add-port br-int tenant1-veth1

    # Enable VXLAN offload
    ethtool -k eth0 tx-udp_tnl-segmentation on
    ethtool -k eth1 tx-udp_tnl-segmentation on

### Offload verification

    [root@client ~]# dmesg | grep VxLAN
    [ 6829.318535] be2net 0000:05:00.0: Enabled VxLAN offloads for UDP port 4789
    [ 6829.324162] be2net 0000:05:00.1: Enabled VxLAN offloads for UDP port 4789
    [ 6829.329787] be2net 0000:05:00.2: Enabled VxLAN offloads for UDP port 4789
    [ 6829.335418] be2net 0000:05:00.3: Enabled VxLAN offloads for UDP port 4789

    [root@client ~]# ethtool -k eth0 | grep tx-udp
    tx-udp_tnl-segmentation: on

    [root@server ~]# dmesg | grep VxLAN
    [ 6829.318535] be2net 0000:05:00.0: Enabled VxLAN offloads for UDP port 4789
    [ 6829.324162] be2net 0000:05:00.1: Enabled VxLAN offloads for UDP port 4789
    [ 6829.329787] be2net 0000:05:00.2: Enabled VxLAN offloads for UDP port 4789
    [ 6829.335418] be2net 0000:05:00.3: Enabled VxLAN offloads for UDP port 4789

    [root@server ~]# ethtool -k eth0 | grep tx-udp
    tx-udp_tnl-segmentation: on

<p>

## Testing

As stated before, Netperf was used for getting the throughput and the CPU utilization for the server and the client side. The test was run over the bridged interface in the Tenant1 namespace with VXLAN Offload off and Offload on.

Copies of the netperf scripts can be found here:

[TCP stream testing](https://gist.github.com/therandomsecurityguy/191ac4d8525f62e9e7f3)<br>
[UDP stream testing](https://gist.github.com/therandomsecurityguy/5a3b060fd6879315b721)<p>

<b>Throughput:</b>
![](/images/total-throughput.png)<br>
<b>% CPU Utilization (Server side):</b>
 ![](/images/CPU-server.png)<br>
<b>% CPU Utilization (Client side):</b>
![](/images/CPU-client.png)<p>

I conducted several TCP stream tests saw the following results with different buffer/socket sizes:

<b>Socket size of 128K(sender and Receiver):</b>
![](/images/socket-128k.png)<br>
<b>Socket size of 32K(sender and Receiver):</b>
![](/images/socket-32k.png)<br>
<b>Socket size of 4K(sender and Receiver):</b>
![](/images/socket-4k.png)<br><p>

#### NETPERF Raw Results:

<b>Offload Off:</b>

    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to 192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 6.663%
    !!!                       Local CPU util  : 14.049%
    !!!                       Remote CPU util : 13.944%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384   4096    10.00      9591.78   1.18     0.93     0.483   0.383  

    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to     192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 4.763%
    !!!                       Local CPU util  : 7.529%
    !!!                       Remote CPU util : 10.146%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384   8192    10.00      9200.11   0.94     0.90     0.402   0.386  

    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to     192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 4.469%
    !!!                       Local CPU util  : 8.006%
    !!!                       Remote CPU util : 8.229%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384  32768    10.00      9590.11   0.65     0.90     0.268   0.367  

    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to     192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 7.053%
    !!!                       Local CPU util  : 12.213%
    !!!                       Remote CPU util : 13.209%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384  16384    10.00      9412.99   0.76     0.85     0.316   0.357  
    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to     192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 1.537%
    !!!                       Local CPU util  : 12.137%
    !!!                       Remote CPU util : 15.495%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384  65536    10.00      9106.93   0.59     0.85     0.253   0.369  

<b>Offload ON:</b>

    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to 192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 5.995%
    !!!                       Local CPU util  : 8.044%
    !!!                       Remote CPU util : 7.965%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384   4096    10.00      9632.98   1.08     0.91     0.440   0.371  
    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to     192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 0.031%
    !!!                       Local CPU util  : 6.747%
    !!!                       Remote CPU util : 5.451%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384   8192    10.00      9837.25   0.91     0.91     0.362   0.363  
    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to 192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 0.099%
    !!!                       Local CPU util  : 7.835%
    !!!                       Remote CPU util : 13.783%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384  16384    10.00      9837.17   0.65     0.89     0.261   0.354  
    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to     192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 0.092%
    !!!                       Local CPU util  : 7.445%
    !!!                       Remote CPU util : 8.866%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384  32768    10.00      9834.57   0.53     0.88     0.212   0.353  

    MIGRATED TCP STREAM TEST from 0.0.0.0 (0.0.0.0) port 0 AF_INET to     192.168.10.20 () port 0 AF_INET : +/-2.500% @ 99% conf.
    !!! WARNING
    !!! Desired confidence was not achieved within the specified iterations.
    !!! This implies that there was variability in the test environment that
    !!! must be investigated before going further.
    !!! Confidence intervals: Throughput      : 5.255%
    !!!                       Local CPU util  : 7.245%
    !!!                       Remote CPU util : 8.528%

    Recv   Send    Send                          Utilization       Service Demand
    Socket Socket  Message  Elapsed              Send     Recv     Send    Recv
    Size   Size    Size     Time     Throughput  local    remote   local   remote
    bytes  bytes   bytes    secs.    10^6bits/s  % S      % S      us/KB   us/KB

     87380  16384  65536    10.00      9465.12   0.52     0.90     0.214   0.375  


## Test results

Line rate speeds were achieved in almost all traffic flow type tests with the exception of VXLAN over bridge. For VXLAN over physical flow test, the CPU utilization was pretty much similar to the baseline physical flow test as no encapsulation was taken place. When offload was disabled, the CPU usage increased by over 50%.

Given that Netperf is single process threaded, and forwarding pins to one CPU core only, the CPU utilization shown was an extrapolated result from what was reported by the tool which was N*8 cores. This also showed how throughput was effected by CPU resource as seen in the case with VXLAN over bridge test. Also, reduction in socket sizes produced higher CPU utilization with offload on, due to the smaller packet/additional overhead handling.

These tests were completed with the standard supported kernel in RHEL 7.1. There have been added [networking improvements in the 4.x kernel](http://kernelnewbies.org/LinuxChanges#head-f5beb868c879336ee5b4228336273fb1e7b39170) that in separate testing increased performance by over 3x, although existing results are very promising.

Overall, VXLAN offloading will be useful in getting past specific network limitations and achieving scalable east-west expansions.

## Code

[https://github.com/therandomsecurityguy/benchmarking-tools/tree/main/netperf](https://github.com/therandomsecurityguy/benchmarking-tools/tree/main/netperf)
