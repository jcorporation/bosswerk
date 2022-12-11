#!/bin/bash

#SPDX-License-Identifier: GPL-3.0-or-later
#myMPD (c) 2022 Juergen Mang <mail@jcgames.de>
#https://github.com/jcorporation

BASE_DIR=$(dirname "$(realpath "$0")") # path of the script
WWW="$BASE_DIR/www"                    # doc root
DATA_FILE="$WWW/data/data.js"          # the javascript file with current data
GRAPH_DIR="$WWW/graphs"                # dir for the rrd graphs
RRD="$BASE_DIR/rrd/solar.rrd"          # the rrd data file

# rrd options
RRD_OPTS="--imgformat SVG -w 800 -h 300 -u 600 -l 0"
RRD_OPTS="$RRD_OPTS --full-size-mode -g"
RRD_OPTS="$RRD_OPTS DEF:watts_avg=$RRD:watts:AVERAGE"
RRD_OPTS="$RRD_OPTS DEF:watts_min=$RRD:watts:MIN"
RRD_OPTS="$RRD_OPTS DEF:watts_max=$RRD:watts:MAX"
RRD_OPTS="$RRD_OPTS AREA:watts_max#7eca90:Max"
RRD_OPTS="$RRD_OPTS AREA:watts_avg#28a745:Watt"
RRD_OPTS="$RRD_OPTS LINE:watts_max#ffffff:Min"

# goto script dir
cd "$BASE_DIR" || exit 1

source .config

if [ -z "$PV_URI" ]
then
  echo "PV_URI not defined"
  exit 1
fi

if [ ! -f "$RRD" ]
then
  # creates the rrd with:
  # - 5 min data steps
  # - 1 week: 5 min
  # - 1 year: 15 min
  # - 20 year: 1 hour
  rrdtool create "$RRD" --start now-2h --step 300 \
	DS:watts:GAUGE:600:0:700
	RRA:AVERAGE:0:1:2016
	RRA:AVERAGE:0:3:35712
	RRA:AVERAGE:0:12:175680
	RRA:MIN:0:1:2016
	RRA:MIN:0:3:35712
	RRA:MIN:0:12:175680
	RRA:MAX:0:1:2016
	RRA:MAX:0:3:35712
	RRA:MAX:0:12:175680
fi

# try to fetch the data from pv
for TRY in {1..10}
do
  echo "Fetching data from pv (#$TRY)"
  if OUT=$(curl -s -n "$PV_URI" 2>&1 | grep "^var webdata")
  then
    WATT=$(grep webdata_now_p <<< "$OUT" | cut -d\" -f2)
    if [ -n "$WATT" ]
    then
      # updat the rrd and write the js data file
      echo "$OUT" > "$DATA_FILE"
      echo "var last_refresh=$(date +%s)" >> "$DATA_FILE"
      rrdtool update "$RRD" "N:$WATT"
      break
    fi
  fi
  sleep 10
done

# update graphs
if [ ! -f "$GRAPH_DIR/last_8h.svg" ] ||
   [ "$RRD" -nt "$GRAPH_DIR/last_8h.svg" ]
then
  # update graph in cronjob interval (5 min)
  rrdtool graph "$GRAPH_DIR/last_8h.svg" \
  	-t "Last 8 hours" --end now --start end-8h \
	$RRD_OPTS
	
  rrdtool graph "$GRAPH_DIR/last_day.svg" \
  	-t "Last day" --end now --start end-1d \
	$RRD_OPTS

  # update other graphs hourly
  if [ ! -f "$GRAPH_DIR/last_month.svg" ] ||
     [ "$(( $(date +"%s") - $(stat -c "%Y" "$GRAPH_DIR/last_month.svg") ))" -gt "7200" ]
  then
    rrdtool graph "$GRAPH_DIR/last_month.svg" \
  	-t "Last month" --end now --start end-5w \
	$RRD_OPTS

    rrdtool graph "$GRAPH_DIR/last_year.svg" \
  	-t "Last year" --end now --start end-53w \
	$RRD_OPTS
  fi
fi
