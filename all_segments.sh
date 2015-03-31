#! /bin/bash

#base='http://nordond39b-f.akamaihd.net/i/no/open/6b/6b38cb77479d4f91c6e34f0b876bb8325344c6bf/8578245e-3c44-4588-a809-fb9ff03fae71_,141,316,563,1266,2250,.mp4.csmil'
#count=700


base="$1"
count="$2"

nameprefix=segment
namesuffix=_4_av.ts


if [ ! "$base" ]
then
	echo "need base"
	exit
fi
if [ ! "$count" ]
then
	echo "need count"
	exit
fi

# load all segments if none are present
# -> no, don't; type (18) errors can't be caught

# empty=yes
# for i in `seq 1 $count`
# do
# 	f="$nameprefix$i$namesuffix"
# 	if [ -e "$f" ]
# 	then
# 		empty=
# 	fi
# done
# if [ $empty ]
# then
# 	f="$nameprefix[1-$count]$namesuffix"
# 	curl -O "$base/$f" -D "headers.txt"
# fi


# make sure it's complete
complete=
while [ ! $complete ]
do
	complete=yes
	for i in `seq 1 $count`
	do
		f="$nameprefix$i$namesuffix"
		if [ ! -e "$f" ]
		then
			complete=
			echo "$f"
			curl -O "$base/$f"
			
			curlexit=$?
			if [ $curlexit -eq 18 ]
			then
				rm "$f"
			elif [ $curlexit -gt 0 ]
			then
				echo "cURL exit code: $curlexit; stopping"
				exit $curlexit
			fi
		fi
	done
done



ls "$nameprefix"* | cut -c 8-99 | sort -n > list
rm -f all_segments.ts
while read f ; do cat "segment$f" >> all_segments.ts ; done < list

#ffmpeg -i all_segments.ts -vcodec copy -acodec copy -bsf:a aac_adtstoasc -scodec copy all_segments.mp4
ffmpeg -i all_segments.ts -vcodec copy -acodec copy -bsf:a aac_adtstoasc all_segments.mp4

rm all_segments.ts


# DVD 960x540 = approx. 1.73 MB/segment
# HD 1280x720 = approx. 3.01 MB/segment

# curl: (18) transfer closed with 2475808 bytes remaining to read

# ^ [ 0-9][0-9]
