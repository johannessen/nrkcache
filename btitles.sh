#! /bin/bash

#set -x

key="$1"
if [ ! "$key" ]
then
	echo "need key"
	exit
fi

xml="$key.xml"
srt="$key.xml.srt"

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
	curl -o "$xml" "https://tv.nrk.no/programsubtitles/$key"
	curlexit=$?
fi

if [[ $curlexit -gt 0 || ! -e "$xml" ]]
then
	echo "download failed; cURL exit code: $curlexit; stopping"
	exit 1
fi

tr "\r\t\n" " " < "$xml" | sed -e 's/  */ /g' | xsltproc "`dirname \"$0\"`/w3ctt2srt.xsl" - > "$srt"

wc -l "$srt"

# https://gist.github.com/anonymous/4064786
