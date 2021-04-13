---
author: "dc"
date: 2014-04-20T16:10:29Z
description: ""
draft: false
slug: "openflow"
tags: ["Openflow", "SDN"]
title: "Openflow"

---



Huh?
----

 With the recent advances in virtualization and abstracted computing, software-defined networking (SDN) has become a reality. Although decoupling the network control out of physical network devices into a central or clustered service has been the primary focus of SDN, the discussion around [Openflow](http://archive.openflow.org/wp/learnmore/ "Openflow") and SDN being the same is a bit of a misnomer. Before I talk about Openflow concepts and deployments strategies, let's break down a bit of what Openflow is, the difference between SDN and Openflow, and it's messaging scheme.

SDN != Openflow
---------------

In SDN, the network intelligence that is normally located within each network device is logically centralized in software-based controllers. This in turn makes physical (or virtual) network devices simple packet forwarding machines that can be programmed via an open interface. One of the most widely known open interface implementations is Openflow. By separating the control logic functionality from forwarding hardware, you create an environment that allows for easier: deployment of applications, network visualization, and management. So if it's that simple, then how does it work?

### Packet flow

Below is a brief diagram on the flow process within Openflow:

![](/images/OF-packet-flow.png)

When a packet arrives at the Openflow switch, the [packet header fields](http://yuba.stanford.edu/cs244wiki//images/thumb/f/f2/FlowTable-Example1.png/500px-FlowTable-Example1.png) are extracted and matched against current flow table entries (similar to a [CAM](http://en.wikipedia.org/wiki/CAM_Table) table). If a matching entry is found, the switch applies the appropriate set of instructions associated with the matching flow entry and updates it's respective entry counters. If the flow table procedure fails to produce a match, then the flow must follow the instructions from the table-miss entry. The table-miss entry is a required entry that specifies a set of instructions to be performed when no match is found for an incoming packet. Actions can include:

- Dropping the packet
- Sending the packet out on all interfaces
- Forwarding the packet to the Openflow controller

## Openflow messaging

First and foremost, communication between a software controller and Openflow switch (physical or virtual) occurs via a secure channel ([TLS-enabled](http://en.wikipedia.org/wiki/Transport_Layer_Security "TLS")) on TCP port 6633 (soon to be [TCP 6653](https://www.opennetworking.org//images/stories/downloads/sdn-resources/onf-specifications/openflow/openflow-spec-v1.4.0.pdf)). The switch and controller mutually authenticate each other by exchanging certificates via site-specific private key. Traffic to and from this secure channel is <span style="text-decoration: underline;">not</span> checked against the switch's flow table and therefore must be identified as local (to the switch). In the case of a loss of communication with the Openflow controller, the switch will attempt to contact a backup controller if configured. If not able to reach a backup controller, the switch will enter *emergency mode. *Emergency mode contains flow table entries that have been marked with the emergency bit set. These are considered as 'always needed' flows for operational communication. Openflow messaging is broken into 3 message types:

- Controller-to-switch
- Symmetric
- Asynchronous

### Controller-to-switch

Controller-to-switch messages are always initiated by the Openflow controller. They are used to directly manage or audit the state of the switch.

#### Features

Upon establishing a secure connection to the switch, the Openflow controller sends a *feature request* message to the switch. The switch must reply with a *feature reply* message which included the capabilities that are supported by the switch.

#### Configuration

The Openflow controller is able to set and query configuration parameters in the switch. The switch will only respond to configuration queries sourced from the Openflow controller.

#### Modify-State

These messages are sent by the Openflow controller to manage the state of the Openflow switch. They are used to add/delete/modify flow table entries and to set port priorities. Flow table modification messages can have the following types:

- ADD
- MODIFY
- DELETE
- MODIFY and DELETE (for strict matching)

#### Read-State

These messages are used for statistical collection (flow table entries, counters, etc).

#### Send-Packet

These messages are used by the Openflow controller to send packets out of a specified port on the switch (static flows).

#### Barrier

Barrier messages are used by the Openflow controller to receive notification for completed operations.

### Symmetric


Symmetric messages are sent either by the Openflow controller or the switch. The three, unsolicited message types are:

- Hello
- Echo
- Vendor

#### Hello

Hello messages are sent symmetrically upon connection setup

#### Echo

Similar to [ICMP](http://en.wikipedia.org/wiki/Internet_Control_Message_Protocol) or heartbeat connections, these messages can also be used to indicate latency/bandwidth issues.

#### Vendor

These messages provide a way of offering additional vendor functionality within future revisions on Openflow.

### Asynchronous

Asynchronous messages are always initiated by the switch and are used to inform the Openflow controller of changes to the switch state. Switches will send asynchronous messages to the Openflow controller to indicate packet arrival, switch state change, or errors. The four asynchronous message types are:

- Packet-in
- Flow-removal
- Port-status
- Error

#### Packet-in

This message is used for inbound packet entries that do not have a matching flow entry or for packets that match an entry with a *send to controller* action.

#### Flow-removal

When flows are added to the switch via the Openflow controller, an idle timeout value indicates when the flow entry should be removed due to lack of activity as well as a hard timeout value. A hard timeout value of zero means the flow will never expire, regardless of activity. The flow-removal message is sent to the controller when a flow expires.

#### Port-status

The switch will send port-status messages at system-defined intervals as port states change. Events included are user-defined changes (port disabled by user), virtual server disconnection (port disabled by system), and port status modifications due to spanning tree ([802.1d](http://en.wikipedia.org/wiki/Spanning_tree_protocol)).

#### Error

Self-explanatory

Summary
-------

As SDN grows, it's important to understand that Openflow is an SDN concept and they are not the same. Although there are many similarities within Openflow packet flows and traditional L2/L3 packet flows, the control channel is still unique. And finally, understanding the messaging is key in modifying existing open source solutions and building new custom Openflow-enabled applications. Further breakdown of Openflow messaging can be found below:

[Openflow 1.4 spec](https://www.opennetworking.org//images/stories/downloads/sdn-resources/onf-specifications/openflow/openflow-spec-v1.4.0.pdf)
