#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use CIHM::Swift::Client;
use DateTime;
use DateTime::Format::ISO8601;

my %options;

GetOptions( \%options, 'server:s', 'user:s', 'password:s', 'account:s',
    'verbose' );
my $verbose = $options{'verbose'};
delete $options{verbose};

# Longer timeout needed than default.
$options{furl_options} = { timeout => 3600 };

if ( scalar(@ARGV) != 3 ) {

    print STDERR
"Usage: --server <url> --user <username> --password <password> <container name> <object name> <disk filename>\n";
}
my ( $container, $object, $filename ) = @ARGV;

my $swift = CIHM::Swift::Client->new(%options);

if ($swift) {
    open( my $fh, '>:raw', $filename )
      or die "Could not open file '$filename' $!";
    print "open ($filename) to write\n" if ($verbose);
    my $response =
      $swift->object_get( $container, $object, { write_file => $fh } );
    close $fh;
    if ( $response->code == 200 ) {
        my $filemodified = $response->object_meta_header('File-Modified');
        if ($filemodified) {
            print "modified: $filemodified\n" if ($verbose);

            my $dt = DateTime::Format::ISO8601->parse_datetime($filemodified);
            if ( !$dt ) {
                die "Couldn't parse ISO8601 date from $filemodified\n";
            }
            my $atime = time;
            utime $atime, $dt->epoch(), $filename;
        }
        print "Headers from stored object:\n"
          . $response->headers->as_string() . "\n"
          if ($verbose);
    }
    else {
        print STDERR "account: '"
          . $swift->account
          . "' , container: '$container' , object: '$object'  returned "
          . $response->code . " - "
          . $response->message . "\n";
    }
}
else {
    print STDERR "No CIHM::Swift::Client()\n";
}
