#!/bin/bash
if [ -r $(dirname $0)/setenv.sh ]; then
	. $(dirname $0)/setenv.sh
fi
if [ -r $(dirname $0)/functions.sh ]; then
. $(dirname $0)/functions.sh
fi

# fucking mistake when run on my computer
if [ $(hostname) = w530 ]; then
	echo 'Fucking!!! you are run on self computer!!!'
	exit 1
fi

if ! type ssh-keygen >> /dev/null; then
	echo "command ssh-keygen not found"
	exit 1
fi

[ -z "$ASM_INST" ] && ASM_INST="MASTER"
if [ $ASM_INST = "MASTER" ]; then
	INST_MASTER=true
else
	INST_MASTER=false
fi

echo "ASM INST TYPE: $ASM_INST"

HK_RAC_1=$(ssh-keyscan $IP_RAC_1_TEMP | cut -d\  -f2-)
HK_RAC_2=$(ssh-keyscan $IP_RAC_2_TEMP | cut -d\  -f2-)

turnOffSelinux
yumInstall nfs-utils

hostKeys

addGroup oinstall $GID_OINSTALL
addGroup asmadmin $GID_ASMADMIN
addGroup asmdba $GID_ASMDBA
addGroup asmoper $GID_ASMOPER
addGroup dba $GID_DBA
addGroup oper $GID_OPER
addUser grid $UID_GRID oinstall asmadmin,asmdba,asmoper,oper,dba
addUser oracle $UID_ORACLE oinstall dba,asmdba,oper
userSshKey grid
userSshKey oracle

addHost $HN_RAC_1 $IP_RAC_1
addHost $HN_RAC_2 $IP_RAC_2
addHost $HN_RAC_1_VIP $IP_RAC_1_VIP
addHost $HN_RAC_2_VIP $IP_RAC_2_VIP
addHost $HN_RAC_1_PRIV $IP_RAC_1_PRIV
addHost $HN_RAC_2_PRIV $IP_RAC_1_PRIV
addHostMulti $HN_RAC_SCAN $IP_RAC_SCAN_{1,2,3}

confLimits
confSysCtl

profileOracle
profileGrid

sdbOpt
prepareDirs

#echo "Yum Upgrading System: "
#yum $YUM_OPTS upgrade

yumInstall man vim-enhanced mlocate parted
yumInstall ksh kmod-oracleasm smartmontools gcc-c++ compat-libstdc++-33 elfutils-libelf-devel libaio-devel sysstat compat-libcap1 xorg-x11-utils util-linux-ng iscsi-initiator-utils

localYum
setupIscsi

# configure asm disks: TODO if configured, ignore?
cat <<EOF | /etc/init.d/oracleasm configure
grid
oinstall
y
y
EOF
/etc/init.d/oracleasm scandisks

if $INST_MASTER; then # rac1
	yumInstall openssh-clients
	userSshKey root
	sshTest $IP_RAC_2_TEMP

	TMPFILE=`ssh $IP_RAC_2_TEMP mktemp`
	cat $(dirname $0)/setenv.sh $(dirname $0)/functions.sh $(dirname $0)/auto.sh | ssh $IP_RAC_2_TEMP "cat >> $TMPFILE"
	ssh $IP_RAC_2_TEMP "ASM_INST=SLAVE bash $TMPFILE; rm -f -- $TMPFILE"

	ifcfg_eth $IP_RAC_1 $IP_RAC_1_PRIV
	setHostname $HN_RAC_1

	sshTestSu $IP_RAC_2_TEMP oracle
	sshTestSu $IP_RAC_2_TEMP grid

	for sdN in /dev/sd{c,d,e,f,g}; do
		if [ -b $sdN ]; then
			if [ ! -b ${sdN}1 ]; then
				parted -s -- $sdN mklabel msdos unit s mkpart primary 2048 -1
			fi
		fi
	done
	# configure asm disks
	ASM_DISKS_CURRENT="$(/etc/init.d/oracleasm listdisks)"
	for k in ${!ASM_DISKS[@]}; do
		if ! grep -q "$k" <<< $ASM_DISKS_CURRENT; then
			echo "ASM Label $k not found, create on ${ASM_DISKS[$k]}"
			/etc/init.d/oracleasm createdisk $k ${ASM_DISKS[$k]}
		else
			echo "ASM Label $k found, rebuild on ${ASM_DISKS[$k]}"
			/etc/init.d/oracleasm deletedisk $k
			/etc/init.d/oracleasm createdisk $k ${ASM_DISKS[$k]}
		fi
	done

	/etc/init.d/oracleasm scandisks

	ssh $SSH_OPTS $IP_RAC_2_TEMP /etc/init.d/oracleasm scandisks

else # rac2
	ifcfg_eth $IP_RAC_2 $IP_RAC_2_PRIV
	setHostname $HN_RAC_2
fi

# TODO install vmtools
# user grid: runcluvfy.sh stage -pre crsinst -n rac1,rac2 -fixup -verbose

# TODO
# stop rac
# grid$ srvctl stop database -d orcl
# grid$ srvctl status database -d orcl
# root@rac1# $GRID_HOME/bin/crsctl stop has -f
# root@rac2# $GRID_HOME/bin/crsctl stop has -f
# root@rac1# $GRID_HOME/bin/crsctl stop cluster -all
