#!/bin/bash

# strict mode
set -euo pipefail

#SPDX-License-Identifier: GPL-3.0-or-later
#myMPD (c) 2022 Juergen Mang <mail@jcgames.de>
#https://github.com/jcorporation

BASE_DIR=$(dirname "$(realpath "$0")")     # path of the script
WWW_DIR="$BASE_DIR/www"                    # doc root
GRAPH_DIR="$WWW_DIR/graphs"                # dir for the rrd graphs
DATA_FILE="$WWW_DIR/data/data.js"          # the javascript file with current data
RRD_FILE="$BASE_DIR/rrd/solar.rrd"         # the rrd data file

# rrd options
RRD_OPTS="--imgformat SVG -w 800 -h 300 -u 600 -l 0"
RRD_OPTS="$RRD_OPTS --full-size-mode -g"
RRD_OPTS="$RRD_OPTS DEF:watts_avg=$RRD_FILE:watts:AVERAGE"
RRD_OPTS="$RRD_OPTS DEF:watts_min=$RRD_FILE:watts:MIN"
RRD_OPTS="$RRD_OPTS DEF:watts_max=$RRD_FILE:watts:MAX"

# for exact graphs (max = min = avg)
RRD_OPTS_EXACT="$RRD_OPTS AREA:watts_max#7eca90:Max"
RRD_OPTS_EXACT="$RRD_OPTS_EXACT LINE2:watts_avg#28a745:Watt"

# for more fuzzy graphs
RRD_OPTS_FUZZY="$RRD_OPTS AREA:watts_max#7eca90:Max"
RRD_OPTS_FUZZY="$RRD_OPTS_FUZZY AREA:watts_min#ffffff:Min"
RRD_OPTS_FUZZY="$RRD_OPTS_FUZZY LINE2:watts_avg#28a745:Watt"

# goto script dir
cd "$BASE_DIR" || exit 1

source .config

if [ -z "${PV_URI+x}" ]
then
  echo "PV_URI not defined"
  exit 1
fi

if [ ! -f "$RRD_FILE" ]
then
  # creates the rrd with:
  # - 5 min data steps
  # - 8 days: 5 min
  # - 397 days: 15 min
  # - 7320 days (20 years): 1 hour
  rrdtool create "$RRD_FILE" --start now-2h --step 300 \
    DS:watts:GAUGE:600:0:700 \
    RRA:AVERAGE:0:1:2304 \
    RRA:AVERAGE:0:3:38112 \
    RRA:AVERAGE:0:12:175680 \
    RRA:MIN:0:1:2304 \
    RRA:MIN:0:3:38112 \
    RRA:MIN:0:12:175680 \
    RRA:MAX:0:1:2304 \
    RRA:MAX:0:3:38112 \
    RRA:MAX:0:12:175680
fi

# try to fetch the data from pv
STATUS="FAIL"
for TRY in {1..10}
do
  echo "Fetching data from inverter $PV_URI (#$TRY)"
  if OUT=$(curl -s -S -n "$PV_URI" | grep "^var webdata")
  then
    WATT=$(grep webdata_now_p <<< "$OUT" | cut -d\" -f2)
    if [ -n "$WATT" ]
    then
      # update the rrd and write the js data file
      echo "$OUT" > "$DATA_FILE"
      echo "var last_refresh=$(date +%s)" >> "$DATA_FILE"
      rrdtool update "$RRD_FILE" "N:$WATT"
      STATUS="OK"
      break
    fi
  fi
  RETRY=$(( 3*TRY ))
  echo "Error, retrying in ${RETRY}s"
  sleep "$RETRY"
done

if [ "$STATUS" = "FAIL" ]
then
  echo "Error fetching data from inverter"
  exit 1
fi

# update graph in cronjob interval
rrdtool graph "$GRAPH_DIR/last_8h.svg" \
  -t "Last 8 hours" --end now --start end-8h \
  $RRD_OPTS_EXACT > /dev/null

rrdtool graph "$GRAPH_DIR/last_day.svg" \
  -t "Last day" --end now --start end-1d \
  $RRD_OPTS_EXACT > /dev/null

# update other graphs hourly
if [ ! -f "$GRAPH_DIR/last_week.svg" ] ||
   [ "$(( $(date +"%s") - $(stat -c "%Y" "$GRAPH_DIR/last_week.svg") ))" -gt "3600" ]
then
  rrdtool graph "$GRAPH_DIR/last_week.svg" \
    -t "Last week" --end now --start end-7d \
    $RRD_OPTS_EXACT > /dev/null

  rrdtool graph "$GRAPH_DIR/last_month.svg" \
    -t "Last month" --end now --start end-31d \
    $RRD_OPTS_FUZZY > /dev/null

  rrdtool graph "$GRAPH_DIR/last_3months.svg" \
    -t "Last 3 months" --end now --start end-93d \
    $RRD_OPTS_FUZZY > /dev/null

  rrdtool graph "$GRAPH_DIR/last_year.svg" \
    -t "Last year" --end now --start end-366d \
    $RRD_OPTS_FUZZY > /dev/null
fi

exit 0
