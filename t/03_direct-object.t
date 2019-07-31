use Test::More;
use FindBin;
use JSON qw/encode_json/;

use lib "$FindBin::Bin/lib";
use boilerplate qw/test_client/;
my $client = test_client();

$client->container_put('test');
my $json = encode_json( { property => 'value' } );
$client->object_put( 'test', 'test.json', $json );

my $response_json = $client->object_get( 'test', 'test.json' )->content;
is( $response_json->{property}, 'value', 'direct PUT of a JSON string' );

$client->object_delete( 'test', 'test.json' );
$client->container_delete('test');
done_testing;