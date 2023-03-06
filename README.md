About nrkcache
==============

The [sizeable](https://nrkbeta.no/2015/03/02/50-000-tv-program-nar-du-vil/)
Video-on-Demand offerings of the [Norwegian Broadcasting Corporation](https://www.nrk.no/)
can be difficult to watch over a slow or unstable network connection. Programs
recorded at 1080p quality often have average data rates in excess of
4500 kbit/s (550 KiB/s), which even today is sometimes unavailable in rural areas
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

- [Perl](https://www.perl.org/) 5.37.9+
- [FFmpeg](https://ffmpeg.org/)
- [YT-dlp](https://github.com/yt-dlp/yt-dlp#readme)
  (some alternatives are supported as well)


Installation
------------

Released versions of [`nrkcache`](https://metacpan.org/release/Video-NRK-Cache)
may be installed via [CPAN](https://www.cpan.org/modules/INSTALL.html):

	cpanm Video::NRK::Cache

[![CPAN distribution](https://badge.fury.io/pl/Video-NRK-Cache.svg)](https://badge.fury.io/pl/Video-NRK-Cache)

To install a development version from this repository, run the following steps:

```sh
git clone https://github.com/johannessen/nrkcache
cd nrkcache
cpanm Dist::Zilla::PluginBundle::Author::AJNN
dzil install
```

You can also try to run `nrkcache.pl` directly from the repository
directory without installing the software, but this method is only
provided for backwards compatibility and may not work very reliably.


Contributing
------------

All contributions
are welcome. Simply create a new issue or a pull request.

This is a “Pure Perl” distribution, which means you don’t need
[Dist::Zilla][] to contribute patches. You can simply clone
the repository and run the test suite using `prove` instead.

[Dist::Zilla]: https://metacpan.org/release/Dist-Zilla


Legal Considerations
--------------------

Use of this script would appear to be legal in Germany, falling under both of
the caching exceptions laid down in [§ 44a UrhG](http://www.gesetze-im-internet.de/urhg/__44a.html).
The Norwegian [Åndsverkloven § 4](https://lovdata.no/dokument/NL/lov/2018-06-15-40#%C2%A74)
seems to contain the same exceptions – not surprising, since both laws are
[implementations of the InfoSoc Directive (2001/29/EC)](http://copyrightexceptions.eu/).
Use would apparently also be legal in the U.S. under the “fair use” doctrine.

That said, any use of this script is *your* responsibility. In particular, you
probably shouldn’t share your locally cached copies of NRK content with other
people. Doing so would likely constitute a copyright infringement on your
part.

This script is in the Public Domain.

[![CC0](https://licensebuttons.net/p/zero/1.0/80x15.png)](https://creativecommons.org/publicdomain/zero/1.0/)


Alternatives
------------

The following alternatives to **nrkcache** (this script) are known.

- [**nrk-download**](https://github.com/marhoy/nrk-download) is another
  solution specific to NRK that supports downloading entire series of
  TV shows in one go. It automatically embeds subtitles into the video
  file, but does not seem to offer meta data retrieval.

- [**yt-dlp**](https://github.com/yt-dlp/yt-dlp) is being
  maintained very well and is the backend used by **nrkcache** since
  version 3. It offers a great deal of configurability, which may make
  its use more complicated in certain cases.

- [**svtplay-dl**](https://github.com/spaam/svtplay-dl) purports
  supporting NRK as well.

- **nrkcache** [version 1](https://github.com/johannessen/nrkcache/tree/all_segments)
  is no longer working properly after changes to NRK's HTML pages.
  However, its component scripts may be useful individually in some
  rare cases.
