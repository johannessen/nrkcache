#! /bin/bash

#set -x

key="$1"
url="$2"
if [ ! "$key" ]
then
	echo "need key"
	exit
fi
if [ ! "$url" ]
then
	url="https://tv.nrk.no/programsubtitles/$key"
fi

key=`echo "$key" | sed -e 's|^/programsubtitles/||'`

xml="$key.ttml"
srt="$key.srt"

if [ -e "$srt" ]
then
	echo "$srt exists; stopping"
	exit 1
fi

curlexit=0
if [ -e "$xml" ]
then
	echo "$xml exists; skipping download"

else
	curl -o "$xml" "$url"
	curlexit=$?
fi

if [[ $curlexit -gt 0 || ! -e "$xml" ]]
then
	echo "download failed; cURL exit code: $curlexit; stopping"
	exit 1
fi

tr "\r\t\n" " " < "$xml" | sed -e 's/  */ /g' | xsltproc "`dirname \"$0\"`/w3ctt2srt.xsl" - > "$srt"

#if [ "$2" ]
#then
#	ln "$srt" "all_segments.srt"
#fi

wc -l "$srt"

# https://gist.github.com/anonymous/4064786
