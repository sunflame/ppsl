#!/bin/ksh

aix()
{
# function checks if this is running on aix
if [ ${OS} = "AIX" ]; then
 return 0
else
 return 1
fi
}

hpux()
{
# function checks if this is running on hp-ux
if [ ${OS} = "HP-UX" ]; then
 return 0
else
 return 1
fi
}

linux()
{
# function checks if this is running on linux
if [ ${OS} = "Linux" ]; then
 return 0
else
 return 1
fi
}

setVars()
{
 POWERPATH=false
 RDAC=false
 DATAPATH=false
 PCMPATH=false
 NATIVEMPIO=false
 HPQLOGIC=false
 DEBUG=false
 ODIR=/stage/managed-services/$(hostname)
 OS="$(uname -s)"
 CONTINUE=false
 SUCCESS=false
 SHUTDOWN=false
 STEP=none
 IGNOREERRORS=false
 MIGRATION=false

 while getopts ":rpDQPndo:OCSR:IM" options; do
  case ${options} in
   r) RDAC=true;;
   p) POWERPATH=true;;
   D) DATAPATH=true;;
   P) PCMPATH=true;;
   n) NATIVEMPIO=true;;
   Q) HPQLOGIC=true;;
   d) DEBUG=true; set -x;;
   o) ODIR="${OPTARG}";;
   O) OS=OVERRIDE;;
   C) CONTINUE=true;;
   S) SHUTDOWN=true;;
   R) STEP=${OPTARG};;
   I) IGNOREERRORS=true;;
   M) MIGRATION=true;;
   h|\?|:|*) usage;exit 1;;
  esac
 done

 case ${OS} in
  Linux) SUPPORTEDOS=true;;
  AIX|HP-UX) echo "${OS} is in BETA, please override to continue anyway"; usage;;
  OVERRIDE) SUPPORTEDOS=true;;
  *) SUPPORTEDOS=false; echo "Running on unsupported OS (${OS}), please override to continue anyway"; usage;;
 esac

 if [ ${NATIVEMPIO} = "true" ]; then
  true
 elif [ ${PCMPATH} = "true" ]; then
  true
 elif [ ${POWERPATH} = "true" ]; then
  true
 elif [ ${DATAPATH} = "true" ]; then
  true
 elif [ ${RDAC} = "true" ]; then
  true
 elif [ ${HPQLOGIC} = "true" ]; then
  true
 elif [ -x "$(which powermt 2>/dev/null)" -o ${POWERPATH} = "true" ]; then
  POWERPATH=true
 elif [ -x "$(which datapath 2>/dev/null)" -o ${DATAPATH} = "true" ]; then
  DATAPATH=true
 elif [ -x "$(which mppUtil 2>/dev/null)" -o ${RDAC} = "true" ]; then
  RDAC=true
 elif [ -x "$(which lssd 2>/dev/null)" -o ${HPQLOGIC} = "true" ]; then
  HPQLOGIC=true
 elif [ -x "$(which pcmpath 2>/dev/null)" -o ${PCMPATH} = "true" ]; then
  PCMPATH=true
 else
  echo "No supported SAN multipath drivers detected, please force a selection"
  usage
 fi

 mkdir -p ${ODIR} && SUCCESS=true || SUCCESS=false
 getRACNodes
 getSecondaryNodes
}

lineBreak()
{
 echo "################################################################################"
}

usage()
{
 lineBreak
 echo "This script is designed to perform all work required for ASM LUN configuration"
 lineBreak
 echo "./$(basename $0) [-r|-p|-D|-P|-n|-Q] [-d] [-o <path>] [-h] [-O] [-S] [-I] [-C] -R <step> [-M]"
 lineBreak
 echo "-r # Force RDAC selection, BETA"
 echo "-p # Force POWERPATH selection"
 echo "-D # Force DATAPATH selection, BETA"
 echo "-P # Force PCMPATH selection, BETA"
 echo "-n # Force NATIVEMPIO selection, BETA"
 echo "-Q # Force HP/Qlogic selection, BETA"
 lineBreak
 echo "-d # Set DEBUG mode"
 echo "-o <path> # Set ODIR=<path>"
 echo "-O # Override OS safety check, allows to run on unsupported OS"
 echo "-S # Shutdown CRS stack to perform new lun scan"
 echo "-C # Continue on to next step automatically"
 echo "-I # Ignore errors and continue"
 echo "-M # Set MIGRATION mode"
 echo "-h # print this help"
 lineBreak
 echo "-R <step> # What step to run/start at"
 echo "#### Available steps: ####"
 echo "disableInittab # begins with step #2a of the project plan"
 echo "               #  disabling h[123] entries in /etc/inittab."
 echo "               # Will continue to step #2b with -C"
 echo "shutdownRAC # begins with step #2b of the project plan"
 echo "            #  shutting down the RAC environment and disabling CRS"
 echo "            # Will continue to step #3 with -C"
 echo "scanNewLUNs # begins with step #3 of the project plan"
 echo "            #  scanning new LUNs into the server. This must be run"
 echo "            #  on all nodes. Will not continue"
 echo "enableInittab # Will enable entries disabled by disableInittab step"
 echo "              # Will re-read inittab afterwards, starting CRS automatically"
 echo "checkDiskHeaders # begins with step #6 of the project plan"
 echo "                 #  verifying the new LUNs are seen properly"
 echo "                 # Will not continue"
 echo "buildASMLISTvariable # builds a list of all unpartitioned devices"
 echo "                     # This list is used to partition devices"
 lineBreak
 if [ "${DEBUG}" = "true" ]; then
  set
 fi
 exit 1
}

main()
{
 setVars $* && SUCCESS=true || SUCCESS=false
 echo ${STEP}
 linux && keepWorking setVars ${STEP}
 if [ "${DEBUG}" = "true" ]; then
  set
 fi
}

moveOn()
{
 if [ ${CONTINUE} = "true" ]; then
  return 0
 else
  return 1
 fi
}

keepWorking()
{
 export prevStep=$1
 export nextStep=$2
 lineBreak
 echo "#### Output of ${prevStep} ####"
 case ${prevStep} in
  setVars) case "true" in
    ${POWERPATH}) echo "PowerPath detected, setting POWERPATH=true";;
    ${DATAPATH}) echo "Datapath detected, setting DATAPATH=true";;
    ${RDAC}) echo "RDAC (mppUtil) detected, setting RDAC=true";;
    ${PCMPATH}) echo "pcmpath detected, setting PCMPATH=true";;
    ${NATIVEMPIO}) echo "NativeMPIO forced, setting NATIVEMPIO=true";;
    ${HPQLOGIC}) echo "HP/Qlogic detected, setting HPQLOGIC=true";;
   esac;;
  checkDiskHeaders) echo "Disk headers for all devices matching the current multipath type:"
                    cat ${ODIR}/fdisk-disk-header.out;;
  scanNewLUNs) echo "New LUNs have been scanned (if possible). See output for details:"
               cat ${ODIR}/scan-new-luns.out;;
  buildASMLISTvariable) cat ${ODIR}/buildASMLIST.out
                moveOn && echo "Please press enter if ready to continue,"
                moveOn && echo " otherwise Ctrl+C to break out"
                moveOn && read answer;;
  updateUdevPermissions) /stage/mck_ks/bin/chmod_oracle_devices.sh -f ${ODIR}/ASMDISKS;;
  buildRawDevices) echo "New raw devices have been built. /etc/sysconfig/rawdevices has been updated. Use -M during updateSecondaryNodes to ensure it is transfered";;
  updateDevices) echo "Remember to run 'service oracleasm scandisks' on all nodes if you are not going to use this script to perform the createASMVOLS step."
 esac
 lineBreak
 if [ ${SUCCESS} = "true" -o ${IGNOREERRORS} = "true" ]; then
  export SUCCESS=false
  $nextStep
 else
  echo "Failure at ${prevStep}, see above"
 fi
 finalize
}

finalize()
{
 exit 0
}

enableInittab()
{
 echo "Getting list of RAC nodes"
 getRACNodes
cat >/tmp/enable-inittab.sh.copy <<EOF
 if [ $(grep -c '^h[123]:' /etc/inittab) -eq 3 ]; then
  echo "h[123] entries are already enabled, please verify they are working"
  echo " correctly in another shell, then press enter to continue, or Ctrl+C to quit"
  read answer
 elif [ -f /etc/inittab.adv.bak ]; then
   cp -f /etc/inittab.adv.bak /etc/inittab
   telinit q
   /etc/init.d/init.crs start
 else
  echo "Unable to locate /etc/inittab.adv.bak, which should have been created by"
  echo " this script when disabling h[123] entries in /etc/inittab. Please re-enable"
  echo " the h[123] entries manunally and then continue running this script. This"
  echo " script will detect that they are enabled and continue past this point automatically"
  exit 1
 fi
EOF
  copyScript "/tmp/enable-inittab.sh.copy" ${NODELIST} &&\
  runScript "/tmp/enable-inittab.sh" ${NODELIST} && SUCCESS=true || SUCCESS=false
 moveOn && keepWorking enableInittab finalize
}

disableInittab()
{
 echo "Getting list of RAC nodes"
 getRACNodes

 if [ "${SHUTDOWN}" = false ]; then
  echo "Skipping disableInittab as shutdown is false, to force shutdown use -S"
 else
cat >/tmp/disable-inittab.sh.copy <<EOF
 if [ $(grep -c '^h[123]:' /etc/inittab) -ne 3 ]; then
  echo "h[123] entries appear to be disabled already, please verify they are not"
  echo " present in another shell, then press enter to continue, or Ctrl+C to quite"
  read answer
 else
  cp -f /etc/inittab /etc/inittab.adv.bak && \
  grep -v '^h[123]:' /etc/inittab.adv.bak >/etc/inittab && \
  telinit q
 fi
EOF
  copyScript "/tmp/disable-inittab.sh.copy" ${NODELIST}
  runScript "/tmp/disable-inittab.sh" ${NODELIST}
 fi && SUCCESS=true || SUCCESS=false
 moveOn && keepWorking disableInittab shutdownRAC
}

getRACNodes()
{
 if [ -f /tmp/manual.node.list ]
 then
  export NODELIST="$(cat /tmp/manual.node.list)"
 else
  export NODELIST=$(su - oracle -c 'olsnodes')
 fi
}

getSecondaryNodes()
{
 if [ -f /tmp/secondary.node.list ]
 then
  export SECONDARYNODELIST=$(cat /tmp/secondary.node.list)
 else
  export SECONDARYNODELIST=$(su - oracle -c 'olsnodes|grep -v $(hostname)')
 fi
}

shutdownRAC()
{
 if [ "${SHUTDOWN}" = false ]; then
  echo "Skipping shutdownRAC as shutdown is false, to force shutdown use -S"
 else
  echo "Getting list of RAC nodes"
  getRACNodes

  cat >/tmp/shutdown-databases.sh.copy <<EOF
   DBLIST=\$( ps -ef|grep _smon|grep -v ASM|grep -v grep|awk '{print \$NF}'|awk -F'_' '{print \$NF}')
   for INSTANCE in \${DBLIST}
   do
    SID=\$(echo \${INSTANCE} | awk -F'1' '{print \$1}')
     su - oracle -c "srvctl stop instance -d \${SID} -i \${INSTANCE} -o immediate"
   done
   srvctl stop asm -n \$(hostname)
EOF

  copyScript "/tmp/shutdown-databases.sh.copy" ${NODELIST}
  runScript "/tmp/shutdown-databases.sh" ${NODELIST}
  runScript "/etc/init.d/init.crs stop" ${NODELIST}
  
 fi && SUCCESS=true || SUCCESS=false

 moveOn && keepWorking shutdownRAC finalize
}

copyScript()
{
 script=${1}
 shortName=$(echo ${script} | awk -F'.copy' '{print $1}')
 shift
 NODELIST="$*"
 echo "Will copy ${shortName} to the following nodes: ${NODELIST}"
 for node in ${NODELIST}
 do
  echo "Copying ${shortName} to ${node}"
  scp ${script} ${node}:${shortName}
  echo "Setting execute permissions on ${shortName} on ${node}"
  ssh ${node} "chmod +x ${shortName}"
  echo "Copied ${shortName} on ${node}"
 done
}

runScript()
{
 script="${1}"
 shift
 NODELIST="$*"
 echo "# Will execute ${script} on the following nodes: ${NODELIST}"
 for node in ${NODELIST}
 do
  echo "# Executing ${script} on ${node}: cat ${script}:"
  ssh ${node} "cat ${script}"
  lineBreak
  echo "#  Press enter to continue or Ctrl+c to break"
  read answer
  ssh ${node} "${script}"
  lineBreak
  echo "# Completed ${script} on ${node}"
  lineBreak
 done
}

scanNewLUNs()
{
 case "true" in
  ${POWERPATH}) linux && qlScan;;
  ${DATAPATH}) linux && qlScan;;
  ${RDAC}) linux && qlScan;;
  ${PCMPATH}) linux && qlScan;;
  ${NATIVEMPIO}) linux && qlScan;;
  ${HPQLOGIC}) linux && hpScan;;
 esac 2>&1 >${ODIR}/scan-new-luns.out && SUCCESS=true || SUCCESS=false

 keepWorking scanNewLUNs finalize
}

qlScan()
{
 if [ -f ${ODIR}/ql-dynamic-tgt-lun-disc-2.3.tgz ]; then
  tar xvzf ${ODIR}/ql-dynamic-tgt-lun-disc-2.3.tgz -C ${ODIR} &&
  SUCCESS=true
 else
  echo "We are not able to find ${ODIR}/ql-dynamic-tgt-lun-disc-2.3.tgz"
  echo " which is required to scan new LUNs"
  SUCCESS=false
 fi

 if [ ${SUCCESS} = "true" ]; then
  cd ${ODIR}/ql-dynamic-tgt-lun-disc-2.3
  ./ql-dyanmic-tgt-lun-disc.sh -s <<EOF
yes

EOF
 else
  SUCCESS=false
  exit 1
 fi && SUCCESS=true || SUCCESS=false
}

hpScan()
{
 if [ -f /opt/hp/hp_fibreutils/hp_rescan ]; then
  /opt/hp/hp_fibreutils/hp_rescan -a -n && SUCCESS=true || SUCCESS=false
 else
  echo "We are not able to find /opt/hp/hp_fibreutils/probe-luns"
  echo " which is required to scan new LUNs"
  SUCCESS=false
 fi

 if ${SUCCESS}; then
 true
 ##############
 else
  SUCCESS=false
  exit 1
 fi && SUCCESS=true || SUCCESS=false
}

getDefaultDevList()
{
 case "true" in
  ${POWERPATH}) linux && DEVLIST="/dev/emcpower[a-z] /dev/emcpower[a-z][a-z]"
	aix && DEVLIST="/dev/hdiskpower[0-9] /dev/hdiskpower[0-9][0-9]";;
  ${DATAPATH}) linux && DEVLIST="/dev/vpath[0-9] /dev/vpath[0-9][0-9]"
        aix && DEVLIST="/dev/vpath[0-9] /dev/vpath[0-9][0-9]";;
  ${RDAC}) linux && DEVLIST="/dev/sd[a-z] /dev/sd[a-z][a-z]"
	aix && DEVLIST="/dev/hdisk[0-9] /dev/hdisk[0-9][0-9]";;
  ${PCMPATH}) linux && DEVLIST="/dev/vpath[0-9] /dev/vpath[0-9][0-9]"
        aix && DEVLIST="/dev/vpath[0-9] /dev/vpath[0-9][0-9]";;
  ${NATIVEMPIO}) linux && DEVLIST="/dev/mapper/mpath[0-9] /dev/mapper/mpath[0-9][0-9] /dev/mapper/asm[0-9][0-9][0-9] /dev/mapper/ocr[0-9] /dev/mapper/voting[0-9]";;
  ${HPQLOGIC}) linux && DEVLIST="/dev/sd[a-z] /dev/sd[a-z][a-z]";;
 esac
}

checkDiskHeaders()
{
 getDefaultDevList

 linux && for dev in ${DEVLIST}
 do
  if [ -b "${dev}" ]; then
   fdisk -l ${dev} 2>&1 | grep Disk
  fi
 done >${ODIR}/fdisk-disk-header.out && SUCCESS=true || SUCCESS=false

 aix && for pv in $(lspv|grep hdiskpower|awk '{print $1}')
 do
  SIZE=$(bootinfo -s ${pv})
  NAME=${pv}
  LID=$(powermt display dev=${pv} | grep 'Logical device' |\
   awk -F'[' '{print $2}' | awk -F']' '{print $1}')
  echo "${NAME}\t${SIZE}\t${LID}"
 done >${ODIR}/fdisk-disk-header.out && SUCCESS=true || SUCCESS=false

 keepWorking checkDiskHeaders finalize
}

buildASMLISTtmp()
{
 rm -f ${ODIR}/ASMLIST.tmp
 for dev in ${DEVLIST}
 do
  if [ -b "${dev}" ]; then
   fdisk -l ${dev} >/dev/null 2>>${ODIR}/ASMLIST.tmp
  fi
 done
}

buildASMLISTinternal()
{
 ASMLIST="$(cat ${ODIR}/ASMLIST.tmp|grep -v '^#'|awk '{print $2}')"
}

buildASMLISTvariable()
{
 getDefaultDevList
 if [ -f ${ODIR}/ASMLIST.tmp ]; then
  true
 else
  buildASMLISTtmp
 fi && SUCCESS=true || SUCCESS=false
 buildASMLISTinternal
 echo "Verify contents of ASMLIST variable: " >${ODIR}/buildASMLIST.out
 echo ${ASMLIST} >>${ODIR}/buildASMLIST.out
 echo "# If the list contains devices that are not desired, edit "
 echo "#  ${ODIR}/ASMLIST.tmp and comment offending "
 echo "# If the list is missing devices, add them"
 
 moveOn && keepWorking buildASMLISTvariable partitionLUNs || keepWorking buildASMLISTvariable finalize
}

partitionASMLUN()
{
 ASMDISK="$1"
 echo "Now partitioning device: ${ASMDISK}."
 echo "Current configuration of: ${ASMDISK}"
 fdisk -l ${ASMDISK}
 echo "Press enter to continue, Ctrl+c to quit"
 read answer
 echo -e "n\np\n1\n\n\nt\n60\nw\n" | fdisk ${ASMDISK}
}

partitionLUNs()
{
 if [ -f ${ODIR}/buildASMLIST.out -a -f ${ODIR}/ASMLIST.tmp ]; then
  buildASMLISTinternal
 for ASMDISK in ${ASMLIST}
  do
   partitionASMLUN ${ASMDISK} && SUCCESS=true || SUCCESS=false
   if [ ${SUCCESS} = "false" ]; then
    echo "Failure partitioning device: ${ASMDISK}"
   fi
  done
 else
  echo "You have not run the buildASMLISTvariable step!!!!!!!!!!"
  echo " Please do so and re-run again."
 fi && SUCCESS=true || SUCCESS=false
 
 moveOn && keepWorking partitionLUNs updateUdevPermissions || keepWorking partitionLUNs finalize
}

getASMSIZE()
{
 ASMTMPSIZE=$(for dev in ${DEVLIST}
  do
   if [ -b "${dev}" ]; then
    fdisk -l ${dev} 2>/dev/null | grep Disk|awk '{print $3}'
   fi
  done | sort -nr | uniq |\
   while read line
   do
    echo -n "${line}|"
   done | rev | cut -b 2- | rev)

 echo "Please specify the size of all (new and old) ASM devices."
 echo "This should be in the format output by fdisk, ex: 68.7, 53.6, 34.3"
 echo "It can contian multiple entries seperated by a | (no spaces)"
 echo "example: 53.6|68.7|34.3, to match all three sizes"
 echo "Current gathered specs for all visible LUNs: ${ASMTMPSIZE}"
 read ASMSIZE
}

getASMDevList()
{
 getASMSIZE

 ASMDEVLIST=$(for dev in ${DEVLIST}
 do
  if [ -b "${dev}" ]; then
   fdisk -l ${dev} 2>/dev/null | grep Disk | egrep "${ASMSIZE}" | awk '{print $2}' | awk -F':' '{print $1}'
  fi
 done)
}

updateUdevPermissions()
{
 getDefaultDevList
 getASMDevList

 getAllPaths && SUCCESS=true || SUCCESS=false

 keepWorking updateUdevPermissions finalize
}

buildRawDevices()
{
 echo "# Please give the full device path of the 2 partition lun (OCR):"
 read DEVA
 if [ -b ${DEVA} ]; then
  echo "# Please confirm the device details below for the OCR LUN:"
  fdisk -l ${DEVA}
  echo "# If they do not refer to the correct device, press Ctrl+c and retry, otherwise press enter to continue."
  read mistake
  export DEVA
 else
  echo "# Device, ${DEVA}, does not exist or is not a block device"
  ls -lrt ${DEVA}
 fi && SUCCESS=true || SUCCESS=false
 echo "# Please give the full device path of the 3 partition lun (Voting):"
 read DEVB
 if [ -b ${DEVB} ]; then
  echo "# Please confirm the device details below for the Voting LUN:"
  fdisk -l ${DEVB}
  echo "# If they do not refer to the correct device, press Ctrl+c and retry, otherwise press enter to continue."
  read mistake
  export DEVB
 else
  echo "# Device, ${DEVB}, does not exist or is not a block device"
  ls -lrt ${DEVB}
 fi && SUCCESS=true || SUCCESS=false

 echo -e "n\np\n1\n\n+1024M\nn\np\n2\n\n+1024M\nt\n1\n60\nt\n2\n60\nw\n" | fdisk ${DEVA} && SUCCESS=true || SUCCESS=false

 echo -e "n\np\n1\n\n+1024M\nn\np\n2\n\n+1024M\nn\np\n3\n\n+1024M\nt\n1\n60\nt\n2\n60\nt\n3\n60\nw\n" | fdisk ${DEVB} && SUCCESS=true || SUCCESS=false
 
 cp /etc/sysconfig/rawdevices ${ODIR}/rawdevices.original

 case "true" in
  ${NATIVEMPIO}|${DATAPATH}|${PCMPATH}) FILLER="p";;
  ${POWERPATH}|${RDAC}) FILLER="";;
 esac

cat >>/etc/sysconfig/rawdevices <<EOF
# Oracle Voting device (7,9,11 or 1,3,5)
/dev/raw/raw7 ${DEVA}${FILLER}1
/dev/raw/raw9 ${DEVB}${FILLER}1
/dev/raw/raw11 ${DEVB}${FILLER}3
# Oracle OCR disks (8,10 or 2,4)
/dev/raw/raw8 ${DEVA}${FILLER}2
/dev/raw/raw10 ${DEVB}${FILLER}2
EOF

 sleep 3
 kpartx -v -a ${DEVA}
 sleep 3
 kpartx -v -a ${DEVB}

 sleep 3
 service rawdevices restart && SUCCESS=true || SUCCESS=false

 sleep 3
 for i in 7 9 11
 do
  chown oracle:dba /dev/raw/raw${i}
  chmod 660 /dev/raw/raw${i}
 done
 find /dev/raw/ -user oracle -type c -exec ls -lrt {} \;

 for i in 8 10
 do
  chown root:dba /dev/raw/raw${i}
  chmod 640 /dev/raw/raw${i}
 done
 find /dev/raw/ -user root -type c -exec ls -lrt {} \;

 moveOn && keepWorking buildRawDevices buildASMLISTvariable
}

getAllPaths()
{
for asmdev in ${ASMDEVLIST}
do

if ${POWERPATH}; then
# PowerPath
 powermt display dev=$(echo $asmdev | awk -F'/' '{print $NF}') |\
  egrep '^Pseudo|qla2xxx|lpfc' |\
  sed -e 's/=/ /g' | awk '{print "/dev/" $3 "1"}'

elif ${RDAC}; then
# RDAC
 echo ${asmdev}1

elif ${DATAPATH}; then
 # DataPath
 # TODO
 echo /dev/${asmdev}p1
 #datapath query device ${DEVNUM} | grep 'Host[0-9]Channel[0-9]' |\
 # awk '{print $2}'|awk -F'/' '{print "/dev/" $2 "1"}'

elif ${PCMPATH}; then
 # PCMPath
 # TODO
 echo ${asmdev}p1
 #pcmpath query device ${DEVNUM} | grep 'Host[0-9]Channel[0-9]' |\
 # awk '{print $2}'|awk -F'/' '{print "/dev/" $2 "1"}'

elif ${HPQLOGIC}; then
 echo ${asmdev}1

elif ${NATIVEMPIO}; then
 echo ${asmdev}p1
 for dev in $(multipath -v2 -ll $(echo ${asmdev}|awk -F'/' '{print $NF}')|grep 'active'|grep ready|awk '{print $3}')
 do
  echo "/dev/${dev}1"
 done

else
 echo "No known SAN type for device ${asmdev}, please configure manually" >/dev/stderr
fi 

done >${ODIR}/ASMDISKS

for disk in $(cat ${ODIR}/ASMDISKS)
do
 chown oracle:dba ${disk}
 chmod 664 ${disk}
done
}

getBindingsFile()
{
 if [ -f /etc/multipath.conf ]; then
  SPECIFIED=$(grep -c bindings_file /etc/multipath.conf)
 fi

 if [ ${SPECIFIED} -gt 0 ]; then
  export BINDINGSFILE=$(grep bindings_file /etc/multipath.conf | awk '{print $2}'|grep bindings)
 elif [ -f /var/lib/multipath/bindings ]; then
  export BINDINGSFILE=/var/lib/multipath/bindings
 else
  echo "Bindings file not specified and not found at default location."
  echo "Please configure bindings_file variable in /etc/multipath.conf"
  echo "or at default location, /var/lib/multipath/bindings"
 fi
}

sendFile()
{
 FILE="${1}"
 TARGET="${2}"
 cksum ${FILE}
 scp ${FILE} ${target}:${FILE}
 ssh ${TARGET} "cksum ${FILE}"
}

updateSecondaryNodes()
{
 getSecondaryNodes
 for target in ${SECONDARYNODELIST}
 do
  echo "# Updating configuration files on secondary node: ${target}"
  if ${SHUTDOWN}; then
   if ${POWERPATH}; then
   # PowerPath
    echo "# Updating PowerPath configuration files. For these to take effect, a reboot of the"
    echo "#  secondary node will be required"
    sendFile /etc/emcp_devicesDB.dat ${target}
    sendFile /etc/emcp_devicesDB.idx ${target}
   fi

   if ${NATIVEMPIO}; then
    getBindingsFile
    echo "# Updating NativeMPIO configuration files. For these to take effect, a reboot of the"
    echo "#  secondary node will be required"
    sendFile ${BINDINGSFILE} ${target}
   fi
 
   if [ ${MIGRATION} = "true" ]; then
    echo "# Updating /etc/sysconfig/rawdevices"
    sendFile /etc/sysconfig/rawdevices ${target}
   else
    echo "# Use -M to make updates for migrations"
   fi
  else
   echo "# Use -S to make updates requiring a downtime on secondary nodes:"
   echo "#  migrations"
   echo "#  updates to /etc/sysconfig/oracleasm (except when ASM vols already use multipath device)"
   echo "#  PowerPath when the devices names are not the same"
  fi

  if [ -f /etc/udev/permissions.d/10-oracle-devices.permissions ]; then
   echo "# Updating /etc/udev/permissions.d/10-oracle-devices.permissions"
   sendFile /etc/udev/permissions.d/10-oracle-devices.permissions ${target}
  fi

  if [ -f /etc/sysconfig/oracledevices ]; then
   echo "# Updating /etc/sysconfig/oracleasm"
   sendFile /etc/sysconfig/oracleasm ${target}
  fi

  if [ -f /etc/sysconfig/oracledevices ]; then
   echo "# Updating NativeMPIO oracledevices configuration file. For these to take effect, a reboot of the"
   echo "#  secondary node will be required"
   sendFile /etc/sysconfig/oracledevices ${target}
  fi
  lineBreak
 done && SUCCESS=true || SUCCESS=false

 keepWorking updateSecondaryNodes finalize
}

updateDevices()
{
 getSecondaryNodes

 
 cat >/tmp/updateDevices.sh.copy <<EOF
 if [ -f \${ODIR:-/tmp}/ASMLIST.tmp ]; then
  ASMLIST="\$(cat \${ODIR:-/tmp}/ASMLIST.tmp|awk '{print \$2}')"
  for dev in \$ASMLIST
  do
   echo "## About to re-write partition table of \${dev}"
   echo "## Press enter to continue or ctrl+c to quit"
   read continue
   echo "w\\n" | fdisk \${dev}
   chown oracle:dba \${dev}
  done
  echo "sleeping for 60 seconds to let LUNs settle after scan on \$(hostname)"
 else
  echo "You have not run the buildASMLISTvariable step!!!!!!!!!!"
  echo " Please do so and re-run again."
 fi
EOF

 copyScript "/tmp/updateDevices.sh.copy" ${SECONDARYNODELIST} &&\
 lineBreak && \
 echo && \
 if [ -f ${ODIR}/buildASMLIST.out -a -f ${ODIR}/ASMLIST.tmp ]; then
  buildASMLISTinternal
  echo "About run updateDevices, which is damaging to currently in use devices against the following devices. If this list is not accurate, DO NOT PROCEED. Stop and review the buildASMLISTvariable step. Re-run that step for guidance on correcting issues with it."
  echo "${ASMLIST}"
  echo "# If the list contains devices that are not desired, edit "
  echo "#  ${ODIR}/ASMLIST.tmp and comment offending "
  echo "# If the list is missing devices, add them"
  read pauseUpdateDevices
  runScript "/tmp/updateDevices.sh" ${SECONDARYNODELIST} && SUCCESS=true || SUCCESS=false
 else
  echo "You have not run the buildASMLISTvariable step!!!!!!!!!!"
  echo " Please do so and re-run again."
 fi 
 keepWorking updateDevices finalize
}

createASMVOLS()
{

 if [ -d /dev/oracleasm/disks ] ; then
  b=$(ls -l /dev/oracleasm/disks/|tail -n 1|awk '{print $NF}'|awk -F'0' '{print $NF}')
 else
  echo "# Unable to determine the volume number of the last ASM volume"
  echo "#  please provide it, or press ctrl+c"
  echo "## Set b to whatever the current volume number is for ASM"
  echo "## Do not include leading zeros (009 = 9)"
  read b
 fi

 if [ ${b} -gt 0 ]; then
  true
 else
  break
 fi

 if [ -f ${ODIR}/buildASMLIST.out ]; then
  buildASMLISTinternal
 if [ "x" = "x${ASMLIST}" ] ; then
  echo "ASMLIST variable is blank, no devices to label"
  echo "Check the output of buildASMLISTvariable step"
 else
  for asmdev in ${ASMLIST}
  do
   let b=b+1
   a=${b}
   case $a in
    [0-9]) a=00${a};;
    [1-9][0-9]) a=0${a};;
   esac

   case "true" in
    ${NATIVEMPIO}|${DATAPATH}|${PCMPATH}) VolName="${asmdev}p1";;
    ${POWERPATH}|${RDAC}) VolName="${asmdev}1";;
   esac
   echo "# Review the following commands, and press continue to execute each, or Ctrl+c to break out:"
   echo "# service oracleasm createdisk VOL${a} ${VolName}"
   read answer
   service oracleasm createdisk VOL${a} ${VolName}

  done && \
  runOracleasmScandisks || \
  echo "Please manually run 'service oracleasm scandisks' on all nodes and check output of the createdisk above as there appears to have been a problem."
 fi
 else
  echo "You have not run the buildASMLISTvariable step!!!!!!!!!!"
  echo " Please do so and re-run again."
 fi && SUCCESS=true || SUCCESS=false

 keepWorking createASMVOLS finalize

}

runOracleasmScandisks()
{
 echo "Now running 'service oracleasm scandisks' on local node"
 service oracleasm scandisks
 cat >/tmp/scandisks.sh.copy <<EOF
#!/bin/bash
/etc/init.d/oracleasm scandisks
EOF

 copyScript "/tmp/scandisks.sh.copy" ${SECONDARYNODELIST} 
 runScript "/tmp/scandisks.sh" ${SECONDARYNODELIST}
}

main $* 2>&1 | tee /tmp/$(hostname)-host-configuration.log
