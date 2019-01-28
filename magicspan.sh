#!/bin/sh

usage="$(basename "$0") [-h] [-s SourceVM] [-d DestinationVM] [-n Network] -- program to configure a port mirroring in Xen and openvswitch, without intervening with vif ports that are not constant. 

where:
	-h | --help		show this help text
	-s | --source-vm	set the name of the VM you want to monitor
	-o | --output-vm	set the name of the VM you want to send the mirrored traffic
	-n | --network		set the name of the network, where both VMs are placed."


TEMP=`getopt -o s:o:n:h --long help,source-vm:,output-vm:,network: \
     -n 'example.bash' -- "$@"`

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

while true ; do
    case "$1" in
        -s|--source-vm)
			sourceVM=$2
			shift 2 ;;
			
        -o|--output-vm) 
			outputVM=$2
			shift 2 ;;
			
        -n|--network) 
			network=$2
			shift 2 ;;
			
		-h|--help)
			echo "Usage: $usage"
			exit ;;
		--) 
			shift ; 
			break ;;	
        *) 
			#echo "Usage: $usage"
			exit 1 ;;
    esac
done

#echo "Remaining arguments:"
#for arg do echo '--> '"\`$arg'" ; done



bridgeLabel=`xe network-list name-label=$network | grep -i bridge | tr -s ' ' | cut -d ' ' -f5`

domainSource=`xl list | grep -i $sourceVM | tr -s ' ' | cut -d ' ' -f2`

domainOutput=`xl list | grep -i $outputVM | tr -s ' ' | cut -d ' ' -f2`

#First of all, clear existing mirrorings that exist on the same bridge.

ovs-vsctl clear Bridge $bridgeLabel mirrors  


for p in `ovs-vsctl list-ports $bridgeLabel`; do
	
	array=(`grep -Eo '[[:alpha:]]+|[0-9]+' <<< "$p"`)
	
	interfaceType=${array[0]}
	domID=${array[1]}
	portID=${array[2]}
		
	if [ $interfaceType = "vif" ]; then
		
		if [ $domID = $domainSource ]; then
			sourcePort="vif${domID}.${portID}"
		fi
		
		if [ $domID = $domainOutput ]; then
			outputPort="vif${domID}.${portID}"
		fi
	
	fi
	
done

echo $sourcePort
echo $outputPort


ovs-vsctl -- set Bridge $bridgeLabel mirrors=@m \
-- --id=@src1 get Port $sourcePort \
-- --id=@dst get Port $outputPort \
-- --id=@m create Mirror name=idsMirror select-dst-port=@src1 \
select-src-port=@src1 output-port=@dst
