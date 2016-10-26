#!/bin/bash

usage() {
		echo "Usage: $0"
}
yumInstall() {
	declare -a pkgs=()
	for pkg in $@; do
		if ! rpm --quiet -q $pkg; then
			pkgs+=($pkg)
		fi
	done
	if [ ${#pkgs[@]} -gt 0 ]; then
		yum $YUM_OPTS install ${pkgs[@]}
	fi
}
sshTest() {
	if ! ssh -qo BatchMode=yes -o StrictHostKeyChecking=no $1 true; then
		echo "Testing SSH PublicKey Authentication for: $1 Failed, Now Install PublicKey"
		ssh-copy-id $1
	fi
}
hostKeys() {
	tmp1=$(mktemp)
	tmp2=$(mktemp)
	ssh-keyscan $IP_RAC_1_TEMP | perl -pe "s|\\Q$IP_RAC_1_TEMP\\E|${HN_RAC_1%%.*}|" >> $tmp1
	ssh-keyscan $IP_RAC_2_TEMP | perl -pe "s|\\Q$IP_RAC_2_TEMP\\E|${HN_RAC_2%%.*}|" >> $tmp2
	if [ ! -e /etc/ssh/ssh_known_hosts ]; then
		touch /etc/ssh/ssh_known_hosts
	fi
	if ! grep -Fqf $tmp1 /etc/ssh/ssh_known_hosts; then
		cat $tmp1 >> /etc/ssh/ssh_known_hosts
	fi
	if ! grep -Fqf $tmp2 /etc/ssh/ssh_known_hosts; then
		cat $tmp2 >> /etc/ssh/ssh_known_hosts
	fi
	rm -f -- $tmp1 $tmp2
}

# depends sshKeygen for user, and assert run on INST_MASTER
sshTestSu() {
	$INST_MASTER || (echo "sshTestSu must run on master"; exit 1)
	ENTRYS=$(getent passwd $2)
	IFS=':' read -a ENTRY <<< $ENTRYS
	mgId=${ENTRY[3]}
	userHome=${ENTRY[5]}
	# todo .ssh/known_hosts?
	# add locate->remote
	if ! sudo -u $2 -i ssh $SSH_OPTS $IP_RAC_2_TEMP true; then
		echo "Test for $2@$1 need copy-id"
		cat $userHome/.ssh/id_rsa.pub $userHome/.ssh/id_dsa.pub | ssh $IP_RAC_2_TEMP sudo -u $2 -i "exec sh -c 'cd; umask 077; test -d .ssh || mkdir .ssh ; cat >> .ssh/authorized_keys && (test -x /sbin/restorecon && /sbin/restorecon .ssh .ssh/authorized_keys >/dev/null 2>&1 || true)'" || exit 1
	fi
	# add local->local
	if ! sudo -u $2 -i ssh $SSH_OPTS $IP_RAC_1_TEMP true; then
		cat $userHome/.ssh/id_rsa.pub $userHome/.ssh/id_dsa.pub | sudo -u $2 -i sh -c 'cd; umask 077; test -d .ssh || mkdir .ssh ; cat >> .ssh/authorized_keys && (test -x /sbin/restorecon && /sbin/restorecon .ssh .ssh/authorized_keys >/dev/null 2>&1 || true)' || exit 1
	fi
	# add remote->local
	if ! ssh -t $SSH_OPTS $IP_RAC_2_TEMP sudo -u $2 -i ssh $SSH_OPTS $IP_RAC_1_TEMP true; then
		ssh $IP_RAC_2_TEMP cat $userHome/.ssh/id_rsa.pub $userHome/.ssh/id_dsa.pub | sudo -u $2 -i sh -c 'cd; umask 077; test -d .ssh || mkdir .ssh ; cat >> .ssh/authorized_keys && (test -x /sbin/restorecon && /sbin/restorecon .ssh .ssh/authorized_keys >/dev/null 2>&1 || true)' || exit 1
	fi
	# add remote->remote
	if ! ssh -t $SSH_OPTS $IP_RAC_2_TEMP sudo -u $2 -i ssh $SSH_OPTS $IP_RAC_2_TEMP true; then
		ssh $IP_RAC_2_TEMP cat $userHome/.ssh/id_rsa.pub $userHome/.ssh/id_dsa.pub | ssh $IP_RAC_2_TEMP sudo -u $2 -i "exec sh -c 'cd; umask 077; test -d .ssh || mkdir .ssh ; cat >> .ssh/authorized_keys && (test -x /sbin/restorecon && /sbin/restorecon .ssh .ssh/authorized_keys >/dev/null 2>&1 || true)'" || exit 1
	fi
}
addHost() {
	if grep -q $1 /etc/hosts; then
		if ! grep -q "$1.*$2" /etc/hosts; then
			echo "record exist, but not corret, change it"
			sed -i "s/^$1.*/$1\t$2" /etc/hosts
		fi
	else
		echo -e "$1\t$2" >> /etc/hosts
	fi
}
addHostMulti() {
# TODO incorrect records
	local HN=$1
	shift
	for IP in $@; do
		if ! grep -q "$HN.*$IP" /etc/hosts; then
			echo -e "$HN\t$IP" >> /etc/hosts
		fi
	done
}
setHostname() {
	if ! grep -q "HOSTNAME=$1" /etc/sysconfig/network; then
		echo "/etc/sysconfig/network not correct, changing it"
		sed -i "s/^HOSTNAME=.*$/HOSTNAME=$1/" /etc/sysconfig/network
	fi
	if [ !`hostname -f` = $1 ]; then
		echo "hostname not correct, setting it"
		hostname $1
	fi
}
turnOffSelinux() {
	selinuxenabled && sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
	if selinuxenabled; then
		echo "selinux on, turning off"
		sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
	fi
}
addGroup() {
	if ! ENTRY=$(getent group $1); then
		groupadd -g $2 $1
	elif [ $(cut -d: -f3 <<<$ENTRY) -ne $2 ]; then
			echo "group id for $1 not correct!"
			exit 1
	fi
}
addUser() {
	if ! ENTRY=$(getent passwd $1); then
		echo "User $1($2) not found, adding"
		useradd -u $2 -g $3 -G $4 -s /bin/bash $1
	else
		# TODO uid,group,groups correct
		echo "TODO check user $1 mod correct?"
	fi
}
sdbOpt() {
	if [ -b /dev/sdb ]; then
		if [ -b /dev/sdb1 ]; then
			# mount /dev/sdb1 to /opt
			echo "/dev/sdb1 found, TODO check fstype"
		else
			yumInstall parted
			echo "mk partion: sdb with ext4 fs, and mounting to /opt"
			parted -s -- /dev/sdb mklabel msdos unit s mkpart primary 2048 -1
			mkfs.ext4 -q /dev/sdb1
		fi
		awk "/^[^#]/ && \$2~/^\/opt\$/ {exit 1}" /etc/fstab
		if [ $? -ne 1 ]; then
			echo "mount point /opt not found, adding /dev/sdb1 /opt to /etc/fstab"
			mount /dev/sdb1 /opt
			cat <<EOF >> /etc/fstab

/dev/sdb1	/opt	ext4	defaults	0 0

EOF
		fi
	fi
}
userSshKey() {
	local userHome=`getent passwd $1 | cut -d: -f6`
	if ! [ -f $userHome/.ssh/id_rsa -a -f $userHome/.ssh/id_rsa.pub ]; then
		echo "generate user $1 rsa key"
		sudo -u $1 -i bash -c "ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N '' -q"
	fi
	if ! [ -f $userHome/.ssh/id_dsa -a -f $userHome/.ssh/id_dsa.pub ]; then
		echo "generate user $1 dsa key"
		sudo -u $1 -i bash -c "ssh-keygen -t dsa -b 1024 -f ~/.ssh/id_dsa -N '' -q"
	fi
}
sedConf() {
	local file=$1
	shift
	for pair in $@; do
		IFS='=' read name value <<< $pair
		if grep -q "^$name=" $file; then
			if ! grep -q "^$name=$value\$" $file; then #fixed incorrect
				sed -i "s/$name=.*/$name=$value/" $file
			fi
		else
			sed -i "\$ a\\$name=$value" $file
		fi
	done
}
ifcfg_eth() {
	sedConf /etc/sysconfig/network-scripts/ifcfg-eth0 DEVICE=eth0 TYPE=Ethernet BOOTPROTO=none ONBOOT=yes IPV6INIT=no IPV4_FAILURE_FATAL=yes IPADDR=$1 PREFIX=$IP_RAC_PREFIX GATEWAY=$IP_RAC_GW DNS1=$IP_RAC_DNS DEFROUTE=yes
	sedConf /etc/sysconfig/network-scripts/ifcfg-eth1 DEVICE=eth1 TYPE=Ethernet BOOTPROTO=none ONBOOT=yes IPV6INIT=no IPV4_FAILURE_FATAL=yes IPADDR=$2 PREFIX=$IP_RAC_PREFIX
}
profileClean() {
	 if grep -q "^# auto appended: by auto.sh\$" $1 && grep -q "^# auto appended end: by auto.sh\$" $1; then
                echo "Previous configuration found, remove first"
                sed -i '/^# auto appended: by auto\.sh/,/^# auto appended end: by auto\.sh/d' $1
		sync
                sed -i ':a;/^\n*$/{$d;N};/\n$/ba' $1
		sync
        fi
}
profileOracle() {
	# TODO fix values instead remove and append?
	local file=/home/oracle/.bash_profile
	profileClean $file
	if $INST_MASTER; then
		SID=$ORACLE_SID_DB_1
		HN_RAC=$HN_RAC_1
	else
		SID=$ORACLE_SID_DB_2
		HN_RAC=$HN_RAC_2
	fi
	cat >>$file <<EOF

# auto appended: by auto.sh
export ORACLE_HOSTNAME=$HN_RAC
export ORACLE_UNQNAME=$ORACLE_UNQNAME
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$SID
export PATH=\$ORACLE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib
export CLASSPATH=\$ORACLE_HOME/JRE:\$ORACLE_HOME/jlib:\$ORACLE_HOME/rdbms/jlib

export DISPLAY=$INSTALL_DISPLAY
# auto appended end: by auto.sh

EOF
}
profileGrid() {
	# TODO fix values instead remove and append?
	local file=/home/grid/.bash_profile
	profileClean $file
	if $INST_MASTER; then
		SID=$ORACLE_SID_ASM_1
		HN_RAC=$HN_RAC_1
	else
		SID=$ORACLE_SID_ASM_2
		HN_RAC=$HN_RAC_2
	fi
	cat <<EOF >> /home/grid/.bash_profile

# auto appended: by auto.sh
export ORACLE_HOSTNAME=$HN_RAC
export ORACLE_UNQNAME=$ORACLE_UNQNAME
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$GRID_HOME
export ORACLE_SID=$SID
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib
export CLASSPATH=\$ORACLE_HOME/JRE:\$ORACLE_HOME/jlib:\$ORACLE_HOME/rdbms/jlib
export PATH=\$ORACLE_HOME/bin:\$PATH

export DISPLAY=$INSTALL_DISPLAY
# auto appended end: by auto.sh

EOF
}
confLimits() {
	local file="/etc/security/limits.d/oracle-rac.conf"
	for user in oracle grid; do
		softNoFile=$(sudo -u $user -i ulimit -Sn)
		hardNoFile=$(sudo -u $user -i ulimit -Hn)
		softNoProc=$(sudo -u $user -i ulimit -Su)
		hardNoProc=$(sudo -u $user -i ulimit -Hu)
		if [ $softNoFile -lt 1024 ]; then
			echo "$user soft nofile required 1024, but was $softNoFile, fixed"
			echo -e "$user\tsoft\tnofile\t1024" >> $file
		fi
		if [ $hardNoFile -lt 65536 ]; then
			echo "$user hard nofile required 65536, but was $hardNoFile, fixed"
			echo -e "$user\thard\tnofile\t65536" >> $file
		fi
		if [ $softNoProc -lt 2047 ]; then
			echo "$user soft nproc required 2047, but was $softNoProc, fixed"
			echo -e "$user\tsoft\tnproc\t2047" >> $file
		fi
		if [ $hardNoProc -lt 16384 ]; then
			echo "$user hard nproc required 16384, but was $hardNoProc, fixed"
			echo -e "$user\thard\tnproc\t16384" >> $file
		fi
	done
}
sysctlItem() {
	local file="/etc/sysctl.conf"
	local var=$1
	local required=$2
	local current=$(sysctl -n $1)
	read -a reqs <<< $required
	if [ ${#reqs[@]} -gt 1 ]; then
		read -a currs <<< $current
		# TODO check #currs -eq #reqs
		declare -a except=();
		declare -i need=0;
		for ((i=0;i<${#reqs[@]};i++)); do
			if [ ${reqs[$i]} -gt ${currs[$i]} ]; then
				except+=(${reqs[$i]})
				need+=1
			else
				except+=(${currs[$i]})
			fi
		done
		if [ $need -ne 0 ]; then
			if grep -q $var $file; then
				sed -i "/^$var[^\\w]/d" $file
				sync
			fi
			echo -e "\n$var = ${except[@]}" >> $file
		fi
	elif [ $current -lt $required ]; then
		echo -e "\n$1 = $2" >> $file # TODO add current, note don't add duplicate record
	fi
}
confSysCtl() {
	sysctlItem kernel.sem "250 32000 100 128"
	sysctlItem kernel.shmmni 4096
	sysctlItem fs.file-max 6815744
	sysctlItem fs.aio-max-nr 1048576
	#sysctlItem net.ipv4.ip_local_port_range "9000 65500"
	sysctlItem net.core.rmem_default 262144
	sysctlItem net.core.rmem_max 4194304
	sysctlItem net.core.wmem_default 262144
	sysctlItem net.core.wmem_max 1048576

	# port range need equip
	read -a ports <<< `sysctl -n net.ipv4.ip_local_port_range`
	if [ ${ports[0]} -ne 9000 -o ${ports[1]} -ne 65500 ]; then
		echo "port range need change"
		if grep -q net.ipv4.ip_local_port_range /etc/sysctl.conf; then
			sed -i '/^net\.ipv4\.ip_local_port_range/d' /etc/sysctl.conf; sync
		fi
		echo -e "\nnet.ipv4.ip_local_port_range = 9000 65500" >> /etc/sysctl.conf
	fi

	sysctl -q -p
	return;
}
prepareDirs() {
	local OH=`eval echo $ORACLE_HOME`
	mkdir -p $ORACLE_BASE/cfgtoollogs $OH $ORACLE_DATA $ORACLE_INVENTORY $GRID_HOME
	chown oracle:oinstall $ORACLE_BASE $OH $ORACLE_DATA
	chown oracle:oinstall $ORACLE_BASE/product # TODO how to prevent second run change dir owner of (/opt/oracle/extapi)
	chown grid:oinstall $ORACLE_INVENTORY $GRID_HOME $ORACLE_BASE/cfgtoollogs
	chmod g+w $ORACLE_BASE $ORACLE_INVENTORY $ORACLE_BASE/cfgtoollogs
	# note $ORACLE_BASE/cfgtoollogs need group write for oracle(create by grid without group write)
}
scsiId() {
	scsi_id --page=0x83 --whitelisted --device=$1
}
setupIscsi() {
	iscsiadm -m discovery -t sendtargets -p $ASM_ISCSI_HOST
	iscsiadm -m node -T $ASM_ISCSI_TARGET --login

<<COMMENT
	cat <<-EOF > /etc/udev/rules.d/50-oracle-asm.rules
	KERNEL=="sd*", PROGRAM=="scsi_id --page=0x83 --whitelisted --device=/dev/%k", RESULT=="$(scsiId $ASM_OCR_1)", SYMLINK+="oracleasm/disks/OCR1", OWNER="grid", GROUP="dba", MODE="0660"
	KERNEL=="sd*", PROGRAM=="scsi_id --page=0x83 --whitelisted --device=/dev/%k", RESULT=="$(scsiId $ASM_OCR_2)", SYMLINK+="oracleasm/disks/OCR2", OWNER="grid", GROUP="dba", MODE="0660"
	KERNEL=="sd*", PROGRAM=="scsi_id --page=0x83 --whitelisted --device=/dev/%k", RESULT=="$(scsiId $ASM_OCR_3)", SYMLINK+="oracleasm/disks/OCR3", OWNER="grid", GROUP="dba", MODE="0660"
	KERNEL=="sd*", PROGRAM=="scsi_id --page=0x83 --whitelisted --device=/dev/%k", RESULT=="$(scsiId $ASM_DATA)", SYMLINK+="oracleasm/disks/DATA", OWNER="grid", GROUP="dba", MODE="0660"
	KERNEL=="sd*", PROGRAM=="scsi_id --page=0x83 --whitelisted --device=/dev/%k", RESULT=="$(scsiId $ASM_RECV)", SYMLINK+="oracleasm/disks/RECV", OWNER="grid", GROUP="dba", MODE="0660"
EOF
COMMENT
}
localYum() {
	yum $YUM_OPTS localinstall $RPM_LOCAL_URL/$RPM_ORACLEASM_LIB
	yum $YUM_OPTS localinstall $RPM_LOCAL_URL/$RPM_ORACLEASM_SUPPORT
	yum $YUM_OPTS localinstall $RPM_LOCAL_URL/$RPM_CVUQDISK
}
