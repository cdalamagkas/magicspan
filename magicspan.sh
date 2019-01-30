#!/bin/sh

usage="$(basename "$0") [OPTION] ... -- Configures a port mirroring session in XenServer or XCP-ng with Open vSwitch as the backend, only by providing the names of monitored VMs and networks.

Mandatory arguments:
    -m, --monitored-vm    set the name of VMs you want to monitor, 
                          seperated by comma.
    -o, --output-vm       set the name of the VM you want to send the
                          mirrored traffic to.
    -n, --network         set the name of the network, where all these
                          VMs are placed to.
	
Optional arguments:	
    -p, --source-pif [eth0]    automaticaly selects the pif (only one) that is attached to the
	                           selected network as a source port. If you specify one or more pif
                               labels, then those pifs are being selected as source ports. 
    -h, --help                 show this help text.
	-t, --test                 test mode: prints the ovs-vsctl command, without executing it."

TEMP=`getopt -o m:p:o:n:ht --long monitor-vm:,source-pif:,output-vm:,network:,help,test -- "$@"`

if [ $? != 0 ] ; then echo "$? is not 0. Terminating..." >&2 ; exit 1 ; fi

eval set -- "$TEMP"
sourcePifs=()

while true ; do    
	case "$1" in
        -m|--monitor-vm)
			IFS=',' read -r -a monitoredVM <<< "$2"
			shift 2;;
			
		-p|--source-pif)			
		    case "$2" in
				"") 
					autoPif=1 
					shift ;;
				*)  
					IFS=',' read -r -a sourcePifs <<< "$2"
					shift 2 ;;
			esac ;;
			
        -o|--output-vm) 
			outputVM=$2
			shift 2;;
			
        -n|--network) 
			network=$2
			shift 2;;
			
		-h|--help)
			echo "Usage: $usage"
			exit ;;
			
		-t|--test)
			testMode=1
			shift ;;
			
		--) 
			shift ; 
			break ;;	
        *) 
			echo "Usage: $usage"
			exit 1 ;;
    esac
done

bridgeLabel=`xe network-list name-label=$network | grep -i bridge | tr -s ' ' | cut -d ' ' -f5`

domainSource=()
for var in "${monitoredVM[@]}" ; do
	domainSource+=(`xl list | grep -i $var | tr -s ' ' | cut -d ' ' -f2`)
done

domainOutput=`xl list | grep -i $outputVM | tr -s ' ' | cut -d ' ' -f2`

#First of all, clear existing mirrorings that exist on the same bridge.
ovs-vsctl clear Bridge $bridgeLabel mirrors  

monitoredPorts=()

for p in `ovs-vsctl list-ports $bridgeLabel` ; do	
	array=(`grep -Eo '[[:alpha:]]+|[0-9]+' <<< "$p"`)
	
	interfaceType=${array[0]}
	domID=${array[1]}
	portID=${array[2]}
		
	if [ $interfaceType = "vif" ] ; then
		for var in "${domainSource[@]}" ; do
			if [ $domID = $var ] ; then
				monitoredPorts+=("vif${domID}.${portID}")
			fi
		done
		if [ $domID = $domainOutput ] ; then
			outputPort="vif${domID}.${portID}"
		fi
	elif [ $interfaceType = "eth" ] && [ ! -z $autoPif ] ; then
		sourcePifs+=("eth$domID")
	fi
done

commandString="ovs-vsctl -- set Bridge $bridgeLabel mirrors=@m"
for (( i=0; i<${#monitoredPorts[@]}; i++ )) ; do
	commandString="$commandString -- --id=@src$i get Port ${monitoredPorts[$i]}"
done

if [ ${#sourcePifs[@]} -ne 0 ]; then
	for (( i=${#monitoredPorts[@]}; i<$(( ${#monitoredPorts[@]} + ${#sourcePifs[@]} )); i++ )) ; do
		index=$(( $i - ${#monitoredPorts[@]} ))
		commandString="$commandString -- --id=@src$i get Port ${sourcePifs[$index]}"
	done
fi 

commandString="$commandString -- --id=@out get Port $outputPort -- --id=@m create Mirror name=idsMirror select-dst-port="

for (( i=0; i<${#monitoredPorts[@]}; i++ )) ; do
	commandString="$commandString@src$i,"
done
commandString=${commandString%?};  # Removes the last comma

commandString="$commandString select-src-port="
for (( i=0; i<${#monitoredPorts[@]}; i++ )) ; do
	commandString="$commandString@src$i,"
done
if [ ${#sourcePifs[@]} -ne 0 ] ; then
	for (( i=${#monitoredPorts[@]}; i<$(( ${#monitoredPorts[@]} + ${#sourcePifs[@]} )); i++ )) ; do
		commandString="$commandString@src$i,"
	done
fi
commandString=${commandString%?};  # Removes the last comma	


commandString="$commandString output-port=@out"

if [ ! -z $testMode ] ; then
	echo $commandString
else
	eval $commandString
fi