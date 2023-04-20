#!/bin/sh

if [ -z "$PYARTIPROXY_IP" ];then

	echo "DEBUG: No PYARTIPROXY_IP variable, using fallbacks"
	BAYLIBRE_IP=10.1.1.47
	AGLCORELAB_IP=192.168.111.1

	if ping -q -W 2 -4 -c 1 $BAYLIBRE_IP ; then 
		PYARTIPROXY_IP=$BAYLIBRE_IP
	fi
	if ping -q -W 2 -4 -c 1 $AGLCORELAB_IP ; then
		PYARTIPROXY_IP=$AGLCORELAB_IP
	fi
	if [ -z $PYARTIPROXY_IP ] ; then
	    echo "ERROR: no PYARTIPROXY_IP"
	    exit 1
	fi
fi

if [ -z "$1" ];then
	echo "ERROR: missing path argument"
	exit 1
fi

if [ -z "$2" ];then
	echo "ERROR: missing filename argument"
	exit 1
fi

curl --silent --show-error -F "filename=$2" -F "data=@$1" http://$PYARTIPROXY_IP:9090/cgi-bin/pyartiproxy.py --output curl.out
if [ $? -ne 0 ];then
	echo "ERROR: with curl"
	# retry without silent
	curl --show-error -F "filename=$2" -F "data=@$1" http://$PYARTIPROXY_IP:9090/cgi-bin/pyartiproxy.py --output curl.out
fi
ARTI_URL=$(grep -E '^http://.*|https://.*' curl.out)
echo "==========================="
cat curl.out
echo "==========================="
if [ -z "$ARTI_URL" ];then
	# No URL something is wrong
	lava-test-reference artifactory-$2 --result fail
	exit 1
else
	lava-test-reference artifactory-$2 --result pass --reference $ARTI_URL
fi
