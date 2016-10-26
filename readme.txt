
auto.sh:
	prepare oracle 11gR2 rac install environment on centos 6.8 (minimal installation)

	RAC install method: ASM
		with ASM Label OCR1,OCR2,OCR3,DATA,RECV



ks6.8.cfg: centos 6.8 kickstart install config


oracle-rac.conf:
/dev/vg_1t/rac_c1: 1G partion, export as lun 1, and so on: lun 2 3 4 5
/dev/vg_1t/rac_c2: 1G partion
/dev/vg_1t/rac_c3: 1G partion

/dev/vg_1t/rac_data: 32G DATA partion
/dev/vg_1t/rac_recv: 32G Recovery partion

readme.txt: this file
oracle-rac.conf：
	archlinux: place into /etc/tgt/conf.d/, systemctl start tgtd
	centos: append to /etc/tgt/targets.conf?

	archlinux: https://aur.archlinux.org/tgt.git (aur repo)
	centos: scsi-target-utils (yum repo)

setenv.sh: install parameters
functions.sh: functions declaration
auto.sh: main script
