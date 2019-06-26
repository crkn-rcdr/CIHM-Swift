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
  handles  => [qw/code message header content_type content_length/]
);

has '_deserialize' => (
  is       => 'ro',
  isa      => Maybe [Enum [qw{application/json text/xml application/xml}]],
  init_arg => 'deserialize'
);

sub content {
  my ($self) = @_;
  my $ds = $self->_deserialize || $self->content_type;
  if ( $ds eq 'application/json' ) {
    return
      length $self->_fr->content > 0 ? decode_json $self->_fr->content : [];
  } elsif ( $ds eq 'application/xml' || $ds eq 'text/xml' ) {
    return XML::LibXML->load_xml( string => $self->_fr->content );
  } else {
    return $self->_fr->content;
  }
}

sub auth_token     { return shift->header('X-Auth-Token'); }
sub transaction_id { return shift->header('X-Trans-Id'); }
sub bytes_used     { return int( shift->header('X-Account-Bytes-Used') ); }

sub container_count {
  return int( shift->header('X-Account-Container-Count') );
}

sub object_count { return int( shift->header('X-Account-Object-Count') ); }

1;