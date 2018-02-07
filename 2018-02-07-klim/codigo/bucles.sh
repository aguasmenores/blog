#!/bin/bash

#    Aquest codi permet mostrejar la sortida de les comandes smartctl, sensors i cpufreq-info
#    Copyright (C) 2018 Federico Trillo
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.


for ((i=0;<100;i+=1)); do \
    sudo smartctl -A /dev/sda | \
    gawk ' { if ($line ~ /Temperature_Celsius/) print $10}' - >> hdd-temp-0.txt; \
    sleep 5; \
done
for ((i=0;i<100;i+=1)); do \
    sensors | \
    gawk 'BEGIN{FPAT="[0-9]*\\.[0-9]"}{ if ($line ~ /Core/) printf "%s ", $1}END{printf "\n"}' - &gt;&gt; core-temps-0.txt; \
    sleep 5; \
done
for ((i=0;i<100;i+=1)); do \
    echo $(cpufreq-info | \
    grep 'current CPU frequency' | \
    grep -o '[0-9]\.[0-9]*' | \
    tr '\n' ' ') >> thread-freqs-0.txt; \
    sleep 5; \
done

ffmpeg -i bdremux.mkv -vcodec libx264 -preset slower -profile:v high -level 4.1 \
-crf 18 -acodec libvorbis -aq 8 -scodec copy -map 0:v -map 0:s \
-map 0:1 -map 0:3 -map 0:4 -map 0:5 -map 0:6 \
bdrip.mkv
