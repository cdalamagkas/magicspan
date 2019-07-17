#!/bin/sh

#TODO: Check for non-existing or invalid VMs and pifs

usage="$(basename "$0") [OPTION] ... -- Configures a port mirroring session in XenServer or XCP-ng with Open vSwitch as the backend, only by providing the names of monitored VMs and networks.

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

options=`getopt -o o:n:d:s:pht --long source-vm:,destination-vm:,source-pif:,output-vm:,network:,help,test -- "$@"`

if [ $? != 0 ] ; then echo "Incorrect options provided" ; exit 1 ; fi

sourcePif=()

#echo $options
eval set -- "$options"

while true; do    
	case "$1" in
        -s | --source-vm )
			IFS=',' read -r -a sourceVM <<< "$2"
			shift 2;;
			
		-d | --destination-vm )
			IFS=',' read -r -a destinationVM <<< "$2"
			shift 2;;
			
		-p | --source-pif )	
			case "$2" in
				-* | "")
					autoPif=1 
					shift ;;
				*)  
					IFS=',' read -r -a sourcePif <<< "$2"
					shift ;;
			esac ;;
			
        -o | --output-vm ) 
			outputVM=$2
			shift 2;;
			
        -n | --network ) 
			network=$2
			shift 2;;
			
		-h | --help )
			echo "Usage: $usage"
			exit ;;
			
		-t | --test)
			testMode=1
			shift ;;
			
		-- ) 
			shift ; 
			break ;;	
        * ) 
			echo $1
			echo "Usage: $usage"
			exit 1 ;;
    esac
done


if [[ -z ${sourceVM+x} && -z ${destinationVM+x} && -z ${allVM+x} && -z ${autoPif+x} && -z ${sourcePif+x} ]]; then
	echo "ERROR: No monitored VMs have been defined. Exiting..."
	exit 1;
fi 

# -1- Find the label of the bridge to which the mirror will be applied.
bridgeLabel=`xe network-list name-label=$network | grep -i bridge | tr -s ' ' | cut -d ' ' -f5`

# -2- Find the domains of the source VMs.
domainSource=()
for var in "${sourceVM[@]}" ; do
	domainSource+=(`xl list | grep -i $var | tr -s ' ' | cut -d ' ' -f2`)
done

# -3- Find the domains of the destination VMs.
for var in "${destinationVM[@]}" ; do
	domainDestination+=(`xl list | grep -i $var | tr -s ' ' | cut -d ' ' -f2`)
done

# -4- Find the domain of the output VM (only one!)
domainOutput=`xl list | grep -i $outputVM | tr -s ' ' | cut -d ' ' -f2`

sourcePorts=()
destinationPorts=()
#outputPort is determined inside the loop

# -5- Check each port of the bridge and determine the source, destination or output port labels
for p in `ovs-vsctl list-ports $bridgeLabel` ; do	
		
	# -5.1- For the current port, seperate its interface type, domain ID and device ID
	array=(`grep -Eo '[[:alpha:]]+|[0-9]+' <<< "$p"`)
	interfaceType=${array[0]}
	domID=${array[1]}
	deviceID=${array[2]}
	
	# -5.2- Check if the current port is virtual or physical
	if [ $interfaceType = "vif" ] ; then
		# -5.2.1- If it is virtual, check if the domain ID of the current port should be monitored for its ingress traffic
		for var in "${domainSource[@]}" ; do
			if [ $domID = $var ] ; then
				sourcePorts+=("vif${domID}.${deviceID}")
			fi
		done
		
		# -5.2.2- Then check if the domain ID of the current port should be monitored for its ergress traffic
		for var in "${domainDestination[@]}" ; do
			if [ $domID = $var ] ; then
				destinationPorts+=("vif${domID}.${deviceID}")
			fi
		done
		
		# -5.2.3- Then check if the current domain ID is the output VM
		if [ $domID = $domainOutput ] ; then
			outputPort="vif${domID}.${deviceID}"
		fi
		
	elif [ $interfaceType = "eth" ] && [ ! -z $autoPif ] ; then
		# -5.3- If the current port is physical and autoPif is enabled, then add the current port.
		sourcePif+=($p)
	fi
done

# Since the labels have been determined, we can start constructing the command

# -6- First, create the mirror and, second, define the source ports
commandString="ovs-vsctl -- set Bridge $bridgeLabel mirrors=@m"

for (( i=0; i<${#sourcePorts[@]}; i++ )) ; do
	commandString="$commandString -- --id=@src$i get Port ${sourcePorts[$i]}"
done

# -6.1- If source pifs have been defined, define them too.
if [ ${#sourcePif[@]} -ne 0 ]; then
	for (( i=${#sourcePorts[@]}; i<$(( ${#sourcePorts[@]} + ${#sourcePif[@]} )); i++ )) ; do
		index=$(( $i - ${#sourcePorts[@]} ))
		commandString="$commandString -- --id=@src$i get Port ${sourcePif[$index]}"
	done
fi 

# -7- All source ports have been defined, define now the destination ports.
for (( i=0; i<${#destinationPorts[@]}; i++ )) ; do
	commandString="$commandString -- --id=@dst$i get Port ${destinationPorts[$i]}"
done

# -8- Now define the output port
commandString="$commandString -- --id=@out get Port $outputPort -- --id=@m create Mirror name=idsMirror "

# -9- If destination ports have been defined, then add them to the mirror
if [ ${#destinationPorts[@]} -gt 0 ] ; then
	commandString="$commandString select-dst-port="
	for (( i=0; i<${#destinationPorts[@]}; i++ )) ; do
		commandString="$commandString@dst$i,"
	done
	commandString=${commandString%?};  # Removes the last comma
fi

# -10- If source ports have been defined, then add them to the mirror too
if [ ${#sourcePorts[@]} -gt 0 ] ; then
	commandString="$commandString select-src-port="
	for (( i=0; i<${#sourcePorts[@]}; i++ )) ; do
		commandString="$commandString@src$i,"
	done
	if [ ${#sourcePif[@]} -ne 0 ] ; then
		for (( i=${#sourcePorts[@]}; i<$(( ${#sourcePorts[@]} + ${#sourcePif[@]} )); i++ )) ; do
			commandString="$commandString@src$i,"
		done
	fi
	commandString=${commandString%?};  # Removes the last comma	
fi

commandString="$commandString output-port=@out"

if [ ! -z $testMode ] ; then
	echo $commandString
else
	#Before executing, clear existing mirrorings that exist on the same bridge.
	ovs-vsctl clear Bridge $bridgeLabel mirrors  
	eval $commandString
fi
