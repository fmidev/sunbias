#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Copyright (c) 2024 Finnish Meteorological Institute
#

PROG_BASENAME=$(basename $0)

ARG_WORKDIR=$(pwd)
URL_SOLAR_REGIONS="https://services.swpc.noaa.gov/json/solar_regions.json"
DATE_30DAYS_AGO=$(date -u --date="$(date -u +"%Y%m%d -30 day")" +%Y-%m-%d)
DATE_YESTERDAY=$(date -u --date="$(date -u +"%Y%m%d -1 day")" +%Y-%m-%d)
DATE_TODAY=$(date -u +%Y-%m-%d)


ARG_DATE=${DATE_30DAYS_AGO}
ARG_DATA=""
ARG_GRAPHICS=()
GRAPHIC_CODES=(bias-el bias-az regions-count regions-area spots-count)
ARG_SIGN_CHANGE=()
SIGN_CHANGE_CODES=(bias-el bias-az)

timestamp_enable=1


Help()
{
  echo -n -e "Usage: ${PROG_BASENAME} [OPTIONS]\n" \
    "\nCalculate bias estimates of solar radiation at weather radar bands based on the solar regions data of NOAA." \
    "\n" \
    "\nOptions:" \
    "\n        --workdir        directory to handling and store data, default: execution directory of the script" \
    "\n        --date-start     a start date of the target data set in format YYYY-mm-dd, default: 30 days ago" \
    "\n        --data           print the data" \
    "\n        --graphics <>    print graphics, supported codes: ${GRAPHIC_CODES[*]}" \
    "\n        --sign-change <> change the sign of result values, supported codes: ${SIGN_CHANGE_CODES[*]}" \
    "\n" \
    "\nExamples:\n" \
    "       ${PROG_BASENAME} --workdir ~/ --data --sign-change bias-az --graphics bias-az" \
    "\n\n"
}


function timestamp()
{
  if [ ${timestamp_enable} -eq 1 ]; then
    echo -n "$(date -u '+%Y-%m-%d %H:%M:%S') "
  fi
}
function log_info() {
  timestamp
  echo "[INFO] ${PROG_BASENAME}: $1";
}
function log_warning() {
  timestamp
  echo "[WARNING] ${PROG_BASENAME}: $1";
}
function log_error() {
  timestamp
  echo "[ERROR] ${PROG_BASENAME}: $1";
}

# Read command line arguments
while [ -n "$1" ]; do # while loop starts
        case "$1" in
            --workdir)
                    ARG_WORKDIR="$(readlink -f $2)"
                    if [ ! -d ${ARG_WORKDIR} ]; then
                        log_error "Workdir argument value '$2' is not a directory"
                        exit 1
                    fi
                    shift
                    ;;
            --date-start)
                    ARG_DATE="$2"

                    # Parse values like '3 days ago' and convert to ISO date.
                    re_days_ago_pattern='^[1-9]{1}[0-9]{0,1}\ (day|days) ago$';
                    if [[ ${ARG_DATE} =~ ${re_days_ago_pattern} ]]; then
                        ago_val=${ARG_DATE/ ago/}
                        ARG_DATE=$(date -u --date="$(date -u +"%Y%m%d -${ago_val}")" +%Y-%m-%d)
                    fi

                    if [ ${#ARG_DATE} != 10 ]; then
                        log_error "Invalid date argument value '$2' (YYYY-mm-dd)"
                        exit 1
                    fi

                    # Check the date notation is ok.
                    re='^[0-9]{4}-(0[1-9]{1}|1[0-2]{1})-(0[1-9]{1}|[1-2]{1}[0-9]{1}|3[0-1]{1})$'
                    if ! [[ ${ARG_DATE} =~ $re ]] ; then
                        log_error "Invalid '--date-start' argument value '$2'. Not a date"
                        exit 1
                    fi
                    shift
                    ;;
            --data)
                ARG_DATA="enabled"
                ;;
            --graphics)
                while [ -n "$2" ] && [ "${2:0:1}" != "-" ]; do
                    gcode=""
                    for gval in ${GRAPHIC_CODES[*]}; do
                       if [ "${gval}" == "$2" ]; then
                           gcode="$2"
                       fi
                    done
                    if [ -z "${gcode}" ]; then
                        log_error "Invalid --graphics code '$2'. Supported codes are: ${GRAPHIC_CODES[*]}"
                        exit 1
                    else
                        ARG_GRAPHICS+=("$gcode")
                    fi
                    shift
                done
                ;;
            --sign-change)
                while [ -n "$2" ] && [ "${2:0:1}" != "-" ]; do
                    icode=""
                    for ival in ${SIGN_CHANGE_CODES[*]}; do
                       if [ "${ival}" == "$2" ]; then
                           icode="$2"
                       fi
                    done
                    if [ -z "${icode}" ]; then
                        log_error "Invalid --sign-change code '$2'. Supported codes are: ${SIGN_CHANGE_CODES[*]}"
                        exit 1
                    else
                        ARG_SIGN_CHANGE+=("$icode")
                    fi
                    shift
                done
                ;;
            --help | -h)
                Help
                exit 0
                ;;
            *)
                log_error "option $1 not recognized. "
                log_info "Try '${PROG_BASENAME} --help' for more information."
                exit 1
                ;;
        esac
        shift
done


ret=0


# Test the date given is between 30 days ago and yesterday.
let DIFF=$(($(($(date -u --date="${DATE_YESTERDAY}" +%s) - $(date -u --date="${ARG_DATE}" +%s)))/86400))
if [ $DIFF -gt 30 ]; then
    log_error "date must be between 30 days ago and yesterday."
    exit 1
fi
if [ $DIFF -lt 0 ]; then
    log_error "date must be between 30 days ago and yesterday."
    exit 1
fi

# Set start and end date
DATE_START=${ARG_DATE}
DATE_END=${DATE_YESTERDAY}
FILENAME="${ARG_WORKDIR}/solar_regions.json"
# Backup name
FILENAME_MONTH="${ARG_WORKDIR}/solar_regions.json.${DATE_YESTERDAY:0:7}"

# Download the datafile is not exist
if [ ! -f ${FILENAME} ]; then
    wget -q $URL_SOLAR_REGIONS -O ${FILENAME}
    ret=$?
    if [ $ret -ne 0 ]; then
        log_error "Wget failed to download data file and returned exit code ${ret}. "\
                  "See the description of the code from the man pages of wget (EXIT STATUS).";
        exit 1
    fi
fi

# Update the data file if it is too old.
updated_n_seconds_ago=$(($(date -u +%s) - $(stat -c %Y ${FILENAME})))
if [ ${updated_n_seconds_ago} -gt 3600 ]; then
    wget -q ${URL_SOLAR_REGIONS} -O ${FILENAME};
    ret=$?
    if [ $ret -ne 0 ]; then
        log_error "Wget failed to update data file and returned exit code ${ret}. "\
                  "See the description of the code from the man pages of wget (EXIT STATUS).";
        exit 1
    fi
    cp -a ${FILENAME} ${FILENAME_MONTH}
fi

# Check the end date is in the file.
if ! grep -q "${DATE_END}" ${FILENAME} ; then
    log_error "${FILENAME} data doesn't include ${DATE_END} day data";
    exit 1
fi

SIGN_CHANGE=${ARG_SIGN_CHANGE[*]}
py_out=$(
python3 << EOF
import numpy as np;
import pandas as pd;

# Change the sign of values, default is not to change
sign_change = {"bias-az": 1.0, "bias-el": 1.0 }
for k in "${SIGN_CHANGE}".split(" "):
    if len(k.strip()) > 0:
        sign_change[k] = -1.0

# Load the json file
solar_regions = pd.read_json("${FILENAME}");

# Target data set by start date and end date
tdata=solar_regions.loc[solar_regions.observed_date.between("${DATE_START}","${DATE_END}")]

# Loop unique dates in sorted order.
for d in sorted(tdata.observed_date.unique()):
    # Select only the data we want
    tmp=tdata.loc[tdata.observed_date.eq(d) &
                  tdata.longitude.between(-90.0,90.0) &
                  tdata.latitude.between(-90.0, 90.0) &
                  tdata.area.ge(1) &
                  tdata.number_spots.ge(1)
	         ].get(["observed_date","latitude","longitude","area","extent","number_spots"]);

    # Move to the next day if there are no values.
    if tmp is None or tmp.shape[0] < 1:
        continue

    # Calculate scaling parameters
    attenuate=5.0
    scale_lon=1.0/(1.0 + np.exp(attenuate-tmp.shape[0]))
    scale_lat=1.0/(1.0 + np.exp(attenuate-tmp.shape[0]))

    # Print the data
    print("{:>10s}    {:>9.3f}    {:>9.3f}     {:>9.0f}  {:>9.0f}        {:>9.0f}".format(
        d,
        sign_change["bias-el"]*scale_lat*np.sum(np.sin(np.pi*tmp["latitude"]/180)*tmp["extent"])/np.sum(tmp["extent"])/tmp.shape[0],
	sign_change["bias-az"]*scale_lon*np.sum(np.sin(np.pi*tmp["longitude"]/180)*tmp["extent"])/np.sum(tmp["extent"])/tmp.shape[0],
        tmp.shape[0],
        np.sum(tmp["area"]),
        np.sum(tmp["number_spots"])
	))
EOF
)

# Print the data if enabled
if [ "${ARG_DATA}" == "enabled" ]; then
echo -e  "date        bias_el_est  bias_az_est  region_count   area_tot number_spots_tot\n$py_out"
fi

dumptype=
#dumbtype=ansi256
aspect=
#aspect="aspect 1"
dumb_size="size 81,26"


# Print graphics if enabled
for gval in ${ARG_GRAPHICS[*]}; do
echo -e "\n"

if [ "${gval}" == "bias-el" ]; then
printf "$py_out\n\n" | gnuplot -p -e "set terminal dumb ${dumbtype} ${dumb_size} ${aspect};
 set title 'Elevation bias estimate, ${DATE_TODAY} ';
 set timefmt \"%Y-%m-%d\";
 set xdata time;
 set format x \"%d\";
 set yrange [*<-0.1:0.1<*];
 plot '-' u 1:2 with impulse ls 1 title ''"
fi

if [ "${gval}" == "bias-az" ]; then
printf "$py_out\n" | gnuplot -p -e "set terminal dumb ${dumbtype} ${dumb_size} ${aspect};
 set title 'Azimuth bias estimate, ${DATE_TODAY}';
 set timefmt \"%Y-%m-%d\";
 set xdata time;
 set format x \"%d\";
 set yrange [*<-0.1:0.1<*];
 plot '-' u 1:3 with impulse ls 1 title ''"
fi

if [ "${gval}" == "regions-count" ]; then
printf "$py_out\n" | gnuplot -p -e "set terminal dumb ${dumbtype} ${dumb_size} ${aspect};
 set title 'Sunspot region count, ${DATE_TODAY}';
 set timefmt \"%Y-%m-%d\";
 set xdata time;
 set format x \"%d\";
 set yrange [0:20<*];
 plot '-' u 1:4 with impulse ls 1 title ''"
fi

if [ "${gval}" == "regions-area" ]; then
printf "$py_out\n" | gnuplot -p -e "set terminal dumb ${dumbtype} ${dumb_size} ${aspect};
 set title 'Total area of sunspot regions, ${DATE_TODAY}';
 set timefmt \"%Y-%m-%d\";
 set xdata time;
 set format x \"%d\";
 set yrange [0:100<*];
 plot '-' u 1:5 with impulse ls 1 title ''"
fi

if [ "${gval}" == "spots-count" ]; then
printf "$py_out\n" | gnuplot -p -e "set terminal dumb ${dumbtype} ${dumb_size} ${aspect};
 set title 'Total number of sunspots, ${DATE_TODAY}';
 set timefmt \"%Y-%m-%d\";
 set xdata time;
 set format x \"%d\";
 set yrange [0:20<*];
 plot '-' u 1:6 with impulse ls 1 title ''"
fi

done
