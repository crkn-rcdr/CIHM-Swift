#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long;
use CIHM::Swift::Client;
use DateTime;

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
    open( my $fh, '<:raw', $filename )
      or die "Could not open file '$filename' $!";

    my $filedate = "unknown";
    my $mtime    = ( stat($fh) )[9];
    if ($mtime) {
        my $dt = DateTime->from_epoch( epoch => $mtime );
        $filedate = $dt->datetime . "Z";
    }
    print "File modified date: $filedate\n" if ($verbose);
    my $response = $swift->object_put( $container, $object, $fh,
        { 'File-Modified' => $filedate } );
    close $fh;

    if ( $response->code != 201 ) {
        print STDERR "account: '"
          . $swift->account
          . "' , container: '$container' , object: '$object'  returned "
          . $response->code . " - "
          . $response->message . "\n";
    }

    if ($verbose) {

        # Separate request to confirm headers
        print "Headers from stored object:\n"
          . $swift->object_head( $container, $object )->headers->as_string()
          . "\n";
    }
}
else {
    print STDERR "No CIHM::Swift::Client()\n";
}
