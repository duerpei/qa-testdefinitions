#!/bin/sh

set -x

export TERM=dumb
export COLUMNS=1000

AGLDRIVER=agl-driver

while [ $# -ge 1 ]
do
	case $1 in
	-b)
		shift
		BASEURL=$1
		shift
	;;
	*)
		echo "Unknown argument $1"
		exit 1
	;;
	esac
done

if [ -z "$BASEURL" ]; then
	echo "$0: missing BASEURL"
	echo "Usage: $0 -b BASEURL"
	exit 1
fi

do_afm_util()
{
set -x
	if [ $SERVICE_USER -eq 1 -o $APPLICATION_USER -eq 1 ];then
		su - $AGLDRIVER -c "afm-util $*"
	else
		afm-util $*
	fi
	return $?
}

do_afm_test()
{
set -x
	if [ $SERVICE_USER -eq 1 -o $APPLICATION_USER -eq 1 ];then
		su - $AGLDRIVER -c "aft-test $*"
	else
		afm-test -l $*
	fi
	return $?
}

if [ ! -f index.html ] ; then
	wget -q $BASEURL -O index.html
	if [ $? -ne 0 ];then
	    echo "ERROR: Cannot wget $BASEURL"
		exit 1
	fi
fi

WGTNAME="$(grep -o '[a-z-]*.wgt' index.html | sed 's,.wgt$,,' | sed 's,-debug$,,' | sed 's,-coverage$,,' | sed 's,-test$,,' | uniq)"

grep -o '[a-z-]*.wgt' index.html | sort | uniq |
while read wgtfile
do
	# remove extension and the debug state
	#export WGTNAME=$(echo $wgtfile | sed 's,.wgt$,,' | sed 's,-debug$,,' | sed 's,-coverage$,,' | sed 's,-test$,,')
	echo "DEBUG: fetch $wgtfile"

	if [ ! -f $wgtfile ] ; then
		wget -q $BASEURL/$wgtfile
		if [ $? -ne 0 ];then
			echo "ERROR: wget from $BASEURL/$wgtfile"
			continue
		fi
	fi
done

echo "$WGTNAME"

inspectwgt() 
{

	wgtfile=$1
	CURDIR="$(pwd)"
	ZIPOUT="$(mktemp -d)"
	cd $ZIPOUT

	echo "DEBUG: analyse wgt file"
	unzip $CURDIR/$wgtfile
	if [ $? -ne 0 ];then
		# TODO Do not fail yet, busybox unzip seems to "fail with success" when checking CRC
		echo "ERROR: cannot unzip $wgtfile"
	fi
	if [ -f config.xml ];then
		grep hidden config.xml
		if [ $? -eq 0 ];then
			echo "DEBUG: hidden package"
		else
			echo "DEBUG: not hidden package"
		fi
		# a service sets urn:AGL:widget:provided-api
		grep "urn:AGL:widget:provided-api" config.xml
		if [ $? -eq 0 ] ; then
		    # we are a service, now determine the scope ...
		    grep "urn:AGL:permission::partner:scope-platform" config.xml
		    if [ $? -eq 0 ];then
			export SERVICE_PLATFORM=1
		    else
			export SERVICE_USER=1
		    fi
		else
		    # we are an application
		    export APPLICATION_USER=1
		    # no other type known (yet)
		fi
	else
		echo "DEBUG: fail to unzip"
	fi

	cd $CURDIR
	rm -r $ZIPOUT

}

# cases:
# a) (release).wgt -> lifecycle
# b) -test.wgt -> run afm-test $wgt
# later: c) -coverage wgt -> install coverage AND run afm-test $wgt
for RUNIT in runrelease runtest ; do

    SERVICE_PLATFORM=0
    SERVICE_USER=0
    APPLICATION_USER=0

    if [ x"runrelease" = x"$RUNIT" ] ; then
	eval wgtfile="${WGTNAME}.wgt"
	inspectwgt $wgtfile

	echo "DEBUG: list current pkgs"
	# TODO mktemp
	LIST='list'
	afm-util list --all > $LIST
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util list exit with error"
		continue
	fi
	if [ ! -s "$LIST" ];then
		echo "ERROR: afm-util list is empty"
		continue
	fi

	echo "DEBUG: check presence of $WGTNAME"
	NAMEID=$(grep id\\\":\\\"${WGTNAME}\" $LIST | cut -d\" -f4 | cut -d\\ -f1)
	if [ ! -z "$NAMEID" ];then
		echo "DEBUG: $WGTNAME already installed as $NAMEID"
		# need to kill then deinstall
		do_afm_util ps --all | grep -q $WGTNAME
		if [ $? -eq 0 ];then
			echo "DEBUG: kill $WGTNAME"
			do_afm_util kill $WGTNAME
			if [ $? -ne 0 ];then
				echo "ERROR: afm-util kill"
				#lava-test-case afm-util-pre-kill-$WGTNAME --result fail
				#continue
			#else
			#	lava-test-case afm-util-pre-kill-$WGTNAME --result pass
			fi
		else
			echo "DEBUG: no need to kill $WGTNAME"
		fi

		echo "DEBUG: deinstall $WGTNAME"
		afm-util remove $NAMEID
		if [ $? -ne 0 ];then
			echo "ERROR: afm-util remove"
			#lava-test-case afm-util-remove-$WGTNAME --result fail
			journalctl -b | tail -40
			#continue
		else
			lava-test-case afm-util-remove-$WGTNAME --result pass
		fi
	else
		echo "DEBUG: $WGTNAME not installed"
	fi
	grep id $LIST

	echo "DEBUG: install $wgtfile"
	OUT="out"
	afm-util install $wgtfile > $OUT
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util install"
		lava-test-case afm-util-install-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-install-$WGTNAME --result pass
	fi
	# message is like \"added\":\"mediaplayer@0.1\"
	NAMEID=$(grep d\\\":\\\"${WGTNAME}\" $OUT | cut -d\" -f4 | cut -d\\ -f1)
	if [ -z "$NAMEID" ];then
		echo "ERROR: Cannot get nameid"
		echo "DEBUG: ========== DUMPING output =========="
		cat $OUT
		echo "DEBUG: ========== END DUMP =========="
		continue
	fi
	echo "DEBUG: $WGTNAME is installed as $NAMEID"

	afm-util list --all > $LIST
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util list exit with error"
		continue
	fi
	if [ ! -s "$LIST" ];then
		echo "ERROR: afm-util list is empty"
		continue
	fi
	echo "DEBUG: Verify that $WGTNAME is installed"
	grep -q $NAMEID $LIST
	if [ $? -ne 0 ];then
		echo "ERROR: $WGTNAME is not installed"
		# for debugging, give full output
		echo "DEBUG: start of list"
		cat $LIST
		echo "DEBUG: end of list"
	fi

	do_afm_util info $NAMEID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util info"
		lava-test-case afm-util-info-$WGTNAME --result fail
	else
		lava-test-case afm-util-info-$WGTNAME --result pass
	fi

	echo "DEBUG: check if we see the package with systemctl list-units (before start)"
	systemctl list-units --full | grep "afm.*$WGTNAME--"
	echo "DEBUG: check if we see the package with systemctl -a (before start)"
	systemctl -a |grep "afm.*$WGTNAME--"

	echo "DEBUG: start $NAMEID"
	do_afm_util start $NAMEID > "rid"
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util start"
		lava-test-case afm-util-start-$WGTNAME --result fail
		journalctl -an 200
		continue
	else
		lava-test-case afm-util-start-$WGTNAME --result pass
	fi

	echo "DEBUG: check if we see the package with systemctl list-units (after start)"
	systemctl list-units --full | grep "afm.*$WGTNAME--"
	echo "DEBUG: check if we see the package with systemctl -a (after start)"
	systemctl -a |grep "afm.*$WGTNAME--"

	echo "DEBUG: Get RID for $NAMEID"
	PSLIST="pslist"
	afm-util ps --all > $PSLIST
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util ps"
		lava-test-case afm-util-ps-$WGTNAME --result fail
		continue
	else
		cat $PSLIST
		lava-test-case afm-util-ps-$WGTNAME --result pass
	fi
	# TODO, compare RID with the list in $PSLIST"
	RID="$(cat rid)"
	if [ "$RID" == 'null' ];then
		sleep 20
		echo "DEBUG: retry start $NAMEID"
		do_afm_util start $NAMEID > "rid"
		if [ $? -ne 0 ];then
			echo "ERROR: afm-util start"
			lava-test-case afm-util-start-$WGTNAME --result fail
			continue
		fi
		RID="$(cat rid)"
	fi

	if [ "$RID" == 'null' ];then
		echo "ERROR: RID is null, service fail to start"
		lava-test-case afm-util-status-$WGTNAME --result fail
		continue
	fi

	echo "DEBUG: status $NAMEID ($RID)"
	do_afm_util status $RID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util status"
		lava-test-case afm-util-status-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-status-$WGTNAME --result pass
	fi

	echo "DEBUG: kill $NAMEID ($RID)"
	do_afm_util kill $NAMEID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util kill"
		lava-test-case afm-util-kill-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-kill-$WGTNAME --result pass
	fi

	echo "DEBUG: start2 $NAMEID"
	do_afm_util start $NAMEID > rid
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util start2"
		lava-test-case afm-util-start2-$WGTNAME --result fail
		journalctl -an 200
		continue
	else
		lava-test-case afm-util-start2-$WGTNAME --result pass
	fi
	RID="$(cat rid)"
	if [ "$RID" == 'null' ];then
		echo "ERROR: RID is null"
		continue
	fi
	sleep 120
	echo "DEBUG: status2 $NAMEID ($RID)"
	do_afm_util status $RID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util status2"
		lava-test-case afm-util-status2-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-status2-$WGTNAME --result pass
	fi
    fi
    if [ x"runtest" = x"$RUNIT" ] ; then
	eval wgtfile="${WGTNAME}-test.wgt"
	inspectwgt $wgtfile
	afm-test -l $wgtfile
	journalctl -b | grep ${WGTNAME}-test
	( journalctl -b | grep ${WGTNAME}-test | grep ERROR ) || true	
    fi

done
