#!/bin/sh

RCAR_CAN=0
CAN_BCM=0

if [ ! -e /sys/class/net/can1 ];then
	lava-test-case show_can_modules --result skip
	lava-test-case unload_can_raw_module --result skip
	lava-test-case unload_can_module --result skip
	lava-test-case unload_c_can_platform_module --result skip
	lava-test-case unload_c_can_module --result skipp
	lava-test-case unload_can_dev_module --result skip
	lava-test-case canconfig_can0 --result skip
	lava-test-case load_can_module --result skip
	lava-test-case load_can_raw_module --result skip
	lava-test-case load_c_can_module --result skip
	lava-test-case load_can_dev_module --result skip
	lava-test-case canconfig_can0 --result skip
        exit 0
fi

# remove module "$1"
remove_module() {
	lsmod | grep -q "^$1[[:space:]]"
	if [ $? -ne 0 ];then
		lava-test-case unload_$1_module --result skip
		return 0
	fi
	rmmod $1
	if [ $? -eq 0 ];then
		lava-test-case unload_$1_module --result pass
	else
		lava-test-case unload_$1_module --result fail
	fi
}

modprobe_module() {
	modprobe $1
	if [ $? -eq 0 ];then
		lava-test-case load_$1_module --result pass
	else
		lava-test-case load_$1_module --result fail
	fi
}

remove_module can_raw

# handle "rmmod: ERROR: Module can is in use by: can_bcm"
lsmod | grep -q can_bcm
if [ $? -eq 0 ];then
	CAN_BCM=1
	remove_module can_bcm
fi

remove_module can

remove_module c_can_platform

remove_module c_can

lsmod | grep -q rcar_can
if [ $? -eq 0 ];then
	RCAR_CAN=1
	remove_module rcar_can
fi

remove_module can_dev

ip -V 2>&1 | grep -q -i BusyBox
if [ $? -eq 0 ];then
	lava-test-case canconfig_can0 --result skip
else
	ip link set can0 type can bitrate 50000
	if [ $? -eq 0 ];then
		lava-test-case canconfig_can0 --result fail
	else
		lava-test-case canconfig_can0 --result pass
	fi
fi

modprobe_module can

modprobe_module can_raw

modprobe_module c_can

modprobe_module c_can_platform

modprobe_module can_dev

if [ $RCAR_CAN -eq 1 ];then
	modprobe_module rcar_can
fi

if [ $CAN_BCM -eq 1 ];then
	modprobe_module can_bcm
fi

#Make sure always that the can interface is down before
#starting the config step.
ip link set can0 down

ip -V 2>&1 | grep -q -i BusyBox
if [ $? -eq 0 ];then
	lava-test-case canconfig_can0 --result skip
else
	ip link set can0 type can bitrate 50000
	if [ $? -eq 0 ];then
		lava-test-case canconfig_can0 --result pass
	else
		lava-test-case canconfig_can0 --result fail
	fi
fi

sleep 3
