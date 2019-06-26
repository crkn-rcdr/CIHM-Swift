use Test::More;
use CIHM::Swift::Client;
use FindBin;

my $ssscheme = $ENV{'SWIFTSTACK_SCHEME'}      || 'http';
my $sshost   = $ENV{'SWIFTSTACK_HOST'}        || 'localhost';
my $ssport   = int( $ENV{'SWIFTSTACK_PORT'} ) || 22222;

if ( !$ENV{'DOCKER_TEST'} ) {
  eval {
    require Test::RequiresInternet;
    Test::RequiresInternet->import( $sshost => $ssport );
    1;
  };
}

my $client = CIHM::Swift::Client->new(
  server   => "$ssscheme://$sshost:$ssport",
  user     => $ENV{'SWIFTSTACK_USER'} || 'test',
  password => $ENV{'SWIFTSTACK_PASSWORD'} || 'test'
);

my $info = $client->info;
ok( $info->content->{swift}->{version}, 'can pull swift capabilities' );
ok( $info->transaction_id,              'responses include transaction id' );

my $account = $client->account_head;
is( $account->container_count, 0, 'account starts with 0 containers' );
is( $account->object_count,    0, 'account starts with 0 objects' );
is( $account->bytes_used,      0, 'account starts with no storage use' );

is( scalar @{ $client->account_get->content },
  0, 'container list starts empty' );

$client->container_put('NewContainer');
my $c = $client->account_get->content;
is( scalar @$c, 1, 'container list has new container' );
is( $c->[0]->{name}, 'NewContainer', 'new container initialized properly' );

$client->object_put(
  'NewContainer',                     'metadata.xml',
  "$FindBin::Bin/files/metadata.xml", 'application/xml'
);

my $oi = $client->object_head( 'NewContainer', 'metadata.xml' );
is( $oi->content_length, 43093, 'object upload succeeds' );
my $xml = $client->object_get( 'NewContainer', 'metadata.xml' )->content;
is( $xml->getElementsByTagName('mets:dmdSec')->size(),
  6, 'XML is deserialized' );

is( $client->container_delete('NewContainer')->code,
  409, 'cannot delete non-empty container' );
$client->object_delete( 'NewContainer', 'metadata.xml' );
$client->container_delete('NewContainer');
$c = $client->account_get->content;
is( scalar @$c, 0, 'container list is empty after delete' ) || diag explain $c;

done_testing;
