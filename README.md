About nrkcache
==============

The [sizeable](https://nrkbeta.no/2015/03/02/50-000-tv-program-nar-du-vil/)
Video-on-Demand offerings of the [Norwegian Broadcasting Corporation](https://www.nrk.no/)
can be difficult to watch over a slow or unstable network connection. Programs
recorded at 720p quality often have average data rates in excess of
2500 kbit/s (300 KiB/s), which even today is often unavailable in rural areas
underserved by commercial telcos. Additionally, some network connections,
particularly those that rely on certain wireless technology or ancient copper
wiring, are so unstable that local caching is the only way to watch a video
from the internet uninterrupted at *any* quality setting.

This script aims to prevent modern incarnations of “film tear” by creating
just such a local cache of [HTTP Live Streaming](https://en.wikipedia.org/wiki/HTTP_Live_Streaming)
segments, then combining them into a single MPEG-4 container supported by many
modern video players. It is specially designed for the NRK Video-on-Demand
offering and will not work with other HLS sources without modification.


System Requirements
-------------------

- Perl
- Bash
- cURL
- FFmpeg


Contributing
------------

The script works, but could probably use a lot of polishing. All contributions
are welcome. Simply create a new issue or a pull request.


Legal Considerations
--------------------

Use of this script would appear to be legal in Germany, falling under both of
the caching exceptions laid down in [§ 44a UrhG](http://www.gesetze-im-internet.de/urhg/__44a.html).
The Norwegian [Åndsverkloven § 11a](https://lovdata.no/dokument/NL/lov/1961-05-12-2/KAPITTEL_2-2#%C2%A711a)
seems to contain the same exceptions.
Use would apparently also be legal in the U.S. under the “fair use” doctrine.

That said, any use of this script is *your* responsibility. In particular, you
probably shouldn’t share your locally cached copies of NRK content with other
people. Doing so would likely constitute a copyright infringement on your
part.

This script is in the Public Domain.

[![CC0](https://licensebuttons.net/p/zero/1.0/80x15.png)](https://creativecommons.org/publicdomain/zero/1.0/)
