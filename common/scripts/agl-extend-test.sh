#!/bin/bash
export NO_COLOR=1
export TERM=dumb

pre_check=`which agl-test`

if [ -n "$pre_check" ] ; then
    echo "agl-extend-test is present"
else
    echo "agl-test is not installed, abort this test"
    exit 127
fi

# execute
agl-test


if [ -x ./artiproxy-upload.sh ] ; then
    LOG_DIR='/var/run/agl-test/logs/log-to-report'
    ZIP_FILE=`ls ${LOG_DIR} | grep agl-test-log*`

    ls -alh ${LOG_DIR}

    if [ -z $ZIP_FILE ] ; then
        echo "Cannot find agl-extend-test log"
        exit 1
    fi

    echo "DEBUG: upload LOG_DIR=${LOG_DIR}XXX"
    echo "DEBUG: upload ZIP_FILE=${ZIP_FILE}XXX"

    ./artiproxy-upload.sh "$LOG_DIR/$ZIP_FILE" "$ZIP_FILE"
    if [ $? -eq 1 ] ; then
        echo "Upload of ${ZIP_FILE} failed"
        exit 1
    else
        echo "Upload of test report successful"
        exit 0
    fi

else
    echo "The file artiproxy-upload.sh does not exist"
    exit 126
fi
