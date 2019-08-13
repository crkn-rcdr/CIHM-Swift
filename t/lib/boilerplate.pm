package boilerplate;
require Exporter;
our @ISA       = qw/Exporter/;
our @EXPORT_OK = qw/test_client/;

use CIHM::Swift::Client;

sub test_client {
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

  return CIHM::Swift::Client->new(
    server       => "$ssscheme://$sshost:$ssport",
    user         => $ENV{'SWIFTSTACK_USER'} || 'test',
    password     => $ENV{'SWIFTSTACK_PASSWORD'} || 'test',
    furl_options => { timeout => 60 }
  );
}

1;
