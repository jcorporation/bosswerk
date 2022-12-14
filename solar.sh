#!/bin/bash

# SPDX-License-Identifier: GPL-3.0-or-later
# myMPD (c) 2022 Juergen Mang <mail@jcgames.de>
# https://github.com/jcorporation

# strict mode
set -euo pipefail

BASE_DIR=$(dirname "$(realpath "$0")")     # path of the script
WWW_DIR="$BASE_DIR/www"                    # doc root
GRAPH_DIR="$WWW_DIR/graphs"                # dir for the rrd graphs
JSON_FILE="$WWW_DIR/data/data.json"        # the json file with current data
RRD_FILE="$BASE_DIR/rrd/solar.rrd"         # the rrd data file

# rrd options
RRD_OPTS="--imgformat SVG -w 800 -h 300 -l 0 -u 600 --slope-mode"
RRD_OPTS="$RRD_OPTS --full-size-mode -g --border 0"
RRD_OPTS="$RRD_OPTS -c BACK#1d2124 -c FONT#f8f9fa"
RRD_OPTS="$RRD_OPTS -c CANVAS#212529 -c MGRID#f8f9fa -c GRID#6c757d -c ARROW#6c757d"
RRD_OPTS="$RRD_OPTS -n TITLE:12:. -n AXIS:8.5:. -n UNIT:8.5:."
RRD_OPTS="$RRD_OPTS DEF:watts_avg=$RRD_FILE:watts:AVERAGE"
RRD_OPTS="$RRD_OPTS DEF:watts_min=$RRD_FILE:watts:MIN"
RRD_OPTS="$RRD_OPTS DEF:watts_max=$RRD_FILE:watts:MAX"

# for exact graphs (max = min = avg)
RRD_OPTS_EXACT="$RRD_OPTS AREA:watts_max#7eca90:Max"
RRD_OPTS_EXACT="$RRD_OPTS_EXACT LINE2:watts_avg#28a745:Watt"

# for more fuzzy graphs
RRD_OPTS_FUZZY="$RRD_OPTS AREA:watts_max#7eca90:Max"
RRD_OPTS_FUZZY="$RRD_OPTS_FUZZY AREA:watts_min#212529:Min"
RRD_OPTS_FUZZY="$RRD_OPTS_FUZZY LINE2:watts_avg#28a745:Watt"

# goto script dir
cd "$BASE_DIR" || exit 1

# get config
source .config

# check for PV_URI
if [ -z "${PV_URI+x}" ]
then
  echo "PV_URI not defined"
  exit 1
fi

# check for rrd file
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
STATUS="NOT REACHABLE"
for TRY in {1..10}
do
  echo "Fetching data from inverter $PV_URI (#$TRY)"
  if OUT=$(curl -s -S -n "$PV_URI" | grep "^var webdata")
  then
    WATT=$(grep webdata_now_p <<< "$OUT" | cut -d\" -f2)
    if [ -n "$WATT" ]
    then
      STATUS="OK"
      # write the json data
      printf "{\n" > "$JSON_FILE"
      sed -E 's/var (webdata_.+) = "(.*)";/\t"\1": "\2",/' <<< "$OUT" >> "$JSON_FILE"
      printf "\t\"status\": \"%s\",\n" "$STATUS" >> "$JSON_FILE"
      printf "\t\"last_refresh\": %s\n}\n" "$(date +%s)" >> "$JSON_FILE"
      # update the rrd
      rrdtool update "$RRD_FILE" "N:$WATT"
      break
    fi
  fi
  RETRY=$(( 3*TRY ))
  echo "Error, retrying in ${RETRY}s"
  sleep "$RETRY"
done

if [ "$STATUS" != "OK" ]
then
  echo "Error fetching data from inverter"
  printf "{\n" > "$JSON_FILE"
  printf "\t\"status\": \"%s\",\n" "$STATUS" >> "$JSON_FILE"
  printf "\t\"last_refresh\": %s\n}\n" "$(date +%s)" >> "$JSON_FILE"
  exit 1
fi

# update graphs in cronjob interval
rrdtool graph "$GRAPH_DIR/last_8h.svg" \
  -t "Last 8 hours\n\n" --end now --start end-8h \
  $RRD_OPTS_EXACT > /dev/null

rrdtool graph "$GRAPH_DIR/last_day.svg" \
  -t "Last day\n\n" --end now --start end-26h \
  $RRD_OPTS_EXACT > /dev/null

# update other graphs hourly
if [ ! -f "$GRAPH_DIR/last_week.svg" ] ||
   [ "$(( $(date +"%s") - $(stat -c "%Y" "$GRAPH_DIR/last_week.svg") ))" -gt "3600" ]
then
  rrdtool graph "$GRAPH_DIR/last_week.svg" \
    -t "Last week\n\n" --end now --start end-8d \
    $RRD_OPTS_EXACT > /dev/null

  rrdtool graph "$GRAPH_DIR/last_month.svg" \
    -t "Last month\n\n" --end now --start end-32d \
    $RRD_OPTS_FUZZY > /dev/null

  rrdtool graph "$GRAPH_DIR/last_3months.svg" \
    -t "Last 3 months\n\n" --end now --start end-93d \
    $RRD_OPTS_FUZZY > /dev/null

  rrdtool graph "$GRAPH_DIR/last_year.svg" \
    -t "Last year\n\n" --end now --start end-367d \
    $RRD_OPTS_FUZZY > /dev/null
fi

exit 0
