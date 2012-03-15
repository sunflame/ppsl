#!/bin/bash

 DESCRIPTION="Red Hat Enterprise Linux Server release 5.7 (Tikanga)"
 thisDESCRIPTION=$(lsb_release -d|awk -F":" '{print $2}')

# Checks RHEL version
kernel()
{
 target="2.6.18-274.el5"
 this="$(uname -r)"
 
 if [ "$this" = "$target" ]; then
  STATUS="true"
 else
  STATUS="false"
 fi
 export TASK="KERNEL version matches target ($target)"
 export STATUS
}

description()
{
target="Red Hat Enterprise Linux Server release 5.7 (Tikanga)"
this=$(lsb_release -d|awk -F":" '{print $2}')
 if [ "$this" = "$target" ]; then
  STATUS="true"
 else
  STATUS="false"
 fi
export TASK="RHEL Description matches target"
export STATUS
}

STEPLIST="kernel description"
