#!/bin/bash

set -x

export TERM=dumb
export COLUMNS=1000

XDG_RUNTIME_DIR=/run/user/1001
AGLDRIVER=agl-driver




REF_IMAGE="$1"

if [ -z "${REF_IMAGE}" ]; then
	echo "No reference image passed"
	exit 125
fi

if [ ! -f "${REF_IMAGE}" ]; then
	echo "Reference image is not found"
	exit 125
fi

# Enable the test picture and disable cursor and any other application from being displayed
sed -i '/^\[core\]/a activate-by-default=false' /etc/xdg/weston/weston.ini
# setup homescreen env variable
sed -i '/^\[core\]/a hide-cursor=true' /etc/xdg/weston/weston.ini
# enable red/green/blue test screen
echo 'HOMESCREEN_DEMO_CI=1' > /etc/default/homescreen
sync
systemctl daemon-reload || true
su - agl-driver -c 'export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1001/bus" ; systemctl --user daemon-reload' || true
sleep 2

# create initial journal cursor file
journalctl /usr/bin/agl-compositor --cursor-file=/tmp/agl-screenshot-cursor > /tmp/first-log 2>&1

# stop homescreen (shell) and launcher
su $AGLDRIVER -c 'XDG_RUNTIME_DIR=/run/user/1001/ DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus systemctl --user stop homescreen'
su $AGLDRIVER -c 'XDG_RUNTIME_DIR=/run/user/1001/ DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus systemctl --user stop launcher'
# restart agl-compositor
su $AGLDRIVER -c 'XDG_RUNTIME_DIR=/run/user/1001/ DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus systemctl --user restart agl-compositor'
su $AGLDRIVER -c 'XDG_RUNTIME_DIR=/run/user/1001/ DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus systemctl --user start homescreen'

# e.g. qemu-system-arm takes loooong
sleep 10
echo "Waiting for compositor to initialize (+10sec)."

LOOP=20
while test $LOOP -ge 1 ; do

  ( mv /tmp/next-log /tmp/prev-log > /dev/null 2>&1 ) || true
  journalctl /usr/bin/agl-compositor --cursor-file=/tmp/agl-screenshot-cursor > /tmp/next-log 2>&1
  if ! grep -q 'Usable area:' /tmp/next-log ; then
  # e.g. qemu-system-arm takes loooong
        echo "Waiting for compositor to initialize (+60sec). Loop: $LOOP"
	sleep 60
	LOOP="$(($LOOP-1))"
	continue
  fi
  break
done

#read aw


# giving up now
if ! grep -q 'Usable area:' /tmp/next-log ; then
	echo "Marker ('Usable area:') not found. Dumping log."
	echo "##################################"
	cat /tmp/first-log
	cat /tmp/prev-log
	cat /tmp/next-log
	echo "##################################"
        exit 127
	#echo "CONTINUING ANYWAY !"
fi

AGL_SCREENSHOOTER=/usr/bin/agl-screenshooter

#su - $AGLDRIVER -c "..."
do_screenshot()
{
	su - $AGLDRIVER -c "XDG_RUNTIME_DIR=/run/user/1001 $AGL_SCREENSHOOTER"
	return $?
}


if [ -z "$AGL_SCREENSHOOTER" ]; then
	echo "Failed to find agl-screenshooter. Compositor too old?"
	exit 127
fi

#echo "Found agl-screenshoooter in $AGL_SCREENSHOOTER"
rm -rf /home/agl-driver/agl-screenshot-*.png

# give it a bit more time to display
#sleep 60

if do_screenshot ; then
	echo "Screenshot taken"
else
	echo "##################################"
	journalctl --no-pager -a -b /usr/bin/agl-compositor
	echo "##################################"
	exit 127
fi

REF_IMAGE_SHA1SUM=`sha1sum ${REF_IMAGE} | awk -F ' ' '{print $1}'`
IMAGE_SHA1SUM=`sha1sum /home/agl-driver/agl-screenshot-*.png | awk -F ' ' '{print $1}'`

if [ "${REF_IMAGE_SHA1SUM}" == "${IMAGE_SHA1SUM}" ]; then
	echo "Screenshot matches the reference image"
	FINALRET=0
else
	echo "Screenshot does not match the reference image"
	FINALRET=127
	for i in /home/agl-driver/agl-screenshot-*.png ; do
		if [ -x ./artiproxy-upload.sh ];then
			echo "DEBUG: upload screenshot $i"
			./artiproxy-upload.sh $i $(basename $i)
		fi
	done
	echo "#########################"
	journalctl -t agl-compositor
	echo "#########################"
	journalctl -b --no-pager -a
	echo "#########################"
fi


# cleanup
sed -i '/activate-by-default=false/d' /etc/xdg/weston/weston.ini
sed -i '/hide-cursor=true/d' /etc/xdg/weston/weston.ini
#rm -rf /etc/systemd/system/weston@.service.d
rm -rf /etc/default/homescreen
systemctl daemon-reload
sync
sleep 2
systemctl restart agl-session@agl-driver.service

sleep 10

exit $FINALRET
