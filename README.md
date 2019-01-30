# magic-span
---

## Simple script to configure a SPAN session on XenServer or XCP-ng

When a VM boots or reboots, then the first available domU ID is assigned to that VM. Since virtual interface (vif) labels depend on the assigned domU, vif labels are difficult or impossible to predict, thus port mirroring configurations are not persistent through reboots. Magic-span tries to eliminate this limitation by making the port mirroring configuration to depend on persistent attributes of VMs, like VM and network name/label.    

Usage: `magicspan.sh {-m|--monitor-vm} vm1[,vm2] {-o|--output-vm} vm3 {-n|--network} lan1 [-h] [-t]`

Configures a port mirroring session in XenServer or XCP-ng, with Open vSwitch as the backend, only by providing the names of monitored VMs and networks.

Mandatory arguments:

* `-m, --monitored-vm`: set the name of VMs you want to monitor, separated by coma.
* `-o, --output-vm`: set the name of the VM you want to send the mirrored traffic to.
* `-n, --network`: set the name of the network, where all these VMs are placed to.

Optional arguments:

* `-p, --source-pif [ethX]` automatically selects the pif (only one) that is attached to the selected network as a source port. If you specify one or more pif labels, then those pifs are being selected as source ports. 
* `-h, --help`: show this help text.
* `-t, --test`: test mode: prints the ovs-vsctl command, without executing it.

## Examples

Send all ingress and egress traffic of VMs named "ZorinOS" and "Ubuntu" to "OSSIM" VM. All three VMs have one interface that belongs to the DMZ network.

    magicspan.sh --monitor-vm=ZorinOS,Ubuntu --output-vm=OSSIM --network=DMZ
    
Send all ingress and egress traffic of "Ubuntu" as well as ingress traffic of the local pif to "OSSIM" VM. The pif and VMs have belong to the DMZ network.    
    
    magicspan.sh --monitor-vm=Ubuntu --source-pif --output-vm=OSSIM --network=DMZ
