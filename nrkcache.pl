#! /usr/bin/env perl

use v5.26;
use warnings;
use utf8;
use open qw( :utf8 :std );

package Local::NRK::Cache;
# ABSTRACT: Cache NRK Video on Demand broadcasts for offline viewing
our $VERSION = '2.01';

use Object::Pad 0.51;
use Getopt::Long 2.33 qw( :config posix_default gnu_getopt auto_version auto_help );
use Pod::Usage qw( pod2usage );
use Carp qw( carp croak );
use HTTP::Tiny ();
use JSON::PP qw( decode_json );
use Path::Tiny qw( path );
use Cwd qw( cwd );


our $QUICK_ID = 1;  # skip HTML parsing if possible, rely on hard-coded API base
our $PSAPI_BASE = "https://psapi.nrk.no";
our %UA_CONFIG = ( agent => "nrkcache/$VERSION ", verify_SSL => 1 );
our @FORMATS = qw(
	worst[ext=mp4][height>30]/worst[ext=mp4]
	worst[ext=mp4][height>240]/best[ext=mp4]
	worst[ext=mp4][height>320]/best[ext=mp4]
	worst[ext=mp4][height>480]/best[ext=mp4]
	worst[ext=mp4][height>640]/best[ext=mp4]
	worst[ext=mp4][height>960]/best[ext=mp4]
	best[ext=mp4]
);
our $RATE = 1600;  # kilo-bytes per second


class Local::NRK::Cache :strict(params) {
	
	has $program_id :reader;
	has $url        :reader :param;
	has $meta_title :reader :writer :param = undef;
	has $meta_desc  :reader :writer :param = undef;
	has $nice       :reader :writer :param = 1;
	has $quality    :reader :writer = 3;
	has $psapi_base = $PSAPI_BASE;
	
	ADJUSTPARAMS ($params) {
		if (defined $params->{quality} && $params->{quality} >= 0) {
			$quality = $params->{quality};
		}
		delete $params->{quality};
		
		$program_id = $self->_discover_program_id;
		my $meta = {};
		#$meta = $self->_get_manifest($meta);
		$meta = $self->_get_metadata($meta);
		
		$meta->{title} =~ s/$/-$program_id/ unless $meta->{title} =~ m/$program_id$/;
		$meta_title //= $meta->{title};
		$meta->{description} .= " ($program_id)";
		$meta_desc //= $meta->{description};
	}
	
	
	method _discover_program_id {
		# Strategies to obtain the NRK on-demand "PRF" program ID:
		# 1. parse from URL
		# 2. get from HTTP header
		# 3. parse from web page meta data
		# 4. first string on web page that looks like an ID
		my $id;
		my $nrk_re = qr{//[^/]*nrk\.no(?:/|$)};
		my $prfid_re = qr/[A-ZØÆÅ]{4}[0-9]{8}/;
		my $ua = HTTP::Tiny->new( %UA_CONFIG );
		
		if ($url =~ m/^$prfid_re$/) {
			$id = $url;  # the user supplied the program ID instead of the URL
			$url = "https://tv.nrk.no/program/$url";
			return $id;
		}
		if ($QUICK_ID) {
			return $1 if $url =~ m{/($prfid_re)(?:/|$)};
			$id = eval { $ua->head($url)->{headers}{'x-nrk-program-id'} } // '';
			return $id if $id =~ m/^$prfid_re$/;
		}
		
		my $res = $ua->get($url, {headers => { Accept => 'text/html' }});
		$url = $res->{url};
		carp "Warning: This doesn't look like NRK. Check the URL '$url'" unless $url =~ m/^https?:$nrk_re/i;
		my $error = $res->{status} == 599 ? ": $res->{content}" : "";
		croak "HTTP error $res->{status} $res->{reason} on $url$error" unless $res->{success};
		my $html = $res->{content};
		my ($base_url) = $html =~ m/\bdata-psapi-base-url="([^"]+)"/i;
		$psapi_base = $base_url if $base_url && $base_url =~ m/https:$nrk_re/i;
		$id = $res->{headers}{'x-nrk-program-id'} // '';  # this header might not have been present in the HEAD response
		return $id if $id =~ m/^$prfid_re$/;
		return $id if ($id) = $html =~ m/\bprogram-id(?:"\s+content)?="($prfid_re)"/i;
		return $id if ($id) = $html =~ m/"prf(?:Id"\s*:\s*"|:)($prfid_re)"/;
		warn "Warning: Failed to discover NRK 'PRF' program ID; trying harder";
		return $id if ($id) = $html =~ m/\b($prfid_re)\b/;
		return $id if ($id) = $html =~ m/(\\u002[Ff]|\%2[Ff])($prfid_re)\b/;
		return $id if ($id) = $html =~ m/(?:[0-9a-z_]|\\u[0-9A-F]{4}|\%[0-9A-F]{2})($prfid_re)\b/;  # last-ditch effort
		croak "Failed to discover NRK 'PRF' program ID; giving up on '$url'";
	}
	
	
	method _get_json ($endpoint) {
		my $url = "$psapi_base$endpoint" =~ s/\{id\}/$program_id/r;
		my $ua = HTTP::Tiny->new( %UA_CONFIG );
		my $res = $ua->get($url, {headers => { Accept => 'application/json' }});
		my $error = $res->{status} == 599 ? ": $res->{content}" : "";
		croak "HTTP error $res->{status} $res->{reason} on $res->{url}$error" unless $res->{success};
		return decode_json $res->{content};
	}
	
	
	# dead code, mediaelement is 410
	method _get_mediaelement {
		my $json = $self->_get_json("/mediaelement/{id}");
		my $title = $json->{scoresStatistics}{springStreamStream} // '';
		$title =~ s|^.*/||;
		return {
			title => $title,
			description => $json->{description} // '',
		};
	}
	
	
	method _get_manifest ($meta) {
		my $json = $self->_get_json("/playback/manifest/program/{id}");
		$meta
	}
	
	
	method _get_metadata ($meta) {
		my $json = $self->_get_json("/playback/metadata/program/{id}");
		$meta->{title} = $json->{preplay}{titles}{title} // '';
		if (my $subtitle = $json->{preplay}{titles}{subtitle}) {
			$meta->{title} .= " $subtitle" if length $subtitle < 30;
			# The "subtitle" sometimes contains the full-length description,
			# which we don't want in the file name.
		}
		$meta->{description} = $json->{preplay}{description} // '';
		$meta
	}
	
	
	method store (%options) {
		my $dir = path(cwd)->child("$meta_title");
		my $file = path(cwd)->child("$meta_title.mp4");
		my $dir_mp4 = $dir->child("$program_id.mp4");
		my $dir_sub_nb_ttv = $dir->child("$program_id.nb-ttv.vtt");
		my $dir_sub_nb_nor = $dir->child("$program_id.nb-nor.vtt");
		my $dir_sub_nn_ttv = $dir->child("$program_id.nn-ttv.vtt");
		my $dir_sub_nn_nor = $dir->child("$program_id.nn-nor.vtt");
		croak "File exists: $file" if $file->exists;
		$dir->mkpath;
		
		my @ytdl_args = qw( --write-sub --all-subs --abort-on-unavailable-fragment );
		push @ytdl_args, '--output', $dir_mp4;
		push @ytdl_args, '--format', $FORMATS[$quality < @FORMATS ? $quality : $#FORMATS];
		push @ytdl_args, '--limit-rate', (int $RATE / 2 ** ($nice - 1)) . 'k' if $nice;
		system 'youtube-dl', $url, @ytdl_args;
		$self->_ipc_error_check($!, $?, 'youtube-dl');
		
		my $dir_sub = $dir_sub_nb_ttv->exists ? $dir_sub_nb_ttv :
			$dir_sub_nn_ttv->exists ? $dir_sub_nn_ttv :
			$dir_sub_nb_nor->exists ? $dir_sub_nb_nor :
			$dir_sub_nn_nor->exists ? $dir_sub_nn_nor :
			undef;
		if ($dir_sub) {
			system 'ffmpeg',
				-i => $dir_mp4,
				-f => 'srt', -i => $dir_sub,
				qw( -map 0:0 -map 0:1 -map 1:0 -c:v copy -c:a copy -c:s mov_text ),
				-metadata => "description=$meta_desc",
				-metadata => "comment=$url",
				-metadata => "copyright=NRK",
				-metadata => "episode_id=$program_id",
				$file;
			$self->_ipc_error_check($!, $?, 'ffmpeg');
		}
		else {
			$dir_mp4->move($file);
		}
		$dir->remove_tree;
	}
	
	
	method _ipc_error_check ($os_err, $code, $cmd) {
		utf8::decode $os_err;
		croak "$cmd failed to execute: $os_err" if $code == -1;
		croak "$cmd died with signal " . ($code & 0x7f) if $code & 0x7f;
		croak "$cmd exited with status " . ($code >> 8) if $code;
	}
	
}


# parse CLI parameters
$main::VERSION = $VERSION;
my %options = (
	comment => undef,  # ignored!
	man => undef,
	nice => 1,
	not_nice => 0,
	quality => -1,
);
GetOptions(
	'comment|c=s' => \$options{comment},
	'man' => \$options{man},
	'nice|n+' => \$options{nice},
	'not-nice' => \$options{not_nice},
	'quality|q=i' => \$options{quality},
) or pod2usage(2);
pod2usage(-exitstatus => 0, -verbose => 2) if $options{man};
pod2usage(2) unless @ARGV;
utf8::decode $_ for @ARGV;


my $cache = Local::NRK::Cache->new(
	url => $ARGV[0],
	nice => $options{not_nice} ? 0 : $options{nice},
	quality => $options{quality},
)->store;


__END__

=pod

=head1 NAME

nrkcache.pl - Cache NRK Video on Demand broadcasts for offline viewing.

=head1 SYNOPSIS

 nrkcache.pl https://tv.nrk.no/program/DVFJ64001010
 nrkcache.pl -n -q2 DVFJ64001010
 nrkcache.pl --help|--version|--man

=head1 DESCRIPTION

The Video-on-Demand programs of the Norwegian Broadcasting
Corporation (NRK) can be difficult to watch over a slow or unstable
network connection. This script creates a local cache of such video
programs in an MPEG-4 container, enabling users to watch without
interruptions.

For network transport, this script uses youtube-dl. Earlier versions
used cURL. Norwegian subtitles and metadata are also downloaded from
NRK. The data is muxed into a single MP4 file using FFmpeg.

=head1 OPTIONS

=over

=item B<--help, -?>

Display a help message and exit.

=item B<--man>

Print the manual page and exit.

=item B<--nice, -n>

Try to reduce the bandwidth used by the program. Giving this option
multiple times may reduce the bandwidth more and more.

Reducing the bandwidth may be useful when the caching is done on a
good network connection for later viewing, where it prevents the
overuse of network and server resources. It may also be useful on
a bad network connection to keep the remaining bandwidth available
for other purposes.

=item B<--not-nice>

Prevent bandwidth reduction.

=item B<--quality, -q>

The format of the AV content to download.
Usually the AV quality for NRK content ranges from 0 to 5.

If this option is not given, by default quality 3 is preferred when
available, otherwise the highest numerical value available is chosen.
AV content at quality 3 means "540p" or "qHD" resolution, which is
similar to Standard Definition TV (though typically encoded at higher
quality than standard TV). It may sound old-fashioned, but for a lot
of programs, this is actually plenty fine.

=item B<--version>

Display version information and exit.

=back

=head1 LIMITATIONS

The caching of multiple videos at the same time is currently
unsupported.

The code deciding the output filename seems fairly brittle and should
probably be overhauled. In particular, a suitable output file name
should start with the numeric season/episode code if available and
continue with the name of the program (if this is a TV episode with a
name of its own, the show name should be excluded). It should perhaps
always end with the program ID (although this may be redundant, given
that the ID is also in the meta data). Spaces should be used for
separation on macOS, hyphens otherwise. These considerations are
currently unimplemented.

=head1 AUTHOR

Arne Johannessen

=head1 COPYRIGHT

Public Domain - CC0

=cut
