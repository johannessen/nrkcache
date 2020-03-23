#! /usr/bin/env perl

use strict;
use warnings;
use 5.014;

our $VERSION = 1.17;

# TODO: Segments that are unavailable in the requested quality should perhaps automatically be re-downloaded in another quality. I guess one of the main problems would be how to report that to the user.
# TODO: There should be an -n flag to control the niceness on cURL (e.g. --limit-rate 800k; with -nn yielding 400k, which may approximately be real-time q4; -nnn 200k/s)
# TODO: Sourcing the program ID from the provided URL (if possible) is probably the most reliable option. Parsing it from NRK's changing HTML file is rather brittle and should not be attempted unless really necessary.

use scriptname;
use File::DirList;
use File::Copy;
use File::Basename;
use Getopt::Long 2.33 qw( :config posix_default gnu_getopt auto_version auto_help );
use Pod::Usage;
use Data::Dumper;
use HTML::Entities qw();
use open ":std", ":encoding(UTF-8)";

# parse CLI parameters
my %options = (
	infoonly => 0,
	man => undef,
	master_name => 'master.m3u8',
	quality => -1,
	verbose => 1,
	any => undef,
	part => undef,
	index_base => undef,
	dir => 0,
	comment => undef,  # ignored!
	http_header => undef,
);
GetOptions(
	'verbose|v+' => \$options{verbose},
	'man' => \$options{man},
	'masterfile-name=s' => \$options{master_name},
	'quality|q=i' => \$options{quality},
	'any|a' => \$options{any},
	'part|p=i' => \$options{part},
	'info-only|I' => \$options{infoonly},
	'base|b=s' => \$options{index_base},
	'mkdir|d' => \$options{dir},
	'comment|c=s' => \$options{comment},
	'http-header|H=s' => \$options{http_header},
) or pod2usage(2);
pod2usage(-exitstatus => 0, -verbose => 2) if $options{man};

# make sure we have everything we need
$options{quality} = 0 + $options{quality};

# cases:
# 0 arguments => current dir, master file
# 1 argument - path to dir or master file => use master file's dir and master file
# 1 argument - URL => download master file to current dir
# 2 arguments => download master file to dir

# strategy: try locally first, only get master file if we miss information

my $MASTER_NAME = $options{master_name};
my $targetdir;
my $masterfile;
my $nrkurl;
if (0 == scalar @ARGV) {
	$targetdir = '.';
	$masterfile = $MASTER_NAME;
	if ( ! -f $masterfile ) {
		pod2usage(-exitstatus => 3, -verbose => 0, -message => 'Missing required input file names.');
	}
	print STDERR "case 0\n" if $options{verbose};
}
elsif (1 == scalar @ARGV) {
	$targetdir = dirname $ARGV[0];
	$masterfile = $ARGV[0] . '/' . $MASTER_NAME;
	if ( $ARGV[0] =~ m/\Q$MASTER_NAME\E$/ && -f $ARGV[0] ) {
		# example: dir1/master.m3u8
		$masterfile = $ARGV[0];
		$targetdir = dirname $masterfile;
		print STDERR "case 1a\n" if $options{verbose} >= 2;
	}
	elsif ( -d $ARGV[0] && -f $masterfile ) {
		# example: dir1
		$targetdir = $ARGV[0];
		print STDERR "case 1b\n" if $options{verbose} >= 2;
	}
	elsif ( -d $targetdir && -f "$targetdir/$MASTER_NAME" ) {
		# example: dir1/someotherfile - this doesn't seem very useful actually
		$masterfile = "$targetdir/$MASTER_NAME";
		print STDERR "case 1c\n" if $options{verbose} >= 2;
	}
	elsif ( $ARGV[0] =~ m/^https?:/ ) {
		$targetdir = '.';
		$nrkurl = $ARGV[0];
		$masterfile = $MASTER_NAME;
		print STDERR "case 1d\n" if $options{verbose} >= 2;
	}
	else {
		pod2usage(-exitstatus => 3, -verbose => 0, -message => 'Could not parse master file, target dir or download URL from argument.');
	}
}
elsif (2 == scalar @ARGV) {
	$targetdir = $ARGV[0];
	if ( ! -d $targetdir ) {
		if ($options{dir}) {
			`mkdir -p "$targetdir"`;
		}
		else {
			pod2usage(-exitstatus => 3, -verbose => 0, -message => 'Could not parse target dir from first argument.');
		}
	}
	$masterfile = "$targetdir/$MASTER_NAME";
	if ( $ARGV[1] =~ m/^https?:/ ) {
		$nrkurl = $ARGV[1];
	}
	else {
		pod2usage(-exitstatus => 3, -verbose => 0, -message => 'Could not parse download URL from second argument.');
	}
	print STDERR "case 2\n" if $options{verbose};
}
else {
	pod2usage(-exitstatus => 3, -verbose => 0, -message => 'Too many arguments.');
}

print STDERR "Target Dir: $targetdir  (Master File:  $masterfile)\n" if $options{verbose};
print STDERR "Download URL: $nrkurl\n" if $nrkurl && $options{verbose};



my @hls_cookie_params = ("-b", "NRK_PLAYER_SETTINGS_RADIO=preferred-player-odm=hlslink,NRK_PLAYER_SETTINGS_TV=preferred-player-odm=hlslink");
@hls_cookie_params = ("-b", "NRK_PLAYER_SETTINGS_TV=preferred-player-odm=hlslink") unless $options{any};  # not sure why this is necessary; check curl docs

my @http_header = ();
@http_header = ("-H", $options{http_header}) if $options{http_header};

my $base = $options{index_base};
my $count = '';
my $type;
my $suffix;
my $query;
my $programid;

my $thisdir = `pwd`;
chomp $thisdir;
chdir $targetdir;

if ( -e 'all_segments.mp4' ) {
	print "\n", `pwd`, "all_segments.mp4 exists. skipping.\n\n";
	exit 0;
}


my $nrkinfo = {};
if ($nrkurl) {
	# get all info from programme web page
	print STDERR "Downloading NRK page...\n" if $options{verbose};
	my $pagefile = "no.nrk.tv.programmepage.html";
	if ( $nrkurl =~ m|/([A-Z]{4}[0-9]{8})/|i ) {
		$pagefile = "$1.html";
	}
	system "curl", @hls_cookie_params, @http_header, "-L", "-o", $pagefile, "$nrkurl" unless -f $pagefile;
	
	if ( $nrkurl =~ m{/([A-Z]{4}[0-9]{8})/?}i ) {
		$nrkinfo->{programid} = $1;
	}
	my $Seriebeskrivelse = 0;
	my $nrkinfo_ignore = {
		'apple-mobile-web-app-title' => 1,
		'fb:app_id' => 1,
		'google-site-verification' => 1,
		'og:image' => 1,
		'viewport' => 1,
#		'artikkel_frimerke' => 1,
		'og:site_name' => 1,
#		'series_frimerke' => 1,
	};
	local *NRKPAGE;
	open NRKPAGE, '<', $pagefile or die $!;
	while (<NRKPAGE>) {
		chomp;
		HTML::Entities::decode_entities $_;
		
		if ( m|<link\s+rel="canonical"\s+href="([^"]+)"|i ) {
			$nrkinfo->{canonical} = $1;
		}
		if ( m{<title>([^<]+)</title>}i ) {
			$nrkinfo->{html_title} = $1;
		}
		if ( m{<meta\s+(?:name|property)="([^"]+)"\s+content="([^"]+)"}i ) {
			$nrkinfo->{$1} = $2 unless $nrkinfo_ignore->{$1};
		}
		if ( m{^\s*programId: "([^"]+)",?}i ) {
			$nrkinfo->{programid} = $1;
		}
		if ( m{\WinitState\W.*"id":"([^"]+)"}i ) {
			$nrkinfo->{programid} = $1;
		}
		if ( ! $nrkinfo->{programid} && m{\bapplication/ld\+json\b.*"\@id":"(?:[^"]*\u002[Ff]|[^"]*/)?([^"]+)"}i ) {
			$nrkinfo->{programid} = $1;
		}
		
		if ( m|data-media\s*=\s*"(http[^"]+)"|i ) {
			$nrkinfo->{playerdata_media} = $1;
		}
		if ( m|data-hls-media\s*=\s*"(http[^"]+)"|i ) {
			$nrkinfo->{playerdata_hls_media} = $1;
		}
		if ( m|data-duration\s*=\s*"([^"]+)"|i ) {
			$nrkinfo->{playerdata_duration} = $1;
		}
		if ( m|data-video-id\s*=\s*"([^"]+)"|i ) {
			$nrkinfo->{playerdata_video_id} = $1;
		}
		if ( m|data-legalage\s*=\s*"([^"]+)"|i ) {
			$nrkinfo->{playerdata_legalage} = $1;
		}
		if ( m|data-subtitlesurl\s*=\s*"([^"]+)"|i ) {
			$nrkinfo->{playerdata_subtitlesurl} = $1;
		}
		if ( m|="([^"]+)"\s*id="playListLink"|i ) {
			$nrkinfo->{playlisturl} = $1;
		}
		
		if ( $Seriebeskrivelse && m|<p>([^<]+)</p>|i ) {
			$nrkinfo->{html_Seriebeskrivelse} = $1;
			$Seriebeskrivelse = 0;
		}
		if ( m|<h3>Seriebeskrivelse</h3>|i ) {
			$Seriebeskrivelse = 1;
		}
		if ( m{<a href="/programreview/|\sid="reviewLink"|\sdata-ga-action="episode-tab-review"}i ) {
			$nrkinfo->{has_review} = 1;
		}
		
		if ( ! $nrkinfo->{mediaelementApiTemplate} && m|\sapiBaseUrl\s*:\s*"([^"]+)"\s*,|i ) {
			$nrkinfo->{mediaelementApiTemplate} = "${1}mediaelement/{id}?inSuperUniverse=False&callback=?";
		}
		if ( m|\smediaelementApiTemplate\s*:\s*"([^"]+)"\s*,|i ) {
			$nrkinfo->{mediaelementApiTemplate} = $1;
		}
		if ( m|\sapiBaseUrl\s*:\s*'([^']+)'\s*,|i ) {
			$nrkinfo->{apiBaseUrl} = $1;
		}
		
	}
	close NRKPAGE;
	
	# TODO: use JSON::XS or something
	
	$programid = $nrkinfo->{programid};
	print STDERR "Program ID: ", ("$programid\n" || "not found!\n") if $options{verbose};
	if ($programid && ( ! $nrkinfo->{playerdata_hls_media} || ! $nrkinfo->{playerdata_subtitlesurl} )) {
		my $mediaelementApiTemplate = $nrkinfo->{mediaelementApiTemplate};
		if (! $mediaelementApiTemplate) {
			my $apiBaseUrl = $nrkinfo->{apiBaseUrl} // "https://psapi-we.nrk.no/" // "https://psapi-ne.nrk.no/";
			# The API is documented at https://psapi.nrk.no/ (old version: v7.psapi.nrk.no)
			$mediaelementApiTemplate = "${apiBaseUrl}mediaelement/{id}";
		}
		$mediaelementApiTemplate =~ s/{id}/$nrkinfo->{programid}/;
		my $mediaelementfile = "$nrkinfo->{programid}.json";
		system "curl", @hls_cookie_params, @http_header, "-o", $mediaelementfile, "$mediaelementApiTemplate";
		local *NRKMEDIA;
		open NRKMEDIA, '<', $mediaelementfile or die $!;
		while (<NRKMEDIA>) {
			chomp;
			if ( ! $nrkinfo->{playerdata_hls_media} && m|"mediaUrl"\s*:\s*"(http[^"]+/)master.m3u8(\?[^"]+)?"|i ) {
				$nrkinfo->{playerdata_hls_media} = "${1}master.m3u8";
				$nrkinfo->{playerdata_hls_media} .= $2 if $2;
				$base = "$1";
			}
			if ( $options{part} && m|"mediaAssets"\s*:\s*\[\s*\{([^\]]*)\}\s*\]|i ) {
				$options{part} = 0 + $options{part};
				print STDERR "Looking for part $options{part}\n" if $options{verbose};
				my @parts = split m/}\s*,\s*{/, $1;
				die "Content has " . scalar(@parts) . " parts" if $options{part} > @parts || $options{part} < 1;
				$parts[$options{part} - 1] =~ m|"url"\s*:\s*"(http[^"]+/)master.m3u8(\?[^"]+)?"|i;
				die "Failed to parse media URL of part $options{part}" unless $1;
				$nrkinfo->{playerdata_hls_media} = "${1}master.m3u8";
				$nrkinfo->{playerdata_hls_media} .= $2 if $2;
				$base = "$1";
			}
			if ( ! $nrkinfo->{playerdata_subtitlesurl} && m|"subtitlesUrlPath"\s*:\s*"(http[^"]+)"|i ) {
				$nrkinfo->{playerdata_subtitlesurl} = "$1";
			}
			if ( m|"description"\s*:\s*"(.+?)"\s*,\s*"|i ) {
				$nrkinfo->{'og:description'} = "$1";
				$nrkinfo->{'og:description'} =~ s/\\r\\n|\\r|\\n/\n/g;
				$nrkinfo->{'og:description'} =~ s/\\"/"/g;
			}
		}
		close NRKMEDIA;
	}
	$nrkinfo->{'nrkurl'} = $nrkinfo->{'og:url'} || $nrkurl;
	
	my ($key, $value);
	open(my $FH, '>', 'report.txt') or die "Could not open file 'report.txt' $!";
	if ($nrkinfo->{'og:description'}) {
		print $FH $nrkinfo->{'og:description'}, " ($programid)", "\n\n";
	}
	print $FH $nrkinfo->{'nrkurl'}, "\n\n";
	if ($nrkinfo->{has_review}) {
		print STDERR "Downloading Review...\n" if $options{verbose};
		my $reviewurl = "https://tv.nrk.no/programreview/" . $nrkinfo->{programid};
		print $FH "\nomtale=\n";
		print $FH `curl $reviewurl`;
		print $FH "\n\n";
	}
	else {
		print STDERR "Review not available.\n" if $options{verbose};
	}
	my $program_title = $nrkinfo->{'title'} || $nrkinfo->{'html_title'} || $nrkinfo->{'og:title'};
	if ($program_title) {
		print $FH $program_title, "\n\n";
	}
	for my $key (sort keys %$nrkinfo) {
		print $FH "$key=$nrkinfo->{$key}\n";
	}
	close $FH;
	
}

if ($nrkinfo->{programid} && $nrkinfo->{'nrkurl'}) {
	open(my $FH, '>', "$nrkinfo->{programid}.webloc") or die "Could not open file '$nrkinfo->{programid}.webloc' $!";
	print $FH <<"END";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>URL</key>
	<string>$nrkinfo->{'nrkurl'}</string>
</dict>
</plist>
END
	close $FH;
}

if ( $options{any} && $nrkinfo->{playlisturl} ) {
	print STDERR "Downloading Playlist...\n" if $options{verbose};
	my $playlisturl = "https://radio.nrk.no/" . $nrkinfo->{playlisturl};
	print STDERR "$playlisturl\n" if $options{verbose};
	system "curl", @http_header, "-o", 'playlist.html', $playlisturl;
}
elsif ( $options{any} ) {
	print STDERR "Playlist not available.\n" if $options{verbose};
}

if ($nrkinfo->{playerdata_subtitlesurl}) {
	print STDERR "Downloading Subtitles...\n" if $options{verbose};
	system scriptname::mydir() . "/btitles.sh", $nrkinfo->{programid}, $nrkinfo->{playerdata_subtitlesurl};
}
else {
	print STDERR "Subtitles not available.\n" if $options{verbose};
}





if ( $options{infoonly} ) {
	exit 0;
}

if ($nrkinfo->{playerdata_hls_media}) {
	print STDERR "Downloading Master File...\n" if $options{verbose};
	system "curl", @http_header, "-o", $MASTER_NAME, $nrkinfo->{playerdata_hls_media};
}
else {
	print STDERR "Master File URL not found on NRK page.\n" if $options{verbose};
}





print STDERR "Parsing $targetdir/$MASTER_NAME...\n";

# find highest type/quality AV offering in master file
local *MASTER;
open MASTER, '<', $MASTER_NAME or die $!;
while (<MASTER>) {
	chomp;
	
	my $regex = '^(https?://.+/)?index_(\d)_av\.([^\s\?]+)(\?\S*)?';
	if ($options{any}) {
		$regex = '^(https?://.+/)?index_(\d)([^\s\?]+)(\?\S*)?';
	}
	m|$regex| or next;
	
	$1 || $base or next;
	defined $2 && $3 or next;
	if ( $type && $2 < $type ) {
		next;
	}
	
	$base ||= $1;
	$type = $2;
	$suffix = $3;
	$query = $4;
	
	if ($options{quality} == $type) {
		last;
	}
}
close MASTER;

if ( ! $base || ! defined $type || ! $suffix ) {
	die "something's unusual about the master file; bailing out";
}

if ($options{quality} >= 0 && $options{quality} != $type) {
	print STDERR "Requested " . ($options{any} ? "'any'" : "AV") . " quality " . $options{quality} . " unavailable, using $type instead.\n";
}

my $indexfile = "index_${type}_av.$suffix";
if ($options{any}) {
	$indexfile = "index_${type}$suffix";
}
$query ||= '';

print STDERR "Index File: type $type, " . ($options{any} ? "'any'" : "AV") . "\n";
print STDERR "Base: $base (suffix: $suffix, query: $query)\n";




system "curl", @http_header, "-o", $indexfile, "$base$indexfile$query" unless -r $indexfile;





#my $indexfile = $ARGV[0];
print STDERR "Parsing $indexfile...\n";

# find last chunk in index file to detect segment count
local *FILE;
open FILE, '<', $indexfile or die $!;
while (<FILE>) {
	chomp;
	
	my $regex = '^(https?://.+/)?segment(\d+)_(\d_[av]+)\.ts(\?\S*)?';
	m|$regex| or next;
	$base ||= $1;
	$count = $2;
	$type = $3;
	$suffix = $4;
	
}
close FILE;

if ( ! $base || ! $count || ! $type ) {
	die "something's wrong with the index file";
}

print STDERR "Segments detected:  $count\n";
print STDERR "Type: $type, Base: $base\n";





sub handle_user_cancelled {
	sleep 3;  # test: maybe this helps with sorting? (sleep 2 doesn't seem to do much)
	my $dir = File::DirList::list('.', 'MSN', 1, 1, 0);  # sort doesn't really seem to work
	my $newestfile;
	for (my $i = 0; $i < @$dir; $i++) {
		$newestfile = $dir->[$i]->[13];
		last if $newestfile =~ m/^segment.*\.ts$/;
	}
	if (0 && $newestfile && move $newestfile, "z-$newestfile") {  # automatic deletion disabled cause it doesn't really work yet - trouble with the file creation/modification dates...
		print "\n\nremoved newest segment\nuser cancelled\n\n";
	}
	else {
		die "\nfailed to remove newest segment!\n\nuser cancelled";
	}
	chdir $thisdir;
	exit 2;
}

# TODO: Instead of just dumbly getting each segment individually, we'd ideally want to see which segments are already there and retrieve the largest contiguous *block* of segments that hasn't been loaded. Repeat until all segments are loaded. The downside is that the segments may no longer be loaded strictly sequentially, so defective downloads need to be detected and dealt with automatically. (A good start would be to simply delete whichever segment is the newest, because if the user cancelled, this will be a defective one. Occasionally a healthy segment may be deleted, but that's not a big problem. Rename the segment to "z-*" even avoids that minor issue.)
# Until that is implemented, a quick fix is to try *once* to download all segments with *one* cURL call *iff* *no* segments exist locally yet. Since the download works pretty well these days, that ought to cover the majority of cases. all_segments is then only used as a fallback and to stitch everything together.

my $dir_before = File::DirList::list('.', 'MSN', 1, 1, 0);
my @existing_segments = grep {$_->[13] =~ m/^segment.*\.ts$/} @$dir_before;
if (! @existing_segments) {
	my $result = system "curl", @http_header, "-O", "${base}segment[1-$count]_${type}.ts";
	if ($result == 2) {
		handle_user_cancelled;
	}
}




my $result = system scriptname::mydir() . "/all_segments.sh", $base, $count, $type;
my $status = $?;

my $exitcode = ($result == 0 && $status == 0) ? 0 : ($result == 2 && $status == 2) ? 2 : 1;
if ($exitcode == 2) {
	handle_user_cancelled;
}
elsif ($exitcode == 1) {
	$result == 0 or print "all_segments call failed: $? $!\n";
	if ($? == -1) {
		print "failed to execute: $!\n";
	}
	elsif ($? & 127) {
		printf "child died with signal %d, %s coredump\n",
			($? & 127),  ($? & 128) ? 'with' : 'without';
	}
	else {
		printf "child exited with value %d\n", $? >> 8;
	}
	print "Exiting.\n";
}
elsif ($exitcode == 0) {
	link "$programid.srt", "all_segments.NO.srt" if $programid && -e "$programid.srt";
#	link "all_segments.mp4", "$programid.mp4" if $programid;
	if ($options{any} && $type =~ m/_a$/) {
		rename "all_segments.mp4", "all_segments.m4a";
#		rename "$programid.mp4", "$programid.m4a" if $programid;
	}
}

chdir $thisdir;

exit $exitcode;




__END__

=pod

=head1 NAME

nrkcache.pl - Cache NRK Video on Demand broadcasts for offline viewing.

=head1 SYNOPSIS

 nrkcache.pl [-vv] [dir] [url]
 nrkcache.pl [-vv] master.m3u8
 nrkcache.pl [-vv] dir/
 nrkcache.pl [-vv] -b http://example.org/media/
 nrkcache.pl --help|--version|--man

=head1 DESCRIPTION

.

=head1 OPTIONS

=over

=item B<--help, -?>

Display a help message and exit.

=item B<--http-header, -H>

Add a custom HTTP header to most requests. The format is "Field: value".
Can only be used once.

=item B<--info-only, -I>

.

=item B<--man>

Print the manual page and exit.

=item B<--masterfile-name>

.

=item B<--quality, -q>

The type of the AV content to download as listed in the master.m3u8 file.
Usually the AV quality for NRK content ranges from 0 to 4. By default the
highest numerical value available is chosen.

=item B<--any, -a>

Set this option to enable audio-only (and video-only) download.

=item B<--part, -p>

Set this option to try to retrieve a numbered part of a content. Not well tested.

=item B<--base, -b>

If an existing master file is to be used, this option may be used to supply a base for relative URLs. This must be the CDN URL, not the NRK URL! Not well tested.

=item B<--verbose, -v>

Verbose mode. Produces more output about what the program does. Giving this
option multiple times may produce more and more output.

=item B<--version>

Display version information and exit.

=back



=head1 AUTHOR

Arne Johannessen

=head1 COPYRIGHT

Public Domain - CC0

=cut
