#!/bin/ksh 

# Check debug setting
debug()
{
 if [ "${DEBUG}" = "true" ]; then
  return 0
 else
  return 1
 fi
}

# Running on AIX?
aix()
{
 debug && set -x

# function checks if this is running on aix
if [ ${OS} = "AIX" ]; then
 return 0
else
 return 1
fi
}

# Running on HP-UX?
hpux()
{
 debug && set -x

# function checks if this is running on hp-ux
if [ ${OS} = "HP-UX" ]; then
 return 0
else
 return 1
fi
}

# Running on Linux?
linux()
{
 debug && set -x

# function checks if this is running on linux
if [ ${OS} = "Linux" ]; then
 return 0
else
 return 1
fi
}

getRACNodes()
{
 if [ -f /tmp/manual.node.list ]
 then
  export NODELIST="$(cat /tmp/manual.node.list)"
 else
  if [ $(id oracle 2>/dev/null | wc -l) -gt 0 ]
  then
   su - oracle -c 'olsnodes' >/tmp/manual.node.list
   export NODELIST="$(cat /tmp/manual.node.list)"
  else
   echo $(hostname) >/tmp/manual.node.list
   export NODELIST="$(cat /tmp/manual.node.list)"
  fi
 fi
}

getSecondaryNodes()
{
 if [ -f /tmp/secondary.node.list ]
 then
  export SECONDARYNODELIST=$(cat /tmp/secondary.node.list)
 else
  if [ $(id oracle 2>/dev/null | wc -l) -gt 0 ]
  then
   su - oracle -c 'olsnodes|grep -v $(hostname)' >/tmp/secondary.node.list
   export SECONDARYNODELIST=$(cat /tmp/secondary.node.list)
  fi
 fi
}

# This sets all the default variables and parses options passed in
setVars()
{
 CLEANUP=false
 POWERPATH=false
 RDAC=false
 DATAPATH=false
 PCMPATH=false
 NATIVEMPIO=false
 HPQLOGIC=false
 NOSAN=false
 SUPPORTEDSAN=true
 DEBUG=false
 ODIR=/stage/managed-services/$(hostname)
 OS="$(uname -s)"
 CONTINUE=false
 SUCCESS=false
 LOG=/tmp/$(hostname)-adv-pre.log
 STEP=none

 while getopts ":rpDPnNdo:OCQR:c" options; do
  case ${options} in
   r) RDAC=true;;
   p) POWERPATH=true;;
   D) DATAPATH=true;;
   P) PCMPATH=true;;
   n) NATIVEMPIO=true;;
   Q) HPQLOGIC=true;;
   N) NOSAN=true;;
   d) DEBUG=true; set -x;;
   o) ODIR="${OPTARG}";;
   O) OS=OVERRIDE;;
   C) CONTINUE=true;;
   R) STEP="${OPTARG}";;
   c) CLEANUP=true;;
   h|\?|:|*) echo "Help requested via -h or incorrect option"; usage;exit 1;;
  esac
 done

 getRACNodes
 getSecondaryNodes
}

# Are we running on a supported OS? if so, what version?
checkOS()
{
 case ${OS} in
  Linux) SUPPORTEDOS=true; 
	OSDETAILS="$(lsb_release -a)";
	RHELREL=$(lsb_release -r -c| awk '{print $2}'|tr '\012' ' '|tr '\012' ' ')
	echo "Linux is a supported platform, currently running RHEL ${RHELREL}";
	;;
  AIX) SUPPORTEDOS=false;
	OSDETAILS="$(oslevel -r)";
	AIXREL="$(oslevel -r)";
	echo "${OS} is in BETA, please override to continue anyway"; 
	usage;
	exit 1;
	;;
  HP-UX) SUPPORTEDOS=false;
	echo "${OS} is in BETA, please override to continue anyway"; 
	usage;
	exit 1;
	;;
  OVERRIDE) SUPPORTEDOS=true; echo "OS Override in effect";;
  *) SUPPORTEDOS=false; 
	echo "Running on unsupported OS (${OS}), please override to continue anyway"; 
	usage;
	exit 1;
	;;
 esac >${ODIR}/adv-srv-${step}.out 2>&1
 if [ ${SUPPORTEDOS} = "true" ]; then
  SUCCESS=true
 else
  SUCCESS=false
 fi

 displayOutput ${SUCCESS} "Checking for a supported OS"
}

# this function determines which SAN type to utilize. If you have
# any improvements here, please speak up. Especially with some
# way to detect multiple SAN types
checkSAN()
{
 if [ ${NATIVEMPIO} = "true" ]; then
  true
  echo "NativeMPIO forced, setting NATIVEMPIO=true"
  SUCCESS=true
 elif [ ${PCMPATH} = "true" ]; then
  true
  echo "Pcmpath forced, setting PCMPATH=true"
  SUCCESS=true
 elif [ ${POWERPATH} = "true" ]; then
  true
  echo "PowerPath forced, setting POWERPATH=true"
  SUCCESS=true
 elif [ ${DATAPATH} = "true" ]; then
  true
  echo "Datapath forced, setting DATAPATH=true"
  SUCCESS=true
elif [ ${RDAC} = "true" ]; then
  true
  echo "RDAC (mppUtil) forced, setting RDAC=true"
  SUCCESS=true
 elif [ ${HPQLOGIC} = "true" ]; then
  true
  echo "HP/Qlogic forced, setting HPQLOGIC=true"
  echo "Sometimes this driver is not configured/used properly. If the"
  echo " system is using native mpio on top, force that option instead."
  SUCCESS=true
 elif [ ${NOSAN} = "true" ]; then
  true
  echo "NOSAN forced, setting NOSAN=true"
  SUCCESS=true
 elif [ -x "$(which powermt 2>/dev/null)" -o ${POWERPATH} = "true" ]; then
  POWERPATH=true
  echo "PowerPath detected, setting POWERPATH=true"
  SUCCESS=true
 elif [ -x "$(which datapath 2>/dev/null)" -o ${DATAPATH} = "true" ]; then
  DATAPATH=true
  echo "Datapath detected, setting DATAPATH=true"
  SUCCESS=true
 elif [ -x "$(which mppUtil 2>/dev/null)" -o ${RDAC} = "true" ]; then
  RDAC=true
  echo "RDAC (mppUtil) detected, setting RDAC=true"
  SUCCESS=true
 elif [ -x "$(which pcmpath 2>/dev/null)" -o ${PCMPATH} = "true" ]; then
  PCMPATH=true
  echo "pcmpath detected, setting PCMPATH=true"
  SUCCESS=true
 elif [ -x "$(which lssd 2>/dev/null)" -o ${HPQLOGIC} = "true" ]; then
  HPQLOGIC=true
  echo "HP/Qlogic detected, setting HPQLOGIC=true"
  echo "Sometimes this driver is not configured/used properly. If the"
  echo " system is using native mpio on top, force that option instead."
  SUCCESS=true
 else
  echo "No supported SAN multipath drivers detected, please force a selection"
  SUCCESS=false
 fi >${ODIR}/adv-srv-${step}.out 2>&1

 displayOutput ${SUCCESS} "Determining SAN driver in use"
}

# short way to display a linebreak for easy viewing of the log
lineBreak()
{
 debug && set -x

 echo "################################################################################"
}

# a nice help function to explain how to use this script
usage()
{
 debug && set -x

 lineBreak
 echo "This script will run Advanced Services universal pre-checks"
 lineBreak
 echo "./$(basename $0) [-h] [-d] [-r|-p|-D|-P|-n|-Q|-N] -R <step> [-c] [-o <path>] [-O]"
 lineBreak
 echo "-r # Force RDAC selection, BETA"
 echo "-p # Force POWERPATH selection"
 echo "-D # Force DATAPATH selection, BETA"
 echo "-P # Force PCMPATH selection, BETA"
 echo "-n # Force NATIVEMPIO selection, BETA"
 echo "-Q # Force HP/Qlogic selection, BETA"
 echo "-N # Force NOSAN selection"
 lineBreak
 echo "-R <step> # What step to run/start at"
 echo "############# Available steps: ############"
 echo "ALLSTEPS		# This will run all steps in the default sequence"
 echo "MSE		# ALLSTEPS without ASM or HPM checks"
 echo "ORACLE		# ALLSTEPS without MSE or HPM checks"
 echo "HPM		# ALLSTEPS without MSE checks, setupREPO, and OracleKickstartDetails"
 echo "############## ALLSTEPS Sequence ############"
 echo "createODIR		# Creates output directory"
 echo "checkOS			# Checks for a supported OS"
 echo "checkSAN		# Checks for a supported SAN"
 echo "fdiskAll		# Gathers fdisk -l output for all devices"
 echo "procPartitons		# Gathers /proc/partitions output"
 echo "validateFileSystems	# Gathers file system details"
 echo "extractLunmap		# Extracts lun_map_utils if found"
 echo "copyFiles		# Copies configuration files to ${ODIR}/backup-files"
 echo "miscChecks		# Misc checks applicable to the specific OS"
 echo "checkASMDisks		# Gathers details of ASM volumes"
 echo "setupREPO		# Sets up the yum repositories"
 echo "checkLVM		# Checks LVM for SAN LUNs in use"
 echo "checkSwaps		# Checks swap spaces for SAN LUNs in use"
 echo "checkORACLEASM		# Checks /etc/sysconfig/oracleasm settings"
 echo "checkMessagesFileScsiErrors	# Checks /var/log/messages for scsi errors"
 echo "checkDeadSANPaths	# Checks appropriate SAN driver for dead paths"
 echo "checkMSEVols	# Gathers details of MSE Volumes"
 echo "checkMSEvg	# Gathers details of MSE Volume Groups"
 echo "checkMSEkernel	# Checks various MSE upgrade parameters per README"
 echo "checkMSEErrors	# Checks for MSE internal errors"
 echo "OracleKickstartDetails # Gathers details for Oracle kickstarts"
 echo "getTSM		# Gathers details for TSM"
 echo "getHPMVer	# Gathers HPM application version"
 echo "disableRHNPlugin # Disables RHN plugin, applies to HPM only"
 echo "finalize		# Displays log details from most recent run"
 echo "############## Misc Steps ############"
 echo "cleanUp			# Cleans everything from ${ODIR}"
 lineBreak
 echo "-d 		# Set DEBUG mode (set -x)"
 echo "-o <path>	# Set ODIR=<path>, default ${ODIR}"
 echo "-O		# Override OS safety check, allows to run on unsupported OS"
 echo "-c		# required to force cleanUp step"
 echo "-h		# print this help"
 lineBreak
}

cleanUp()
{
 debug && set -x

 if [ "${CLEANUP}" = "true" ]; then
  echo "Removing ${ODIR}"
  rm -rf ${ODIR}
  echo "Removing ${LOG}"
  rm -f ${LOG}
  echo "Removing /tmp/$(hostname)-pre-check.log"
  rm -f /tmp/$(hostname)-pre-check.log
  lineBreak
 else
  echo "Clean up requires the -c switch as well"
  usage
 fi
}

# Function to kick off the entire process
main()
{
 setVars $* && SUCCESS=true || SUCCESS=false
 runStep ${STEP}
}

# This function allows us to run through the specified steps
# as well as any dependent steps. Various groupings of steps will
# be created to assist with specific project workflows, but in
# most cases all steps can be run via ALLSTEPS
runStep()
{
 debug && set -x

 if [ "${STEP}" = "ALLSTEPS" ]; then
  STEPLIST="createODIR checkOS checkSAN fdiskAll procPartitions validateFileSystems extractLunmap gatherSANDetails copyFiles miscChecks checkASMDisks setupREPO checkLVM checkSwaps checkORACLEASM checkMessagesFileScsiErrors checkDeadSANPaths checkMSEVols checkMSEvg checkMSEKernel checkMSEErrors OracleKickstartDetails getTSM getHPMVer finalize"
 elif [ "${STEP}" = "HPM" ]; then
  STEPLIST="createODIR checkOS checkSAN fdiskAll procPartitions validateFileSystems extractLunmap gatherSANDetails copyFiles miscChecks checkASMDisks checkLVM checkSwaps checkORACLEASM checkMessagesFileScsiErrors checkDeadSANPaths getTSM getHPMVer disableRHNPlugin finalize"
 elif [ "${STEP}" = "ORACLE" ]; then
  STEPLIST="createODIR checkOS checkSAN fdiskAll procPartitions validateFileSystems extractLunmap gatherSANDetails copyFiles miscChecks checkASMDisks setupREPO checkLVM checkSwaps checkORACLEASM checkMessagesFileScsiErrors checkDeadSANPaths OracleKickstartDetails getTSM finalize"
 elif [ "${STEP}" = "MSE" ]; then
  STEPLIST="createODIR checkOS checkSAN fdiskAll procPartitions validateFileSystems extractLunmap gatherSANDetails copyFiles miscChecks setupREPO checkLVM checkSwaps checkMessagesFileScsiErrors checkDeadSANPaths checkMSEVols checkMSEvg checkMSEKernel checkMSEErrors getTSM finalize"
 elif [ "${STEP}" = "createODIR" ]; then
  STEPLIST="createODIR finalize"
 elif [ "${STEP}" = "none" ]; then
  echo "You must specify a step to execute. Usage follows..."
  usage; exit 1
 elif [ "${STEP}" = "checkASMDisks" ]; then
  STEPLIST="createODIR checkOS checkSAN gatherSANDetails checkASMDisks finalize"
 elif [ "${STEP}" = "finalize" ]; then
  STEPLIST="finalize"
 elif [ "${STEP}" = "cleanUp" ]; then
  STEPLIST="cleanUp"
 else
  STEPLIST="createODIR ${STEP} finalize"
 fi
 
 lineBreak
 echo "Now executing the following steps: ${STEPLIST}"
 lineBreak

 for step in ${STEPLIST}
 do
  export step
  ${step}
 done
}

# This function coordinates displaying the output of all steps.
# This allows us to have a uniform look to all output and a centralized
# location to get information from. All output is stored in individualized
# log files for each step, in ${ODIR}/adv-srv-${step}.out. This
# is concattenated into a verbose log, while a brief success/failure
# message is displayed directly.
displayOutput()
{
 debug && set -x

 export SUCCESS=$1
 export MSG="$2"
 export OUTPUTFILE=${ODIR}/adv-srv-${step}.out
 if [ ${SUCCESS} = "true" ]; then
  echo "${MSG}......SUCCESS"
 else
  echo "${MSG}......FAILURE"
 fi
 lineBreak >>${LOG}
 echo "#### Output of ${step}, via ${OUTPUTFILE} ####" >>${LOG}
 cat ${OUTPUTFILE} >>${LOG}
 lineBreak >>${LOG}
}

keepWorking()
{
 debug && set -x

 export SUCCESS=false
 lineBreak
 echo "#### Output of $1 ####"
 case $1 in
  checkDeadSANPaths) echo "Check the below output for dead paths. If any are found a downtime is"
         echo " required to scan in new LUNs. The dead paths should also be reported"
         echo " to the SAN resource for investigation and correction"
         cat ${ODIR}/multipath-dead-paths.out;;
 esac
 echo "#### Completed $1, now executing $2 ####"
 lineBreak
 $2
 break
}

# This function creates an output directory to store gathered details in.
createODIR()
{
 debug && set -x

 rm -f ${LOG}

 mkdir -p ${ODIR} 2>&1 && SUCCESS=true || SUCCESS=false
 if [ ${SUCCESS} = "true" ]; then
  echo "Output directory, ${ODIR}, created succesfully" >${ODIR}/adv-srv-${step}.out 2>&1
 else
  echo "Unable to create output directory, ${ODIR}. Breaking for required step"
  exit 1
 fi
 displayOutput ${SUCCESS} "Creating output directory"
}

# On linux /proc/partitions contains details on all partitions seen by the kernel.
procPartitions()
{
 debug && set -x

 linux && echo "Now executing cat /proc/partitions. Details in " >${ODIR}/adv-srv-${step}.out 2>&1
 linux && echo "${ODIR}/procPartitions.out. Errors appear below" >>${ODIR}/adv-srv-${step}.out 2>&1
 linux && cat /proc/partitions >${ODIR}/procPartitions.out 2>>${ODIR}/adv-srv-${step}.out && SUCCESS=true || SUCCESS=false
 displayOutput ${SUCCESS} "Gathering /proc/partitions"
}

# Gather an fdisk -l output from all known devices.
fdiskAll()
{
 debug && set -x

 linux && echo "Now executing fdisk -l on all devices. Details in " >${ODIR}/adv-srv-${step}.out 2>&1
 linux && echo "${ODIR}/fdiskAll.out. Errors appear below" >>${ODIR}/adv-srv-${step}.out 2>&1
 linux && fdisk -l >${ODIR}/fdiskAll.out 2>>${ODIR}/adv-srv-${step}.out && SUCCESS=true || SUCCESS=false
 displayOutput ${SUCCESS} "Gathering fdisk -l on all disks"
}

# This function checks file systems and gathers details about them.
validateFileSystems()
{
 debug && set -x
 
 echo "Complete df output" >${ODIR}/adv-srv-${step}.out 2>&1
 (
  linux && df -k
  aix && df -k
  hpux && bdf -k
 ) | tee ${ODIR}/df.out >>${ODIR}/adv-srv-${step}.out 2>&1
 lineBreak >>${ODIR}/adv-srv-${step}.out 2>&1

 echo "All configured filesystems" >>${ODIR}/adv-srv-${step}.out 2>&1
 (
  linux && cat /etc/fstab | egrep -v '^$|^#|tmpfs|devpts|proc|swap|sysfs|vmhgfs' | awk '{print $2}'
  aix && cat /etc/filesystems | egrep -v '^$|^#|tmpfs|devpts|proc|swap|sysfs|vmhgfs' | egrep "^/.*:$" | awk -F':' '{print $1}'
  hpux && cat /etc/fstab | egrep -v '^$|^#|tmpfs|devpts|proc|swap|sysfs|vmhgfs' | awk '{print $2}'
 ) | sort | tee ${ODIR}/configured-filesystem-mountpoints.out >>${ODIR}/adv-srv-${step}.out 2>&1
 lineBreak >>${ODIR}/adv-srv-${step}.out 2>&1

 echo "All mounted filesystems" >>${ODIR}/adv-srv-${step}.out 2>&1
 (
  linux && df -P | grep -v 'Filesystem .*Mounted .*on' | egrep -v '^$|^#|tmpfs|devpts|proc|swap|sysfs|vmhgfs' | awk '{print $6}'
  aix && df | grep -v 'Filesystem .*Mounted .*on' | egrep -v '^$|^#|tmpfs|devpts|proc|swap|sysfs|vmhgfs' | awk '{print $7}'
  hpux && bdf | grep -v 'Filesystem .*Mounted .*on' | egrep -v '^$|^#|tmpfs|devpts|proc|swap|sysfs|vmhgfs' | awk '{print $6}'
 ) | sort | tee ${ODIR}/mounted-filesystems-pre.out >>${ODIR}/adv-srv-${step}.out 2>&1
 lineBreak >>${ODIR}/adv-srv-${step}.out 2>&1

 echo "Filesystems that are either: not mounted but configured, or mounted but not configured" >>${ODIR}/adv-srv-${step}.out 2>&1
 diff ${ODIR}/configured-filesystem-mountpoints.out ${ODIR}/mounted-filesystems-pre.out | egrep '<|>' | awk '{print $2}' |\
  sort | tee ${ODIR}/filesystems-configured-or-mounted-but-not-both.out >>${ODIR}/adv-srv-${step}.out 2>&1
 lineBreak >>${ODIR}/adv-srv-${step}.out 2>&1

 echo "Filesystems that should be mounted but are not" >>${ODIR}/adv-srv-${step}.out 2>&1
 cat ${ODIR}/filesystems-configured-or-mounted-but-not-both.out |\
 while read line
 do
  linux && grep "${line}" /etc/fstab | egrep -v 'noauto'
  aix && line2=$(echo "${line}" | tr '/' ' ')
  aix && cat /etc/filesystems | sed 's/\// /g'|sed -e '/./{H;$!d;}' -e 'x;/'"${line2}"':/!d;' |\
      egrep "mount.*automatic|mount.*true" >/dev/null && echo ${line}
  hpux && grep "${line}" /etc/fstab | egrep -v 'noauto'
 done | sort | tee ${ODIR}/filesystems-should-be-mounted-but-not.out >>${ODIR}/adv-srv-${step}.out 2>&1
 lineBreak >>${ODIR}/adv-srv-${step}.out 2>&1
 
 echo "OS Specific file systems checks" >>${ODIR}/adv-srv-${step}.out 2>&1
 aix && (
  LVLIST="$(for vg in $(lsvg)
  do
   lsvg -l ${vg}
  done |\
   egrep -v "^[a-z].*:|LV NAME|boot|paging|jfs2log|sysdump|nfs|jfslog|N/A" |\
   awk '{print $1}')"
  for lv in ${LVLIST}
  do
   lslv ${lv} >${ODIR:-/stage/rhel_minor_upgrade/$(hostname)}/lslv-${lv}.out
   LABEL="$(echo $(grep LABEL ${ODIR:-/stage/rhel_minor_upgrade/$(hostname)}/lslv-${lv}.out|awk -F':' '{print $3}'))"
   CORRECT=$(df ${LABEL} 2>/dev/null | grep -c ${lv})
   [[ ${CORRECT} -eq 1 ]] || echo "${lv} is labelled ${LABEL} but not mounted there"
  done
 ) | sort | tee ${ODIR}/aix-specific-filesystems-checks.out >>${ODIR}/adv-srv-${step}.out 2>&1
 linux && echo "No Linux specific checks defined" >>${ODIR}/adv-srv-${step}.out 2>&1
 hpux && echo "No HP-UX specific checks defined" >>${ODIR}/adv-srv-${step}.out 2>&1

 displayOutput true "File system details gathered"
}

# This function extracts a set of scripts grouped as lun_map_utils*.tar.gz
extractLunmap()
{
 # This set of scripts is provided by Clinical Support (SEteam) for documenting SAN details

 SUCCESS=true
 if [ $(ls -1 ${ODIR}/lun_map_utils*.tar.gz 2>/dev/null|wc -l) -gt 0 ]; then
  echo "Found $(ls -1 ${ODIR}/lun_map_utils*.tar.gz|tail -n 1), extracting..."
  tar xvzf $(ls -1 ${ODIR}/lun_map_utils*.tar.gz|tail -n 1) -C /
 elif [ $(ls -1 /stage/lun_map_utils*.tar.gz 2>/dev/null|wc -l) -gt 0 ]; then
  echo "Found $(ls -1 /stage/lun_map_utils*.tar.gz|tail -n 1), extracting..."
  tar xvzf $(ls -1 /stage/lun_map_utils*.tar.gz|tail -n 1) -C /
 elif [ $(ls -1 /ora_backup/lun_map_utils*.tar.gz 2>/dev/null|wc -l) -gt 0 ]; then
  echo "Found $(ls -1 /ora_backup/lun_map_utils*.tar.gz|tail -n 1), extracting..."
  tar xvzf $(ls -1 /ora_backup/lun_map_utils*.tar.gz|tail -n 1) -C /
 elif [ $(ls -1 /Cluster_Scripts/lun_map_utils*.tar.gz 2>/dev/null|wc -l) -gt 0 ]; then
  echo "Found $(ls -1 /Cluster_Scripts/lun_map_utils*.tar.gz|tail -n 1), extracting..."
  tar xvzf $(ls -1 /Cluster_Scripts/lun_map_utils*.tar.gz|tail -n 1) -C /
 elif [ $(ls -1 ${ODIR}/../lun_map_utils*.tar.gz 2>/dev/null|wc -l) -gt 0 ]; then
  echo "Found $(ls -1 ${ODIR}/../lun_map_utils*.tar.gz|tail -n 1), extracting..."
  tar xvzf $(ls -1 ${ODIR}/../lun_map_utils*.tar.gz|tail -n 1) -C /
 else
  echo "No lun_map_utils*.tar.gz found in /stage, /ora_backup, ${ODIR}, or ${ODIR}/../; Please upload and re-run or extract manually"
  SUCCESS=false
 fi >${ODIR}/adv-srv-${step}.out 2>&1
 
 displayOutput ${SUCCESS} "Extraction of lun_map_utils"
}

# This function gathers all details of the SAN environment
gatherSANDetails()
{
 debug && set -x

 SUCCESS=true
 case "true" in
  ${POWERPATH}) echo "Powermt display of all devices, available in ${ODIR}/powermt.before";
	powermt display dev=all >${ODIR}/powermt.before 2>&1;
	lineBreak;
	echo "PowerPath license details";
	emcpreg -list | tee ${ODIR}/pp.keys 2>&1;
	lineBreak;
	if [ -f /stage/mck_ks/bin/map_pp_pseudo2lun ]; then
	 echo "/stage/mck_ks/bin/map_pp_pseudo2lun found, executing";
	 /stage/mck_ks/bin/map_pp_pseudo2lun | tee ${ODIR}/map.pp 2>&1;
	else
	 echo "/stage/mck_ks/bin/map_pp_pseudo2lun not found, please extract lun_map_utils";
	fi;
	;;
  ${DATAPATH}) echo "Datapath query of all devices, available in ${ODIR}/datapath-query.out";
	datapath query device >${ODIR}/datapath-query.out 2>&1;
	lineBreak;
	;;
  ${RDAC}) linux && 
	(
	echo "mppUtil -a output, available in ${ODIR}/mppUtil-a.out";
	mppUtil -a >${ODIR}/mppUtil-a.out 2>&1;
	lineBreak;
	echo "mppUtil -g 0 output, available in ${ODIR}/mppUtil-g-0.out";
	mppUtil -g 0 >${ODIR}/mppUtil-g-0.out 2>&1;
	lineBreak;
	echo "lsvdev output";
	/opt/mpp/lsvdev | tee ${ODIR}/lsvdev.out 2>&1;
	)
	;;
  ${PCMPATH}) echo "Pcmpath query of all devices, available in ${ODIR}/pcmpath-query.out";
	pcmpath query device >${ODIR}/pcmpath-query.out 2>&1;
	;;
  ${NATIVEMPIO}) linux && 
	(
	echo "multipath verbose output, available in ${ODIR}/multipath-v2.out";
	multipath -v2 -ll >${ODIR}/multipath-v2.out 2>&1;
	)
	;;
  ${HPQLOGIC}) linux && 
	(
	echo "lssd -l output, available in ${ODIR}/lssd-l.out";
	lssd -l >${ODIR}/lssd-l.out 2>&1;
	lineBreak
	echo "parsed lssd output, available in ${ODIR}/lunmap.before"
	for device in $(lssd | awk '{print "/block/" $1}')
	do
	 echo "$(scsi_id -g -s $device) $(echo $device| sed 's/block/dev/g')"
	done | sort >${ODIR}/lunmap.before 2>&1
	lineBreak
	if [ -f /stage/mck_ks/bin/mapOraDevs_hpqla.sh ]; then
	 echo "/stage/mck_ks/bin/mapOraDevs_hpqla.sh found, executing (oradevs.before)";
	 /stage/mck_ks/bin/mapOraDevs_hpqla.sh >${ODIR}/oradevs.before;
	else
	 echo "/stage/mck_ks/bin/mapOraDevs_hpqla.sh not found, please extract lun_map_utils";
	fi
	)
	;;
  ${NOSAN}) echo "NOSAN selected, skipping san checks";;
  *) echo "No SAN type was detected automatically or specified on the command line.";
	echo "To gather SAN details a SAN type must be detected or forced";
	SUCCESS=false
	;;
 esac >${ODIR}/adv-srv-${step}.out 2>&1
 displayOutput ${SUCCESS} "All applicable SAN details gathered"
}

# This function copies all specified files for backup purposes
copyFiles()
{
 debug && set -x

 mkdir -p ${ODIR}/backup-files

 linux && FILES=''
 aix && FILES=''
 hpux && FILES=''

 echo "Creating tar bundle for /etc directory, verbose log in ${ODIR}/tar-etc.log" >${ODIR}/adv-srv-${step}.out 
 (
  linux && tar cvpzf ${ODIR}/backup-files/etc.tar.gz /etc
  aix && tar cvpf ${ODIR}/backup-files/etc.tar.gz /etc
  hpux && tar cvpf ${ODIR}/backup-files/etc.tar.gz /etc
 ) >${ODIR}/tar-etc.log 2>&1

 for file in ${FILES}
 do
  lineBreak >>${ODIR}/adv-srv-${step}.out 2>&1 
  if [ -f ${file} ]; then
   echo "Now copying ${file}"
   linux && cp -pLrv ${file} ${ODIR}/backup-files/
   aix && cp -r ${file} ${ODIR}/backup-files/
   hpux && cp -r ${file} ${ODIR}/backup-files/
   lineBreak
  else
   echo "${file} not found, skipping"
   lineBreak
  fi
 done >>${ODIR}/adv-srv-${step}.out 2>&1 2>&1

 displayOutput true "Backup of configuration files"
}

# This function is a collection of misc Linux specific checks
miscLinux()
{
 debug && set -x

 echo "RPM -qa output, details in ${ODIR}/rpm-qa.out" >${ODIR}/adv-srv-${step}.out
 rpm -qa >${ODIR}/rpm-qa.out 2>&1

 echo "ps auxww output, details in ${ODIR}/ps-auxww.out" >>${ODIR}/adv-srv-${step}.out
 ps auxww >${ODIR}/ps-auxww.out 2>&1

 displayOutput true "Misc. Linux checks"
}

# This function is a collection of misc AIX specific checks
aixMisc()
{
 true
}

# This function is a collection of misc HP-UX specific checks
hpuxMisc()
{
 true
}

# Run appropriate misc checks.
miscChecks()
{
 debug && set -x

 linux && miscLinux
 aix && miscAIX
 hpux && miscHPUX
}

InstalledASM()
{
 debug && set -x

 linux && if [ -f /etc/init.d/oracleasm ]; then
  return 0
 else
  return 1
 fi
}

checkASMDisks()
{
 debug && set -x

 InstalledASM && ASM=true || ASM=false

 if [ ${ASM} = "true" ]; then
 case ${OS} in
 Linux) for disk in $(service oracleasm listdisks)
   do
    line=$(ls -lrt /dev/oracleasm/disks/${disk})
    #line=$(find /dev -follow -name "${disk}" -exec ls -lrt {} \; 2>/dev/null)
    MAJOR=$(echo $line |awk '{print $5, $6}'|awk -F',' '{print $1}')
    MINOR=$(echo $line |awk '{print $6}')
    echo $line
    if ${POWERPATH}; then
     DEV=$(ls -lrt /dev|grep " ${MAJOR}, *${MINOR} ")
     device=$(echo ${DEV}|awk '{print $NF}'|awk -F'[0-9]' '{print $1}')
     echo ${DEV}
     ## PowerPath (EMC using emcpower devices)
     powermt display dev=${device}
    elif ${DATAPATH}; then
     DEV=$(ls -lrt /dev|grep " ${MAJOR}, *${MINOR} ")
     device=$(echo ${DEV}|awk '{print $NF}'|awk -F'[0-9]' '{print $1}')
     echo ${DEV}
     ## Datapath (ibm sdd using vpath devices)
     DEVICENUM=$(grep ${device} ${ODIR}/datapath-query.out |awk '{print $2}')
     datapath query device ${DEVICENUM} | egrep -v '^$'
     echo ""
    elif ${NATIVEMPIO}; then
     ## Native MPIO uses mapper/mpath devices
     MPATHDEV=$(ls -lrt /dev/mapper|grep " ${MAJOR}, *${MINOR} "|awk '{print $NF}' |awk -F'p[0-9]' '{print $1}' )
     if [ "x" = "x${MPATHDEV}" ]; then
      echo "MPATH Device not in use for this volume, trying to find sd* device"
      ls -lrt /dev|grep " ${MAJOR}, *${MINOR} "
     else
      multipath -v2 -l ${MPATHDEV}
     fi
    elif ${HPQLOGIC}; then
     ## HP/Qlogic uses sd* devices directly
     DEV=$(ls -lrt /dev|grep " ${MAJOR}, *${MINOR} ")
     device=$(echo ${DEV}|awk '{print $NF}'|awk -F'[0-9]' '{print $1}')
     lssd -l | grep ${device}
    elif ${RDAC}; then
     DEV=$(ls -lrt /dev|grep " ${MAJOR}, *${MINOR} ")
     device=$(echo ${DEV}|awk '{print $NF}'|awk -F'[0-9]' '{print $1}')
     echo ${DEV}
     /opt/mpp/lsvdev | grep ${device}
     echo ""
    elif ${NOSAN}; then
     ls -lrt /dev|grep " ${MAJOR}, *${MINOR} "
     echo "NOSAN detected, so devices need to be manually verified"
     echo ""
    else
     echo "No method to determine multipath device for this SAN type"
    fi
   done
  ;;
  AIX) echo "TODO" # no details for this OS for this check
  ;;
  HP-UX) echo "TODO" # no details for this OS for this check
  ;;
 esac
 else
  echo "ASM is not detected, all checks will need to be manually completed"
 fi >${ODIR}/adv-srv-${step}.out 2>&1 && SUCCESS=true || SUCCESS=false

 displayOutput ${SUCCESS} "Gathering ASM volume details"
}

setupREPO()
{
 debug && set -x

if [ -f /etc/yum.repos.d/mck_stage_dvd_extras.repo -o -f /etc/yum.repos.d/mck_stage_dvd_main.repo ]; then
 echo "/etc/yum.repos.d/mck_stage_dvd_extras.repo or /etc/yum.repos.d/mck_stage_dvd_main.repo already exists, not modifying"
else

cat >/etc/yum.repos.d/mck_stage_dvd_main.repo <<EOF
#----
# This is the McKesson HC Staging DVD location
# If it is not mounted here, yum may throw errors
#----
#[McKesson Stage DVD Main]
#name=Red Hat Linux - McKesson Stage DVD Main
#baseurl=file:///media/cdrecorder/RedHat/RPMS
EOF

cat >/etc/yum.repos.d/mck_stage_dvd_extras.repo <<EOF
#----
# This is the McKesson HC Staging DVD location
# If it is not mounted here, yum may throw errors
#----
#[McKesson Stage DVD Extras]
#name=Red Hat Linux - McKesson Stage DVD Extras
#baseurl=file:///media/cdrecorder/extras/software/oss
EOF

 echo 'yum repositories setup based on /media/cdrecorder. If that is not the
 location the media will be mounted to, please modify the files created
 in /etc/yum.repo.d. You will need to uncomment the files to use them.'
fi >${ODIR}/adv-srv-${step}.out

 displayOutput true "Create YUM repositories"
}

checkLVM()
{
 debug && set -x

 echo "All volume groups checked for SAN LUNs in vgdisplay -v output" >${ODIR}/adv-srv-${step}.out
 linux && case "true" in
  ${POWERPATH}) vgdisplay -v | grep emcpower;;
  ${DATAPATH}) vgdisplay -v | grep vpath;;
  ${RDAC}) vgdisplay -v | grep 'PV Name';;
  ${PCMPATH}) vgdisplay -v | grep vpath;;
  ${NATIVEMPIO}) vgdisplay -v | egrep 'dm-|mpath';;
  ${HPQLOGIC}) vgdisplay -v | grep 'PV Name';;
  ${NOSAN}) echo "NOSAN set to true, check skipped";;
 esac >>${ODIR}/adv-srv-${step}.out 2>&1
 aix && case "true" in
  ${POWERPATH}) echo "TODO";;
  ${DATAPATH}) echo "TODO";;
  ${RDAC}) echo "TODO";;
  ${PCMPATH}) echo "TODO";;
  ${NATIVEMPIO}) echo "TODO";;
  ${NOSAN}) echo "NOSAN set to true, check skipped";;
 esac >>${ODIR}/adv-srv-${step}.out 2>&1
 hpux && case "true" in
  ${POWERPATH}) echo "TODO";;
  ${DATAPATH}) echo "TODO";;
  ${RDAC}) echo "TODO";;
  ${PCMPATH}) echo "TODO";;
  ${NATIVEMPIO}) echo "TODO";;
  ${NOSAN}) echo "NOSAN set to true, check skipped";;
 esac >>${ODIR}/adv-srv-${step}.out 2>&1

 displayOutput true "Check LVM for SAN LUNs"
}

checkSwaps()
{
 debug && set -x

 echo "Checking for SAN LUNs in swap space" >${ODIR}/adv-srv-${step}.out

 linux && cat /proc/swaps >${ODIR}/proc-swaps.out
 aix && lsps -a >${ODIR}/proc-swaps.out
 hpux && echo "TODO for HPUX" >>${ODIR}/adv-srv-${step}.out
 case "true" in
  ${POWERPATH}) egrep 'emcpower|hdiskpower' ${ODIR}/proc-swaps.out;;
  ${DATAPATH}) grep vpath ${ODIR}/proc-swaps.out;;
  ${RDAC}) cat ${ODIR}/proc-swaps.out;;
  ${PCMPATH}) grep vpath ${ODIR}/proc-swaps.out;;
  ${NATIVEMPIO}) egrep 'dm-|mpath' ${ODIR}/proc-swaps.out;;
  ${HPQLOGIC}) cat ${ODIR}/proc-swaps.out;;
  ${NOSAN}) cat ${ODIR}/proc-swaps.out;;
 esac >>${ODIR}/adv-srv-${step}.out
 
 displayOutput true "Check swap spaces for SAN LUNs"
}

checkORACLEASM()
{
 debug && set -x

 InstalledASM && ASM=true || ASM=false

 if [ ${ASM} = "true" ]; then
 linux && if [ ${HPQLOGIC} = "true" -o ${RDAC} = "true" ]; then
  echo "This check does not 'require' correction for this driver"
  echo "but can be corrected by setting the following:"
  echo " ORACLEASM_SCANORDER=\"sd\""
  echo " ORACLEASM_SCANEXCLUDE=\"\""
 elif [ ${DATAPATH} = "true" -o ${PCMPATH} = "true" ]; then
  echo "This check requires correction for proper failover. To correct this set the following:"
  echo " ORACLEASM_SCANORDER=\"vpath sd\""
  echo " ORACLEASM_SCANEXCLUDE=\"sd\""
 elif [ ${NATIVEMPIO} = "true" ]; then
  echo "This check requires correction for proper failover. To correct this set the following:"
  echo " ORACLEASM_SCANORDER=\"dm sd\""
  echo " ORACLEASM_SCANEXCLUDE=\"sd\""
 elif [ ${POWERPATH} = "true" ]; then
  echo "This check requires correction for proper failover. To correct this set the following:"
  echo " ORACLEASM_SCANORDER=\"emcpower sd\""
  echo " ORACLEASM_SCANEXCLUDE=\"sd\""
 elif [ ${NOSAN} = "true" ]; then
  echo "This check would be a completely custom setup, specific to the environment (NOSAN)"
 fi
 lineBreak
 linux && echo "You should see the current SCANORDER and SCANEXCLUDE settings below."
 linux && echo "If they do not match the recommended settings above, a correction is required."
 linux && echo "This will require a downtime to correct in most situations."
 linux && egrep 'SCANORDER=|SCANEXCLUDE=' /etc/sysconfig/oracleasm
 else
  echo "ASM is not detected, all checks will need to be manually completed"
 fi >${ODIR}/adv-srv-${step}.out 2>&1

 displayOutput true "Check /etc/sysconfig/oracleasm"
}

checkMessagesFileScsiErrors()
{
 debug && set -x

 echo "Check the below output for anything that may impact an event" >${ODIR}/adv-srv-${step}.out 2>&1
 echo " such as scsi errors on lun devices. ">>${ODIR}/adv-srv-${step}.out 2>&1
 linux && egrep 'Buffer|scsi|SCSI' /var/log/messages | tail >>${ODIR}/adv-srv-${step}.out

 displayOutput true "Check for scsi errors"
}

checkDeadSANPaths()
{
 debug && set -x

 echo "Check the below output for dead paths. If any are found a downtime is" >${ODIR}/adv-srv-${step}.out 2>&1
 echo " required to scan in new LUNs. The dead paths should also be reported" >>${ODIR}/adv-srv-${step}.out 2>&1
 echo " to the SAN resource for investigation and correction" >>${ODIR}/adv-srv-${step}.out 2>&1
 lineBreak >>${ODIR}/adv-srv-${step}.out 2>&1

 case "true" in
  ${POWERPATH}) powermt display dev=all|grep 'SP [A-Z][0-9]'|grep -v 'active  alive';;
  ${DATAPATH}) datapath query device |grep 'Host[0-9]Channel[0-9]'|grep -v NORMAL;;
  ${RDAC}) SANID=$(mppUtil -a|grep -A 2 '^ID'|tail -n 1|awk '{print $1}');
   NUMPATHS=$(mppUtil -g $SANID|grep DevSta|grep -vc OPTIMAL);
   echo "Number of non-optimal paths: ${NUMPATHS}";;
  ${PCMPATH}) pcmpath query device | grep 'Host[0-9]Channel[0-9]'|grep -v NORMAL;;
  ${NATIVEMPIO}) linux && multipath -v2 -ll|grep '^ \\_'|grep -v '\[active\]\[ready\]';;
  ${HPQLOGIC}) echo "This must be manually checked, as this driver does not monitor inactive paths, and is strictly failover, not load balanced"
           echo " Please report to the Advanced Service team how you perform this check";;
  ${NOSAN}) echo "No dead paths on NOSAN";;
 esac >>${ODIR}/adv-srv-${step}.out 2>&1
 
 displayOutput true "Check for dead paths on SAN"
}

InstalledMSE()
{
 debug && set -x

 linux && if [ -f /hbo/etc/defaultdbname ]; then
  return 0
 else
  return 1
 fi
}

checkMSEVols()
{
 debug && set -x
 InstalledMSE && MSE=true || MSE=false

 if [ "${MSE}" = "false" ]; then
  echo "MSE does not appear to be installed here. Check /hbo/etc/defaultdbname" >${ODIR}/adv-srv-${step}.out 2>&1
 elif [ "${MSE}" = "true" ]; then
  source /hbo/etc/defaultdbname
  echo "Proceeding with MSE volume documentation in ${ODIR}/mse-volumes.out" >${ODIR}/adv-srv-${step}.out 2>&1
  ALLMSEVOLS="$(grep '\/dev\/.*[vbj]..a' ${DBNAME}.cfg|awk '{print $5}')"
  BILVOLS="$(grep '\/dev\/.*b..a' ${DBNAME}.cfg|awk '{print $5}')"
  JNLVOLS="$(grep '\/dev\/.*j..a' ${DBNAME}.cfg|awk '{print $5}')"
  MSEVOLS="$(grep '\/dev\/.*v..a' ${DBNAME}.cfg|awk '{print $5}')"
  lineBreak >>${ODIR}/adv-srv-${step}.out 2>&1
  echo "All logical volumes for MSE use:" >>${ODIR}/adv-srv-${step}.out 2>&1
  echo "${ALLMSEVOLS}" >>${ODIR}/adv-srv-${step}.out 2>&1
  lineBreak >>${ODIR}/adv-srv-${step}.out 2>&1
  echo "All details in ${ODIR}/mse-volume-details.out, errors below" >>${ODIR}/adv-srv-${step}.out 2>&1
  for vol in ${ALLMSEVOLS}
  do
   linux && lvdisplay ${vol}
   lineBreak
  done >>${ODIR}/all-mse-volumes-details.tmp 2>&1
  mv ${ODIR}/all-mse-volumes-details.tmp ${ODIR}/mse-volume-details.out >>${ODIR}/adv-srv-${step}.out 2>&1
 else
  echo "Not sure how we got to not true or false for InstalledMSE function" >${ODIR}/adv-srv-${step}.out 2>&1
 fi

 displayOutput true "Document MSE Vols"
}

checkMSEvg()
{
 debug && set -x

 InstalledMSE && MSE=true || MSE=false

 if [ "${MSE}" = "false" ]; then
  echo "MSE does not appear to be installed here. Check /hbo/etc/defaultdbname"
 elif [ "${MSE}" = "true" ]; then
  source /hbo/etc/defaultdbname
  echo "Proceeding with MSE VG documentation, details below"
  MSEVG="$(grep '\/dev\/.*b..a' ${DBNAME}.cfg|awk -F'/' '{print $3}'|sort | uniq)"
  for vg in  ${MSEVG}
  do
   lineBreak
   echo "Details of ${vg}:"
   linux && vgdisplay ${vg}
  done
 else
  echo "Not sure how we got to not true or false for InstalledMSE function"
 fi >${ODIR}/adv-srv-${step}.out 2>&1

 displayOutput true "Document MSE vg"
}

checkMSEKernel()
{
 debug && set -x
 #InstalledMSE && MSE=true || MSE=false
 # This check can proceed even if MSE is not "installed", i.e. on secondary nodes in a cluster
 MSE=true
 if [ "${MSE}" = "false" ]; then
  echo "MSE does not appear to be installed here. Check /hbo/etc/defaultdbname"
 elif [ "${MSE}" = "true" ]; then
  echo "Proceeding to check various MSE upgrade parameters"
  linux && lineBreak
  linux && echo "Checking kernel.sem = 256    3200    32      2048 (sysctl -q kernel.sem)"
  linux && sysctl -q kernel.sem|grep "256.*3200.*32.*2048" >/dev/null && echo true || echo false
  linux && echo "Checking kernel.shmmax > 134217728 (sysctl -q kernel.shmmax)" 
  linux && [[ $(sysctl -q kernel.shmmax|awk -F'=' '{print $2}') -ge 134217728 ]] && echo true || echo false
  linux && echo "Checking for sufficient disk space in /hbo (25kb)"
  linux && [[ $(df /hbo|tail -n 1|awk '{print $2}') -ge 25000 ]] && echo true || echo false
 else
  echo "Not sure how we got to not true or false for InstalledMSE function"
 fi >${ODIR}/adv-srv-${step}.out 2>&1
 displayOutput true "Checking MSE kernel options"
}

checkMSEErrors()
{
 debug && set -x
 InstalledMSE && MSE=true || MSE=false
 if [ "${MSE}" = "false" ]; then
  echo "MSE does not appear to be installed here. Check /hbo/etc/defaultdbname"
 elif [ "${MSE}" = "true" ]; then
  source /hbo/etc/defaultdbname
  echo "Now checking for MSE internal errors (/hbo/bin/mseverify -u1 -RO)"
  /hbo/bin/mseverify -u1 -RO | grep Errors
 else
  echo "Not sure how we got to not true or false for InstalledMSE function"
 fi >${ODIR}/adv-srv-${step}.out 2>&1
 displayOutput true "Checking for MSE internal Errors"
}

OracleKickstartDetails()
{
 debug && set -x

 linux && IPADDR=$(ping -c 1 $(hostname)|grep PING|awk -F'(' '{print $2}'|awk -F')' '{print $1}')
 HOSTNAME=$(hostname)
 linux && NETMASK=$(ifconfig -a|grep ${IPADDR}|awk -F':' '{print $4}')
 DEFAULTGW=$(netstat -nr|grep '^0.0.0.0'|awk '{print $2}')
 PDNS=$(cat /etc/resolv.conf | grep nameserver|head -n 1|tail -n 1|awk '{print $2}')
 SDNS=$(cat /etc/resolv.conf | grep nameserver|head -n 2|tail -n 1|awk '{print $2}')
 linux && AUTONEG=$(ethtool eth0|grep 'Adver'|grep auto|awk '{print $3}')
 if [ "${AUTONEG}" = "Yes" ]; then
  SPEED="AUTO"
 else
  SPEED=$(ethtool eth0|grep 'Speed:'|awk '{print $2}')
 fi
 DOMAIN=$(cat /etc/resolv.conf | grep domain|awk '{print $2}')
 SEARCH=$(cat /etc/resolv.conf | grep search|cut -d " " -f 2-)
 NTPS=$(grep ^server /etc/ntp.conf|head -n 1|awk '{print $2}')
 MAILRELAY=$(grep ^DS /etc/mail/sendmail.cf|cut -c 3-)
 MOTD=$(cat /etc/motd)
 TZONE=$(date +%Z)
 if [ -f /etc/mck/rac.conf ]; then
  FILE=/etc/mck/rac.conf
  RACNODES=$(grep ^RAC_NODE\\[ ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
  RACPUBIPS=$(grep ^RAC_PUB ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
  VIRNODES=$(grep ^RAC_NODE_VIR ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
  RACVIRIPS=$(grep ^RAC_VIR_IP ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
  INTNODES=$(grep ^RAC_NODE_INT ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
  RACINTIPS=$(for node in ${INTNODES}; do ping -c 1 $node|grep PING|awk -F'(' '{print $2}'|awk -F')' '{print $1}'; done|tr '\n' ' ')
  INTMASK=$(grep ^RAC_INT_NETMASK ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
  RACINSTANCES=$(grep ^RAC_DB ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
  ORABACKUP=$(grep /ora_backup /etc/fstab)
  echo "$IPADDR
  $HOSTNAME
  $NETMASK
  $DEFAULTGW
  $PDNS
  $SDNS
  $SPEED
  $DOMAIN
  $SEARCH
  $NTPS
  $MAILRELAY
  $MOTD
  $TZONE
  $RACNODES
  $RACPUBIPS
  $VIRNODES
  $RACVIRIPS
  $INTNODES
  $RACINTIPS
  $INTMASK
  $RACINSTANCES
  $ORABACKUP
  " >${ODIR}/adv-srv-${step}.out 2>&1
 elif [ -f /etc/mck/mck-environment.conf ]; then
  FILE=/etc/mck/mck-environment.conf
  CARELINKHOST=$(grep ^CARELINK_HOST ${FILE}|awk -F'=' '{print $2}')
  CARELINKIP=$(grep ^CARELINK_IP ${FILE}|awk -F'=' '{print $2}')
  RAC=$(grep ^RAC_EN ${FILE} | awk -F'=' '{print $2}')
  if [ "${RAC}" = "YES" ]; then 
   DBTYPE=RAC
   RACNODES=$(grep ^RAC_NODE\\[ ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
   RACPUBIPS=$(grep ^RAC_PUB ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
   VIRNODES=$(grep ^RAC_NODE_VIR ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
   RACVIRIPS=$(grep ^RAC_VIR_IP ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
   INTNODES=$(grep ^RAC_NODE_INT ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
   RACINTIPS=$(for node in ${INTNODES}; do ping -c 1 $node|grep PING|awk -F'(' '{print $2}'|awk -F')' '{print $1}'; done|tr '\n' ' ')
   INTMASK=$(grep ^RAC_INT_NETMASK ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
   RACINSTANCES=$(grep ^RAC_DB ${FILE} |awk -F'=' '{print $2}'|tr '\n' ' ')
   ORABACKUP=$(grep /ora_backup /etc/fstab)
   echo "$IPADDR
   $HOSTNAME
   $NETMASK
   $DEFAULTGW
   $PDNS
   $SDNS
   $SPEED
   $DOMAIN
   $SEARCH
   $NTPS
   $MAILRELAY
   $MOTD
   $TZONE
   N/A
   $DBTYPE
   $RACNODES
   $RACPUBIPS
   $RACINSTANCES
   ${CARELINKHOST}
   ${CARELINKIP}
   $ORABACKUP
   " >${ODIR}/adv-srv-${step}.out 2>&1
  else
   DBTYPE=Standalone
   echo "$IPADDR
   $HOSTNAME
   $NETMASK
   $DEFAULTGW
   $PDNS
   $SDNS
   $SPEED
   $DOMAIN
   $SEARCH
   $NTPS
   $MAILRELAY
   $MOTD
   $TZONE
   N/A
   $DBTYPE
   Lookup DB Hostnames for standalone - Notify Advanced Services to query env
   Lookup DB IP addresses for standalone - Notify Advanced Services to query env
   Lookup DB Instances for standalone - Notify Advanced Services to query env
   ${CARELINKHOST}
   ${CARELINKIP}
   $ORABACKUP
   " >${ODIR}/adv-srv-${step}.out 2>&1
  fi

 fi


 displayOutput true "Gather kickstart details"
}

getTSM()
{
 debug && set -x

 FILES='/opt/tivoli/tsm/client/api/dsm.sys /opt/tivoli/tsm/client/api/dsm.opt /opt/tivoli/tsm/client/ba/bin/dsm.sys /opt/tivoli/tsm/client/ba/bin/dsm.opt'
 if [ -f /opt/tivoli/tsm/client/ba/bin/dsm.sys -o -f /opt/tivoli/tsm/client/ba/bin/dsm.opt ]; then
  tar cvzf ${ODIR}/backup-files/tsm.tar.gz ${FILES}
  rpm -qa | grep TIV
 else
  echo "TSM config files not found, skipping"
 fi >${ODIR}/adv-srv-${step}.out 2>&1

 displayOutput true "Gather TSM details"
}

getHPMVer()
{
 debug && set -x
 
 if [ -d /apg ]; then
  echo "HPM Application version is: $(cat /apg/pdsver.dat)"
 else
  echo "HPM directory not found (/apg)"
 fi >${ODIR}/adv-srv-${step}.out 2>&1

 displayOutput true "Gather HPM Version"
}

disableRHNPlugin()
{
 debug && set -x

PLUGINDIR=/etc/yum/pluginconf.d
plugin=rhnplugin.conf
BAKDIR=${ODIR}/backup-files
if [ -d ${PLUGINDIR} ]
then
 mkdir -p ${BAKDIR}
 echo "Disabling ${plugin}"
 cp -f ${PLUGINDIR}/${plugin} ${BAKDIR}/${plugin}
 cat ${BAKDIR}/${plugin} | sed 's/enabled.*=.*1/enabled = 0/' >${PLUGINDIR}/${plugin}
 echo "${plugin} configuration:"
 cat ${PLUGINDIR}/${plugin}
 echo
else
 echo "RHN plugin not found"
fi >${ODIR}/adv-srv-${step}.out 2>&1

displayOutput true "Disable RHN plugin"
}

# This function copies the logs to ${ODIR}.
finalize()
{
 debug && set -x

 lineBreak
 echo "All pre-checks have been completed. Please copy each relavent section into"
 echo " the plan for documentation and manually run any required steps."
 lineBreak
 cp /tmp/$(hostname)-pre-check.log ${ODIR}/$(hostname)-pre-check.log
 cp /tmp/$(hostname)-adv-pre.log ${ODIR}/$(hostname)-adv-pre.log
}

main $* 2>&1 | tee /tmp/$(hostname)-pre-check.log
if [ -f /tmp/$(hostname)-adv-pre.log ]; then
 echo "Press enter to display the log at /tmp/$(hostname)-adv-pre.log (ctrl+c to break)"
 read continue
 more /tmp/$(hostname)-adv-pre.log
fi
