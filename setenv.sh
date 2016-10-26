#!/bin/bash

#NOTE Host Configuration:
#
# HardDisk must be 2, /dev/sda and /dev/sdb, sdb will auto part one partion sdb1, and be mount at /opt
# Network must be eth0 and eth1, and eth0 is public nic, and eth1 is private nic
# You can add other nic, and set IP_RAC_{1,2}_TEMP to these nic
#
# IF you not mount nfs at /var/yum/cache, please remove -C in YUM_OPTS
# IF you not mount nfs at /mnt/soft, and so..., copy cvuqdisk, oracleasm-support, oracleasmlib rpms to you local dir by yourself (in script)
# pdksh not required, this script use ksh rpm instead

# INSTALL_DISPLAY: set to your xserver, and remember use xhost +(rac1's ip)

#IP_RAC_1_TEMP="192.168.121.117"
#IP_RAC_2_TEMP="192.168.121.183"
# hosts IP's (before configure network)
IP_RAC_1_TEMP="192.168.121.33"
IP_RAC_2_TEMP="192.168.121.34"

# rac network configure
IP_RAC_1="192.168.247.33"
IP_RAC_2="192.168.247.34"
IP_RAC_GW="192.168.247.2"
IP_RAC_DNS="192.168.247.1"
IP_RAC_PREFIX="24"

IP_RAC_1_VIP="192.168.247.35"
IP_RAC_2_VIP="192.168.247.36"
IP_RAC_1_PRIV="192.168.121.33"
IP_RAC_2_PRIV="192.168.121.34"
IP_RAC_SCAN_1="192.168.247.37"
IP_RAC_SCAN_2="192.168.247.38"
IP_RAC_SCAN_3="192.168.247.39"

HN_RAC_1="rac1.vm.lc4ever.net"
HN_RAC_2="rac2.vm.lc4ever.net"
HN_RAC_1_VIP="rac1-vip.vm.lc4ever.net"
HN_RAC_2_VIP="rac2-vip.vm.lc4ever.net"
HN_RAC_1_PRIV="rac1-priv.vm.lc4ever.net"
HN_RAC_2_PRIV="rac2-priv.vm.lc4ever.net"
HN_RAC_SCAN="rac-scan.vm.lc4ever.net"

# yum install's options
YUM_OPTS="-C -y -q --setopt=keepcache=1"
# ssh opts, note: BatchMode=yes StrictHostKeyChecking=no required
SSH_OPTS="-qo BatchMode=yes StrictHostKeyChecking=no"

# NOT-USED (kickstart installation already configured
NFS_SHARED_SOFT="192.168.247.1:/srv/nfs/shared/soft/"
NFS_YUM_CACHE="192.168.247.1:/srv/nfs/shared/centos/yum/"

# yum local install url, note if you are use http or nfs, use rpm instead yum
#RPM_LOCAL_URL="nfs://$NFS_SHARED_SOFT/centos6/"
#RPM_LCOAL_URL="http://192.168.247.1/centos/rpm-6/"
RPM_LOCAL_URL="/mnt/soft/centos6/"

# on nfs
# oracle downloaded rpm's, pdksh not used, this can use ksh instead
RPM_CVUQDISK="cvuqdisk-1.0.9-1.rpm"
RPM_PDKSH="pdksh-5.2.14-37.el5_8.1.x86_64.rpm"
RPM_ORACLEASM_LIB="oracleasmlib-2.0.4-1.el6.x86_64.rpm"
RPM_ORACLEASM_SUPPORT="oracleasm-support-2.1.8-1.el6.x86_64.rpm"

# gid and uid
# group ids and user ids ( need equals on rac1 and rac2)
GID_OINSTALL="2000"
GID_ASMADMIN="2010"
GID_ASMDBA="2011"
GID_ASMOPER="2012"
GID_DBA="2020"
GID_OPER="2021"

UID_GRID="2010"
UID_ORACLE="2020"

# install directory
ORACLE_BASE="/opt/oracle"
ORACLE_HOME="\$ORACLE_BASE/product/11.2.0/dbhome_1"
ORACLE_DATA="/opt/oradata"
ORACLE_INVENTORY="/opt/oraInventory"
ORACLE_UNQNAME="RAC"
ORACLE_SID_DB_1="RAC1"
ORACLE_SID_DB_2="RAC2"
ORACLE_SID_ASM_1="+ASM1"
ORACLE_SID_ASM_2="+ASM2"

GRID_HOME="/opt/grid"


# TYPE: ASM, NFS
# current not used, maybe add nfs installation support
INSTALL_TYPE="ASM"

# ASM
# iscsiadm -m discovery -t sendtargets -p 192.168.121.1
# ISCSI dicovery host
ASM_ISCSI_HOST="192.168.121.1"
# iscsiadm -m node -T iqn.2011-09.net.lc4ever:vm.rac.storge --login
# ISCSI target
ASM_ISCSI_TARGET="iqn.2011-09.net.lc4ever:vm.rac.storge"

# graph install display server
INSTALL_DISPLAY="192.168.121.1:0.0"

# OCR Storage Config#!/bin/bash
# ASM disks and label
declare -A ASM_DISKS;
ASM_DISKS[OCR1]="/dev/sdc1"
ASM_DISKS[OCR2]="/dev/sdd1"
ASM_DISKS[OCR3]="/dev/sde1"
ASM_DISKS[DATA]="/dev/sdf1"
ASM_DISKS[RECV]="/dev/sdg1"

