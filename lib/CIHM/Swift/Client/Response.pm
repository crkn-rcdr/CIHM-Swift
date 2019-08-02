package CIHM::Swift::Client::Response;

use strictures 2;
use Types::Standard qw/InstanceOf Enum Maybe/;
use JSON qw/decode_json/;
use XML::LibXML;
use Furl::Response;

use Moo;
use namespace::clean;

has '_fr' => (
  is       => 'ro',
  isa      => InstanceOf ['Furl::Response'],
  init_arg => 'basis',
  handles  => [qw/code message header headers content_type content_length/]
);

has '_deserialize' => (
  is       => 'ro',
  isa      => Maybe [Enum [qw{application/json text/xml application/xml}]],
  init_arg => 'deserialize'
);

sub content {
  my ($self) = @_;
  my $ds = $self->_deserialize || '';
  if ( $ds eq 'application/json' ) {
    return
      length $self->_fr->content > 0 ? decode_json $self->_fr->content : [];
  } elsif ( $ds eq 'application/xml' || $ds eq 'text/xml' ) {
    return XML::LibXML->load_xml( string => $self->_fr->content );
  } else {
    return $self->_fr->content;
  }
}

# expected header metadata for each request
sub date           { return shift->header('Date'); }
sub timestamp      { return shift->header('X-Timestamp'); }
sub transaction_id { return shift->header('X-Trans-Id'); }

# standard headers for objects
sub etag          { return shift->header('ETag'); }
sub last_modified { return shift->header('Last-Modified'); }

# shortcut methods for accessing metadata
sub account_header      { return shift->header( 'X-Account-' . shift ); }
sub account_meta_header { return shift->header( 'X-Account-Meta-' . shift ); }
sub container_header    { return shift->header( 'X-Container-' . shift ); }

sub container_meta_header {
  return shift->header( 'X-Container-Meta-' . shift );
}
sub object_header      { return shift->header( 'X-Object-' . shift ); }
sub object_meta_header { return shift->header( 'X-Object-Meta-' . shift ); }

1;