use Test::More;
use FindBin;
use JSON qw/encode_json/;

use lib "$FindBin::Bin/lib";
use boilerplate qw/test_client/;
my $client = test_client();

$client->container_put('test');
my $json = encode_json( { property => 'value' } );
$client->object_put( 'test', 'test.json', $json );

my $response_json = $client->object_get( 'test', 'test.json',
  { deserialize => 'application/json' } )->content;
is( $response_json->{property}, 'value', 'direct PUT of a JSON string' );

$client->container_put('test1');
$client->object_copy( 'test', 'test.json', 'test1', 'test123.json' );

$response_json = $client->object_get( 'test1', 'test123.json',
  { deserialize => 'application/json' } )->content;
is( $response_json->{property}, 'value', 'Copy of object' );

$client->object_delete( 'test1', 'test123.json' );
$client->container_delete('test1');
$client->object_delete( 'test', 'test.json' );
$client->container_delete('test');
done_testing;