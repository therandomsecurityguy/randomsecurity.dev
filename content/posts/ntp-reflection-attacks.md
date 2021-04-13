---
author: "dc"
date: 2014-02-11T12:31:26Z
description: ""
draft: false
slug: "ntp-reflection-attacks"
tags: ["DDOS", "NTP", "Attacks"]
title: "NTP reflection attacks"

---



The buzz
--------

There has been a lot of traction in the news lately regarding a 'new' DDOS attack vector in regards to network time protocol ([NTP](http://en.wikipedia.org/wiki/Network_Time_Protocol)) based attacks. NTP reflection is similar in nature to [DNS reflection](http://en.wikipedia.org/wiki/Reflection_attack "DNS reflection") in that it is a UDP-based protocol that can be persuaded to return a large reply to a small request. To give a little background on this type of attack I'll explain how it works. A reflection attack works when an attacker can send a packet with a spoofed source IP address. The attacker sends a packet apparently *from* the intended victim to a random server on the Internet that will reply immediately. Because the source IP address is spoofed to look like the victim IP, the remote Internet server replies and sends data to the victim. The result is two-fold: the real source of the attack is hidden and unknown and, if several servers are used, the attack can be amplified. The amplification becomes more severe when the attacker sends spoofed packet that elicits a large reply from the server(s) in question. This attack can turn a small amount of bandwidth that the attacker uses to generate the attack into a massive bandwidth attack from server(s) globally.

How does it happen?
-------------------

NTP, like DNS, is a simple UDP-based protocol that is prone to amplification attacks because it will reply to a packet with a spoofed source IP address and because it contains built in commands will send a long reply to a short request. NTP supports a monitoring service that allows administrators to query the server for traffic counts of connected clients. This information is provided via the “monlist” command. The basic attack technique consists of an attacker sending a "get monlist" request to a vulnerable NTP server, with the source address spoofed to be the victim’s address. An example of this would be:

<tt> ntpdc -c monlist x.x.x.x</tt>

This command causes a list of the last 600 IP addresses which connected to the NTP server to be sent to the victim. Because the size of the response is typically considerably larger than the request, the attacker is able to amplify the volume of traffic directed at the victim. So any attacker can take a list of open NTP servers and perform this attack. A simple Google search for Open NTP servers can show you how easy it is to locate these servers. At the same time, the NMAP utility has a [module](http://nmap.org/nsedoc/scripts/ntp-monlist.html) available to detect NTP servers that have the monlist command available.

Solution?
---------

This is referenced in [CVE-2013-5211](http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2013-5211) that the recommended course of action is to upgrade ntpd to version 4.2.7 or later, which disables the monlist command, or to add the “noquery” directive to the “restrict default” line in the server’s ntp.conf, as shown below:

<tt>restrict default kod nomodify notrap nopeer noquery </tt>
<tt>restrict -6 default kod nomodify notrap nopeer noquery</tt>

From the network side, using [secure NTP](http://www.team-cymru.org/ReadingRoom/Templates/secure-ntp-template.html) templates are available to limit the impact of amplification attacks. At the same time. implementing [BCP-38](http://tools.ietf.org/html/bcp38) will help combat IP spoofing in general. For more info:

[DNS amplification](https://www.us-cert.gov/ncas/alerts/TA13-088A)

[DDOS attack](http://en.wikipedia.org/wiki/Denial-of-service_attack)

[This is how easy it is to perform a DDOS](http://www.youtube.com/watch?v=80yvb93a2qQ)
