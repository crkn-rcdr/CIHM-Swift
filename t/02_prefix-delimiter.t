use Test::More;
use FindBin;

use lib "$FindBin::Bin/lib";
use boilerplate qw/test_client/;
my $client = test_client();

$client->container_put('test');
$client->object_put( 'test', 'files/test1.txt', 'this is a test file' );
$client->object_put( 'test', 'files/test2.txt', 'this is another test file' );
$client->object_put( 'test', 'other/test3.txt',
  'this test file is in another "directory"' );

my $dirs = $client->container_get( 'test', { delimiter => '/' } );
is( scalar @{ $dirs->content }, 2, 'listing successfully delimited' );
is( $dirs->content->[1]->{subdir}, 'other/', 'delimited subdir' );
my $files = $client->container_get( 'test', { prefix => 'other/' } );
is( $files->content->[0]->{name},
  'other/test3.txt', 'subdir prefix successful' );

$client->object_delete( 'test', 'files/test1.txt' );
$client->object_delete( 'test', 'files/test2.txt' );
$client->object_delete( 'test', 'other/test3.txt' );
$client->container_delete('test');

done_testing;