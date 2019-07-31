use Test::More;
use FindBin;

use lib "$FindBin::Bin/lib";
use boilerplate qw/test_client/;
my $client = test_client();

$client->container_put('test');
$client->object_put( 'test', 'files/meta1.xml',
  "$FindBin::Bin/files/metadata.xml" );
$client->object_put( 'test', 'files/meta2.xml',
  "$FindBin::Bin/files/metadata.xml" );
$client->object_put( 'test', 'other/meta3.xml',
  "$FindBin::Bin/files/metadata.xml" );

my $dirs = $client->container_get( 'test', { delimiter => '/' } );
is( scalar @{ $dirs->content }, 2, 'listing successfully delimited' );
is( $dirs->content->[1]->{subdir}, 'other/', 'delimited subdir' );
my $files = $client->container_get( 'test', { prefix => 'other/' } );
is( $files->content->[0]->{name},
  'other/meta3.xml', 'subdir prefix successful' );

$client->object_delete( 'test', 'files/meta1.xml' );
$client->object_delete( 'test', 'files/meta2.xml' );
$client->object_delete( 'test', 'other/meta3.xml' );
$client->container_delete('test');

done_testing;