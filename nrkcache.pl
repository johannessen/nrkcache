#! /usr/bin/env perl

use strict;
use warnings;
use 5.014;

our $VERSION = 1.02;

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
my $verbose = 0;
my %options = (
	infoonly => 0,
	man => undef,
	master_name => 'master.m3u8',
	quality => -1,
	verbose => 99,
	any => undef,
);
GetOptions(
	'verbose|v+' => \$verbose,
	'man' => \$options{man},
	'masterfile-name=s' => \$options{master_name},
	'quality|q=i' => \$options{quality},
	'any|a' => \$options{any},
	'info-only|I' => \$options{infoonly},
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
		print STDERR "case 1a\n" if $options{verbose};
	}
	elsif ( -d $ARGV[0] && -f $masterfile ) {
		# example: dir1
		$targetdir = $ARGV[0];
		print STDERR "case 1b\n" if $options{verbose};
	}
	elsif ( -d $targetdir && -f "$targetdir/$MASTER_NAME" ) {
		# example: dir1/someotherfile - this doesn't seem very useful actually
		$masterfile = "$targetdir/$MASTER_NAME";
		print STDERR "case 1c\n" if $options{verbose};
	}
	elsif ( $ARGV[0] =~ m/^https?:/ ) {
		$targetdir = '.';
		$nrkurl = $ARGV[0];
		$masterfile = $MASTER_NAME;
		print STDERR "case 1d\n" if $options{verbose};
	}
	else {
		pod2usage(-exitstatus => 3, -verbose => 0, -message => 'Could not parse master file, target dir or download URL from argument.');
	}
}
elsif (2 == scalar @ARGV) {
	$targetdir = $ARGV[0];
	if ( ! -d $targetdir ) {
		pod2usage(-exitstatus => 3, -verbose => 0, -message => 'Could not parse target dir from first argument.');
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



my $base;
my $count = '';
my $type;
my $suffix;
my $query;

my $thisdir = `pwd`;
chomp $thisdir;
chdir $targetdir;

if ( -e 'all_segments.mp4' ) {
	print "\n", `pwd`, "all_segments.mp4 exists. skipping.\n\n";
	exit 0;
}


if ($nrkurl) {
	# get all info from programme web page
	print STDERR "Downloading NRK page...\n" if $options{verbose};
	my $pagefile = "no.nrk.tv.programmepage.html";
	if ( $nrkurl =~ m|/([A-Z]{4}[0-9]{8})/|i ) {
		$pagefile = "$1.html";
	}
	system "curl", "-o", $pagefile, "$nrkurl" unless -f $pagefile;
	
	my $nrkinfo = {};
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
		
	}
	close NRKPAGE;
	
	#print Data::Dumper::Dumper($nrkinfo);
	
	my ($key, $value);
# 	while (($key, $value) = each %$nrkinfo) {
# 		print "$key=$value\n";
# 	}
	
	open(my $FH, '>', 'report.txt') or die "Could not open file 'filename' $!";
	if ($nrkinfo->{'og:description'}) {
		print $FH $nrkinfo->{'og:description'}, "\n\n";
	}
	if ($nrkinfo->{'og:url'} && ( ! $nrkinfo->{'og:url'} || $nrkinfo->{'og:url'} eq $nrkinfo->{'og:url'} )) {
		print $FH $nrkinfo->{'og:url'}, "\n\n";
	}
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
	while (($key, $value) = each %$nrkinfo) {
		print $FH "$key=$value\n";
	}
	close $FH;
	
	
	if ( ! $options{infoonly} ) {
		if ($nrkinfo->{playerdata_subtitlesurl}) {
			print STDERR "Downloading Subtitles...\n" if $options{verbose};
			system scriptname::mydir() . "/btitles.sh", $nrkinfo->{playerdata_subtitlesurl};
		}
		else {
			print STDERR "Subtitles not available.\n" if $options{verbose};
		}
		
		if ($nrkinfo->{playerdata_hls_media}) {
			print STDERR "Downloading Master File...\n" if $options{verbose};
			system "curl", "-o", $MASTER_NAME, $nrkinfo->{playerdata_hls_media};
		}
		else {
			print STDERR "Master File URL not found on NRK page.\n" if $options{verbose};
		}
		
	}
	
}



if ( $options{infoonly} ) {
	exit 0;
}









print STDERR "Parsing $targetdir/$MASTER_NAME...\n";

# find highest type/quality AV offering in master file
local *MASTER;
open MASTER, '<', $MASTER_NAME or die $!;
while (<MASTER>) {
	chomp;
	
	my $regex = '^(https?://.+)/index_(\d)_av\.([^\s\?]+)(\?\S*)?';
	if ($options{any}) {
		$regex = '^(https?://.+)/index_(\d)([^\s\?]+)(\?\S*)?';
	}
	m|$regex| or next;
	
	$1 && defined $2 && $3 or next;
	if ( $type && $2 < $type ) {
		next;
	}
	
	$base = $1;
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




system "curl", "-o", $indexfile, "$base/$indexfile$query" unless -r $indexfile;





#my $indexfile = $ARGV[0];
print STDERR "Parsing $indexfile...\n";

# find last chunk in index file to detect segment count
local *FILE;
open FILE, '<', $indexfile or die $!;
while (<FILE>) {
	chomp;
	
	my $regex = '^(https?://.+)/segment(\d+)_(\d_[av]+)\.ts';
	m|$regex| or next;
	$base = $1;
	$count = $2;
	$type = $3;
	
}
close FILE;

if ( ! $base || ! $count || ! $type ) {
	die "something's wrong with the index file";
}

print STDERR "Segments detected:  $count\n";
print STDERR "Type: $type, Base: $base\n";





my $result = system scriptname::mydir() . "/all_segments.sh", $base, $count, $type;
my $status = $?;

my $exitcode = ($result == 0 && $status == 0) ? 0 : ($result == 2 && $status == 2) ? 2 : 1;
if ($exitcode == 2) {
	# user cancelled
	sleep 2;  # test: does this help?
	my $dir = File::DirList::list('.', 'CSN', 1, 1, 0);  # sort doesn't really seem to work
	my $newestfile = $dir->[0]->[13];
	if ($newestfile) {
		move $newestfile, "z-$newestfile";
#		print Data::Dumper::Dumper($dir->[0], $dir->[1]);
	}
	else {
		die "\nfailed to remove newest segment!\n\nuser cancelled";
	}
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
	if ($options{any} && $type =~ m/_a$/) {
		rename "all_segments.mp4", "all_segments.m4a";
	}
}

chdir $thisdir;

exit $exitcode;




__END__

=pod

=head1 NAME

nrkcache.pl

=head1 SYNOPSIS

 nrkcache.pl [-vv] [dir] [url]
 nrkcache.pl [-vv] master.m3u8
 nrkcache.pl [-vv] dir/
 nrkcache.pl --help|--version|--man

=head1 DESCRIPTION

.

=head1 OPTIONS

=over

=item B<--help, -?>

Display a help message and exit.

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

Set this option to enable audio-only and video-only download. Not well tested.

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
