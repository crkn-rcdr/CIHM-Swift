use Test::More;
use FindBin;

use lib "$FindBin::Bin/lib";
use boilerplate qw/test_client/;
my $client = test_client();

my $info = $client->info;
ok( $info->content->{swift}->{version}, 'can pull swift capabilities' );
ok( $info->transaction_id,              'responses include transaction id' );

my $time = time;
$client->account_post( { 'Custom-Timestamp' => $time } );

my $account = $client->account_head;
is( $account->account_header('Container-Count'),
  0, 'account starts with 0 containers' );
is( $account->account_header('Object-Count'),
  0, 'account starts with 0 objects' );
is( $account->account_header('Bytes-Used'),
  0, 'account starts with no storage use' );
is( $account->account_meta_header('Custom-Timestamp'),
  $time, 'account metadata is retrievable' );

is( scalar @{ $client->account_get->content },
  0, 'container list starts empty' );

$client->container_put( 'NewContainer', { 'Custom-Field' => 'test' } );
my $c = $client->account_get->content;
is( scalar @$c, 1, 'container list has new container' );
is( $c->[0]->{name}, 'NewContainer', 'new container initialized properly' );

$client->container_post( 'NewContainer', { 'Other-Field' => 'test2' } );

my $container = $client->container_head('NewContainer');
is( $container->container_header('Bytes-Used'),
  0, 'container starts with no storage use' );
is( $container->container_meta_header('Custom-Field'),
  'test', 'put container metadata is retrievable' );
is( $container->container_meta_header('Other-Field'),
  'test2', 'post container metadata is retrievable' );

$client->object_put(
  'NewContainer', 'metadata.xml',
  "$FindBin::Bin/files/metadata.xml",
  { 'TestMeta' => 'TestMetaValue' }
);

my $oi = $client->object_head( 'NewContainer', 'metadata.xml' );
is( $oi->content_length, 43093, 'object upload succeeds' );
my $object = $client->object_get( 'NewContainer', 'metadata.xml' );
is( $object->object_meta_header('TestMeta'),
  'TestMetaValue', 'put object metadata retrievable' );
is( $object->content->getElementsByTagName('mets:dmdSec')->size(),
  6, 'XML is deserialized' );

$client->object_post( 'NewContainer', 'metadata.xml',
  { 'Other-Field' => 'test2' } );

$oi = $client->object_head( 'NewContainer', 'metadata.xml' );
is( $oi->object_meta_header('Other-Field'),
  'test2', 'post object metadata retrievable' );
is( $oi->object_meta_header('TestMeta'),
  undef, 'post object metadata deletes existing custom metadata' );

is( $client->container_delete('NewContainer')->code,
  409, 'cannot delete non-empty container' );
$client->object_delete( 'NewContainer', 'metadata.xml' );
$client->container_delete('NewContainer');
$c = $client->account_get->content;
is( scalar @$c, 0, 'container list is empty after delete' ) || diag explain $c;

done_testing;
