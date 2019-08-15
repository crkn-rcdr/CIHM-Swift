use Test::More;
use FindBin;

use lib "$FindBin::Bin/lib";
use boilerplate qw/test_client/;
my $client = test_client();

$client->container_put('test');
$client->object_put( 'test', 'foo', 'this is a string' );

my $object = $client->object_get( 'test', 'foo' );
is( $object->content, 'this is a string', 'content is uploaded' );
is( $object->content_type, 'application/octet-stream',
'content is uploaded as application/octet-stream when type cannot be inferred from extension'
);

$client->object_delete( 'test', 'foo' );
$client->container_delete('test');

done_testing;