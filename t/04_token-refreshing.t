use Test::More;
use FindBin;

use lib "$FindBin::Bin/lib";
use boilerplate qw/test_client/;
my $client = test_client();

$client->container_put('test');

# mess with the token
$client->_set__token('foo');
my $response = $client->container_delete('test');
is( $response->code, 204,
  'bad token should be replaced by good one, succeed' );

done_testing;