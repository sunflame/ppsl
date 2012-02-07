#!/bin/bash
#RHEL 4.x to 5.x for Oracle RAC updates

# Pre-checks
# Check if boot drive shows as removable. If it comes back a '1', a custom kickstart must be used that ignores this check
checkBootDrive()
{
BOOTDRIVE=$(df -h /boot|tail -n 1|awk -F'/' '{print $3}'|awk -F'1' '{print $1}')
cat /sys/block/${BOOTDRIVE}/removable
}

# Ensure adequare space for RHEL 5.x image. This is based on RAM
# Options for resolving this include:
#  skipping /var/crash (vc=0)
#  controlling swap size (hcswap=4096)
checkDiskSpace()
{
let MEMORY=$(grep MemTotal /proc/meminfo |awk '{print $2}')/1024
let BOOTSIZE=$(fdisk -l /dev/${BOOTDRIVE}|grep Disk|awk '{print $5}')/1024/1024
if [ $MEMORY -gt 16384 ]
then
 if [ $BOOTSIZE -lt 285000 ]
 then
  echo "Harddrive ${BOOTDRIVE} is too small, minimum size 285000MB, size is ${BOOTSIZE}MB"
 else
  echo "Harddrive ${BOOTDRIVE} meets size requirement"
 fi
else
 if [ ${BOOTSIZE} -gt 139000 ]
 then
  echo "Harddrive ${BOOTDRIVE} is too small, minimum size is 139MB, size is ${BOOTSIZE}MB"
 else
  echo "Harddrive ${BOOTDRIVE} meets size requirement"
 fi
fi
}

########################################################################################################
# SECONDARYNODE kickstart
########################################################################################################
configNode1Phase1()
{
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"

# As root user on ${SECONDARYNODE}
# Check for any connections after stopping listener:
netstat -anp | grep 1521 | grep live | awk '{print $5}' | awk -F':' '{print $1}' | sort | uniq

# As oracle user ${SECONDARYNODE}
 # Shutdown target node
 stopNode ${SECONDARYNODE}

 # Shutdown all instances
 stopAllInstances

 # Stop ASM
 stopASM ${SECONDARYNODE}

 # Compile kfed utility
 make -f /oracle/product/10.2.0/asm_1/rdbms/lib/ins_rdbms.mk $ORACLE_HOME/rdbms/lib/kfed

 # Backup all ASM volume headers
 backupVolumeHeaders

# As root user on ${SECONDARYNODE}
 # Stop CRS
 service init.crs stop

 # Comment out, #--, h[123] in /etc/inittab
 cp /etc/inittab /etc/inittab.orig && \
 cat /etc/inittab.orig | sed -e 's/^h\([123]\)/#--h\1/' >/etc/inittab

 # Stop patrol
 /patrol/Patrol3/scripts.d/S50PatrolAgent.sh stop
}

########################################################################################################

# Customer now engages for backups, kickstart, setup, restore on ${SECONDARYNODE}
#  Reminders: Backups, Pull Cables

########################################################################################################
configNode1Phase2()
{
# As root user on ${SECONDARYNODE}
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"

 # Compare against pre-req details.
 cat /etc/sysconfig/network-scripts/ifcfg-eth0
 cat /etc/sysconfig/network

 # Rebuild eth1 config
 cat >/etc/sysconfig/network-scripts/ifcfg-eth1 <<EOF
# eth1
DEVICE=eth1
ONBOOT=yes
BOOTPROTO=static
IPADDR=1.1.1.2
NETMASK=255.255.255.0
HWADDR="00:21:5E:73:33:1A"
EOF

 # We can ignore this step if desired, as it will happen when the box is rebooted
 service network restart

 # Reconfigure /oa_backup
cat <<EOF >>/etc/fstab
mckoem:/ora_backup_old  /ora_backup nfs rw,noac,bg,intr,hard,timeo=600,wsize=32768,rsize=32768,nfsvers=3,tcp 0 0
EOF
for serv in portmap nfslock netfs
do
 chkconfig $serv on
 service $serv start
done
df -h /ora_backup

 # Confirm crs entries are not present in /etc/inittab
grep ^h[123] /etc/inittab
}

configNode1Phase3()
{
# As oracle user on ${SECONDARYNODE}
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"
DATABASE="${4:-undefined}"

 # relink oracle binaries for all uniq $ORACLE_HOME entries in /etc/oratab
 # Typicaly +ASM and databases
 . oraenv <<EOF
+ASM
EOF
 echo "relink all for ${ORACLE_SID} on ${ORACLE_HOME}"
 ${ORACLE_HOME}/bin/relink all

 . oraenv <<EOF
${DATABASE}
EOF
 echo "relink all for ${ORACLE_SID}"
 ${ORACLE_HOME}/bin/relink all

 cat ~/.ssh/known_hosts | grep -v $(hostname) >~/.ssh/known_hosts.new
 mv ~/.ssh/known_hosts.new ~/.ssh/known_hosts
 /stage/mck_ks/bin/setup_ssh_keys ${NODELIST}
}

configNode1Phase4()
{
# As root user on ${SECONDARYNODE}
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"

 # If SAN is an XIV, all config files can be pulled from ${PRIMARYNODE}
 # Other SAN types must built a new config
 # Customers typically install xiv_attach kit themselves. That must happen prior to this step
 FILES='/etc/multipath/bindings /etc/sysconfig/oracleasm /etc/sysconfig/oracledevices'
 mkdir /etc/multipath
 # You may have to edit /etc/multipath.conf and add 'bindings_file /etc/multipath/bindings' for XIV systems
 for file in $FILES; do scp ${PRIMARYNODE}:${file} ${file}; done

 # Cycle multipathd service to pick up new config
 service multipathd restart
 multipath
 # verify names via multipath -l
 multipath -l

 # "Configure" oracleasm, accept all defaults
 service oracleasm configure

 # start and verify oracledevices
 service oracledevices start && service oracledevices verify
}

########################################################################################################
# Downtime
########################################################################################################
downtime1Phase1()
{
# As oracle user ${PRIMARYNODE}
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"

 # Shutdown target node
 stopNode ${PRIMARYNODE}

 # Shutdown all instances
 stopAllInstances

 # Stop ASM
 stopASM ${PRIMARYNODE}

 # Compile kfed utility
 make -f /oracle/product/10.2.0/asm_1/rdbms/lib/ins_rdbms.mk $ORACLE_HOME/rdbms/lib/kfed

 # Backup all ASM volume headers
 backupVolumeHeaders
}

donwtime1Phase2()
{
# As root user on ${PRIMARYNODE}
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"

 # Stop CRS
 service init.crs stop

 # Comment out, #--, h[123] in /etc/inittab
 cp /etc/inittab /etc/inittab.orig && \
 cat /etc/inittab.orig | sed -e 's/^h\([123]\)/#--h\1/' >/etc/inittab

 # Stop patrol
 /patrol/Patrol3/scripts.d/S50PatrolAgent.sh stop

 # Backup of OCR
  # cd /oracle/product/10.2.0/crs_1/cdata/crs
  # $CRS_HOME/bin/ocrconfig .restore ./backup00.ocr
 for dev in 1 2 3 4 5
 do
  nohup dd if=/dev/raw/raw${dev} of=${ODIR}/raw${dev}.bak &
 done
}

downtime1Phase3()
{
# As root user on ${SECONDARYNODE}
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"

 # Restore raw devices (rhel 5 node)
 for dev in 1 2 3 4 5
 do
  nohup dd if=${ODIR}/raw${dev}.bak of=/dev/raw/raw${dev} &
 done

 # Comment in, #--, h[123] in /etc/inittab
 cp /etc/inittab /etc/inittab.orig && \
 cat /etc/inittab.orig | sed -e 's/^#--//' >/etc/inittab

 # Re-read /etc/inittab and start CRS
 telinit q && service init.crs start
}

########################################################################################################
# PRIMARYNODE kickstart
########################################################################################################
iconfigNode2Phase1()
{
# As root user on ${PRIMARYNODE}
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"

 # Compare against pre-req details.
 cat /etc/sysconfig/network-scripts/ifcfg-eth0
 cat /etc/sysconfig/network

 # Rebuild eth1 config
 cat >/etc/sysconfig/network-scripts/ifcfg-eth1 <${ODIR}/backup-files/ifcfg-eth1

 # We can ignore this step if desired, as it will happen when the box is rebooted
 service network restart

 # Reconfigure /oa_backup
cat <<EOF >>/etc/fstab
mckoem:/ora_backup  /ora_backup nfs rw,noac,bg,intr,hard,timeo=600,wsize=32768,rsize=32768,nfsvers=3,tcp 0 0
EOF
for serv in portmap nfslock netfs
do
 chkconfig $serv on
 service $serv start
done
df -h /ora_backup

 # Confirm crs entries are not present in /etc/inittab
grep ^h[123] /etc/inittab
}
configNode2Phase2()
{
# As oracle user on ${PRIMARYNODE}
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"
DATABASE="${4:-undefined}"

 # relink oracle binaries for all uniq $ORACLE_HOME entries in /etc/oratab
 # Typicaly +ASM and databases
 . oraenv <<EOF
+ASM
EOF
 echo "relink all for ${ORACLE_SID} on ${ORACLE_HOME}"
 ${ORACLE_HOME}/bin/relink all

 . oraenv <<EOF
${DATABASE}
EOF
 echo "relink all for ${ORACLE_SID}"
 ${ORACLE_HOME}/bin/relink all

 cat ~/.ssh/known_hosts | egrep -v "${PRIMARYNODE}|${SECONDARYNODE}" >~/.ssh/known_hosts.new
 mv ~/.ssh/known_hosts.new ~/.ssh/known_hosts
 /stage/mck_ks/bin/setup_ssh_keys ${NODELIST}
}

configNode1Phase3()
{
# As root user on ${SECONDARYNODE}
# Define all customer specific data up front
ODIR="${1:-/ora_backup/managed-services/$(hostname)}"
PRIMARYNODE="${2:-undefined}"
SECONDARYNODE="${3:-undefined}"
NODELIST="${PRIMARYNODE} ${SECONDARYNODE}"

 # If SAN is an XIV, all config files can be pulled from ${PRIMARYNODE}
 # Other SAN types must built a new config
 # Customers typically install xiv_attach kit themselves. That must happen prior to this step
 FILES='/etc/multipath/bindings /etc/sysconfig/oracleasm /etc/sysconfig/oracledevices /etc/multipath.conf /etc/rc.local'
 mkdir /etc/multipath
 # You may have to edit /etc/multipath.conf and add 'bindings_file /etc/multipath/bindings' for XIV systems
 for file in $FILES; do scp ${SECONDARYNODE}:${file} ${file}; done

 # Cycle multipathd service to pick up new config
 service multipathd restart
 multipath
 # verify names via multipath -l
 multipath -l

 # "Configure" oracleasm, accept all defaults
 service oracleasm configure

 # start and verify oracledevices
 service oracledevices start && service oracledevices verify
}

########################################################################################################
# Functions
########################################################################################################

# stopNode stops the listener and nodeapps on the specified node
stopNode()
{
 NODE=${1:-$(hostname)}
 echo "Now stopping listener on ${NODE}"
 srvctl stop listener -n ${NODE} && echo "completed" || echo "failed"
}

# stopAllInstances stops all currently running instances on the local node 
stopAllInstances()
{
 SIDLIST=$(ps -ef|grep _smo|egrep -v 'grep|ASM'|awk '{print $8}'|awk -F'_' '{print $3}'|sed -e 's/.$//')
 for SID in $SIDLIST
 do
  INSTANCE=$(ps -ef|grep _smon_${SID}|awk '{print $8}'|awk -F'_' '{print $3}')
  echo -n "Now stopping $(echo -n ${INSTANCE})..."
  srvctl stop instance -d ${SID} -i ${INSTANCE} -o immediate && echo "completed" || echo "failed"
 done
}

# stopASM stops the ASM instance on the local node
stopASM()
{
 NODE=${1:-$(hostname)}
 SID="+ASM"
 INSTANCE=$(ps -ef|grep _smon_${SID}|awk '{print $8}'|awk -F'_' '{print $3}')
 echo -n "Now stopping $(echo -n ${INSTANCE}) on ${NODE}..."
 srvctl stop asm -n $(hostname) -i ${INSTANCE} -o normal && echo "completed" || echo "failed"
}

# Backup all ASM volume headers
backupVolumeHeaders()
{
 for disk in /dev/oracleasm/disks/*
 do
  NAME=$(echo $disk|awk -F'/' '{print $5}')
  mkdir -p /ora_backup/headers/ && \
  $ORACLE_HOME/rdbms/lib/kfed read ${disk} >/ora_backup/headers/${NAME}.txt
 done
}

main()
{
echo "This is a utility script that defines functions that can be used for project specific purposes"
echo "Source it and utilize the functions as necessary"
}

main
