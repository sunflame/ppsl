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
 LOG=/tmp/$(hostname)-adv-post.log
 STEP=none
 SPECFILE="/dev/null"
 export PATH=${PATH}:/sbin:/usr/local/sbin:/usr/sbin

 while getopts ":rpDPnNdo:OCS:QR:c" options; do
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
   S) SPECFILE="${OPTARG}";;
   R) STEP="${OPTARG}";;
   c) CLEANUP=true;;
   h|\?|:|*) echo "Help requested via -h or incorrect option"; usage;exit 1;;
  esac
 done
}

# short way to display a linebreak for easy viewing of the log
lineBreak()
{
 debug && set -x

 echo "################################################################################"
}

# This function sources the spec file provided or dumps out if none
getSpecFile()
{
 if [ -f ${SPECFILE} ]; then
  source ${SPECFILE}
 else
  echo "Spec file is required, please specify with -S"
  usage
  return 1
 fi
}

# a nice help function to explain how to use this script
usage()
{
 debug && set -x

 lineBreak
 echo "This script will run Advanced Services universal post project audit script"
 lineBreak
 echo "./$(basename $0) -S <specfile> [-h] [-d] [-r|-p|-D|-P|-n|-Q|-N] [-R <step>] [-o <path>] [-O]"
 lineBreak
 echo "-S <specfile>	# Specify the spec file to be used for this audit"
 lineBreak
 echo "-r 		# Force RDAC selection, BETA"
 echo "-p 		# Force POWERPATH selection"
 echo "-D 		# Force DATAPATH selection, BETA"
 echo "-P 		# Force PCMPATH selection, BETA"
 echo "-n 		# Force NATIVEMPIO selection"
 echo "-Q 		# Force HP/Qlogic selection, BETA"
 echo "-N 		# Force NOSAN selection"
 lineBreak
 echo "-d 		# Set DEBUG mode (set -x)"
 echo "-o <path>	# Set ODIR=<path>, default ${ODIR}"
 echo "-O		# Override OS safety check, allows to run on unsupported OS"
 echo "-h		# print this help"
 lineBreak
}

# Function to kick off the entire process
main()
{
 setVars $*
 getSpecFile
 runStep ${STEP}
}

# This function allows us to run through the specified steps
# as well as any dependent steps. Various groupings of steps will
# be created to assist with specific project workflows, but in
# most cases all steps can be run via ALLSTEPS
runStep()
{
 debug && set -x

 lineBreak
 echo "Now executing the following steps: ${STEPLIST}"
 lineBreak

 for step in ${STEPLIST}
 do
  export step
  ${step}
  #printf '%-74s %-5s\n' "${TASK}" "${STATUS}"
  #line="......................................................................."
  #printf "%s %s [${STATUS}]\n" "$TASK" "${line:${#TASK}}"
  displayOutput "${STATUS}" "${TASK}"
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
 #set -x

 export SUCCESS="$1"
 export MSG="$2"
 export OUTPUTFILE=${ODIR}/adv-srv-${step}.out
 linelength=80
 line="......................................................................."
 if [ "${SUCCESS}" = "true" ]; then
  #echo "${MSG}......SUCCESS"
  #printf "%s %-10s [SUCCESS]\n" "$MSG" "${line}"
  #printf '%s%*.*s%s\n' "$SUCCESS" 0 $((linelength - ${#SUCCESS} - ${#MSG} )) "$line" "$MSG"
  printf '%s%*.*s%s\n' "$MSG" 0 $((linelength - 9 - ${#MSG} )) "$line" "[SUCCESS]"
 else
  #echo "${MSG}......FAILURE"
  printf '%s%*.*s%s\n' "$MSG" 0 $((linelength - 9 - ${#MSG} )) "$line" "[FAILURE]"
  #printf "%s %s [FAILURE]\n" "$MSG" "${line:-${#MSG}}"
 fi #>>${LOG}
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

# This function copies the logs to ${ODIR}.
finalize()
{
 debug && set -x

 lineBreak
 echo "All post-audits have been completed. Please copy each relavent section into"
 echo " the plan for documentation and manually run any required steps."
 lineBreak
 cp /tmp/$(hostname)-post-audit.log ${ODIR}/$(hostname)-post-audit.log
 cp /tmp/$(hostname)-adv-post.log ${ODIR}/$(hostname)-adv-post.log
}

main $* 2>&1 | tee /tmp/$(hostname)-post-audit.log
if [ -f /tmp/$(hostname)-adv-post.log ]; then
 echo "Press enter to display the log at /tmp/$(hostname)-adv-post.log (ctrl+c to break)"
 read continue
 more /tmp/$(hostname)-adv-post.log
fi
