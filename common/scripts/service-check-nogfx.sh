#!/bin/bash

export LANG=C
export TERM=dumb

REQUIREDSOCKETS="cynara.socket dbus.socket security-manager.socket"
REQUIREDSERVICES="afm-system-daemon.service afm-user-session@1001.service connman.service ofono.service bluetooth.service gpsd.service udisks.service lightmediascanner.service"

ALL="${REQUIREDSOCKETS} ${REQUIREDSERVICES}"
RESULT="unknown"

# add delay for services to fully start
sleep 5

for i in ${ALL} ; do
    echo -e "\n\n########## Test for service ${i} being active ##########\n\n"

    systemctl is-active ${i} >/dev/null 2>&1
    if [ $? -eq 0 ] ; then
        RESULT="pass"
    else
        RESULT="fail"
    fi

    lava-test-case ${i} --result ${RESULT}
    systemctl status ${i} || true
    echo -e "\n\n"

    echo -e "\n\n########## Result for service ${i} : $RESULT ##########\n\n"
done


echo "------------------------------------------------"
echo "All systemd units:"
echo "------------------------------------------------"
systemctl list-units || true
echo "------------------------------------------------"
echo "Only the failed systemd units:"
echo "------------------------------------------------"
( systemctl list-units | grep failed ) || true


exit 0