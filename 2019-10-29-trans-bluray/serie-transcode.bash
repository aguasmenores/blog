#!/bin/bash

c=1
for i in *; do
    printf -v CH %02d $c
    ~/parallel_encoding.awk -i "$i" -o $VIDEOS/series/'chernobyl 2019'/"Chernobyl 2019 T01E$CH 1080p x265 opus eng fra spa cze.mkv" -x "-metadata title=\"Chernobyl 2019 T01E$CH\""
    ((c=c+1))
done
