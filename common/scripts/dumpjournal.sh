#!/bin/sh
#
# dumpjournal
#
# Copyright (C) 2018 jsmoeller@linuxfoundation.org
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
#

if [ -x ./artiproxy-upload.sh ];then
	DUMP_FILE=/tmp/dump
	SYSTEMD_COLORS=false journalctl -a --no-pager > $DUMP_FILE
	./artiproxy-upload.sh $DUMP_FILE dumpjournal
	# still dump to output if any error arise
	if [ $? -eq 0 ];then
		exit 0
	fi
else
	echo "No upload, fallback to dump to console"
fi

SYSTEMD_COLORS=false journalctl -a --no-pager
echo "dumpjournal: pass"
exit 0
