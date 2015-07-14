#! /usr/bin/env perl

use strict;
use warnings;

our $VERSION = 0.02;

use scriptname;
use File::DirList;
use File::Copy;
use File::Basename;
use Getopt::Long 2.33 qw( :config posix_default gnu_getopt auto_version auto_help );
use Pod::Usage;
use Data::Dumper;

# parse CLI parameters
my $verbose = 0;
my %options = (
	man => undef,
);
GetOptions(
#	'verbose|v+' => \$verbose,
	'man' => \$options{man},
) or pod2usage(2);
pod2usage(-exitstatus => 0, -verbose => 2) if $options{man};

# make sure we have everything we need
if (1 > scalar @ARGV) {
	pod2usage(-exitstatus => 3, -verbose => 0, -message => 'Missing required input file names.');
}



my $base = '';
my $count = '';
my $type = '';
my $suffix = '';
my $query;

my $masterpath = $ARGV[0];
if ( -d $masterpath ) {
	$masterpath .= "/master.m3u8";
}

my $thisdir = `pwd`;
chomp $thisdir;
my $masterfile = basename $masterpath;
my $targetdir = dirname $masterpath;
chdir $targetdir;

if ( -e 'all_segments.mp4' ) {
	print "\n", `pwd`, "all_segments.mp4 exists. skipping.\n\n";
	exit 0;
}




print STDERR "Parsing $masterpath...\n";

# find highest type/quality AV offering in master file
local *FILE;
open FILE, '<', $masterfile or die $!;
while (<FILE>) {
	chomp;
	
	m|^(https?://.+)/index_(\d)_av\.([^\s\?]+)(\?\S*)?| or next;
	$1 && $2 && $3 or next;
	if ( $type && $2 < $type ) {
		next;
	}
	
	$base = $1;
	$type = $2;
	$suffix = $3;
	$query = $4;
	
}
close FILE;

if ( ! $base || ! $type || ! $suffix ) {
	die "something's unusual about the master file";
}

my $indexfile = "index_${type}_av.$suffix";
$query ||= '';

print STDERR "Index File: type $type, AV\n";
print STDERR "Base: $base (suffix: $suffix, query: $query)\n";




system "curl", "-o", $indexfile, "$base/$indexfile$query" unless -r $indexfile;





#my $indexfile = $ARGV[0];
print STDERR "Parsing $indexfile...\n";

# find last chunk in index file to detect segment count
local *FILE;
open FILE, '<', $indexfile or die $!;
while (<FILE>) {
	chomp;
	
	m|^(https?://.+)/segment(\d+)_(\d)_av\.ts| or next;
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

chdir $thisdir;

exit $exitcode;




__END__

=pod

=head1 NAME

nrkcache.pl

=head1 AUTHOR

Arne Johannessen

=head1 COPYRIGHT

Public Domain - CC0

=cut
