# MagicSPAN
---

## Simple script to configure a SPAN session on XenServer or XCP-ng

When a VM boots or reboots, then the first available domU ID is assigned to that VM. Since virtual interface (vif) labels depend on the assigned domU, vif labels are difficult or impossible to predict, thus port mirroring configurations are not persistent across reboots. MagicSPAN tries to eliminate this problem by making the port mirroring configuration to depend on constant attributes of VMs, like VM and network name/label.    

Usage: `magicspan.sh {-s|--source-vm} vm1[,vm2,..] {-d|--destination-vm} vm1[,vm2,..] {-o|--output-vm} vm3 {-n|--network} lan1 {-p|--source-pif} [eth0] [-h] [-t]`

Configures a port mirroring session in XenServer or XCP-ng, with Open vSwitch as the backend, only by providing the names of monitored VMs and networks.

Mandatory arguments:
    -o, --output-vm       set the name of the VM you want to send the
                          mirrored traffic to.
    -n, --network         set the name of the network, where all these
                          VMs are placed to.

At least one of the following is mandatory:
    -s, --source-vm          set the name of VMs you want to monitor their ingress traffic, 
                             seperated by comma.
    -d, --destination-vm     set the name of VMs you want to monitor their ergress traffic,
                             seperated by comma.
    -p, --source-pif [eth0]  automaticaly selects the pif (only one) that is attached to the
                             selected network as a source port. If you specify one or more pif
                             labels, then those pifs are selected as source ports. 

Optional arguments:	
    -h, --help              show this help text.
    -t, --test              test mode: prints the ovs-vsctl command, without executing it."


## Examples

Send all ingress and egress traffic of VMs named "ZorinOS" and "Ubuntu" to "OSSIM" VM. All three VMs have one interface that belongs to the MONITOR network.

    magicspan.sh --source-vm=ZorinOS,Ubuntu --destination-vm=ZorinOS,Ubuntu --output-vm=OSSIM --network=MONITOR
    
Send only ergress traffic of "Ubuntu" and the ingress traffic the local pif to "OSSIM" VM. The pif and VMs should belong to the DMZ network.    
    
    magicspan.sh --destination-vm=Ubuntu --source-pif --output-vm=OSSIM --network=DMZ
