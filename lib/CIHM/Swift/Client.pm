package CIHM::Swift::Client;

use strictures 2;

use Carp;
use Moo;
use Types::Standard qw/Str Int InstanceOf/;
use Furl;
use MIME::Types;

use CIHM::Swift::Client::Response;

has 'server' => (
  is       => 'ro',
  isa      => Str,
  required => 1
);

has 'user' => (
  is       => 'ro',
  isa      => Str,
  required => 1
);

has 'password' => (
  is       => 'ro',
  isa      => Str,
  required => 1
);

has '_agent' => (
  is      => 'ro',
  isa     => InstanceOf ['Furl'],
  default => sub { return Furl->new(); },
);

has '_mt' => (
  is      => 'ro',
  isa     => InstanceOf ['MIME::Types'],
  default => sub { return MIME::Types->new; }
);

has '_token' => (
  is      => 'rwp',
  isa     => Str,
  default => ''
);

has '_token_time' => (
  is      => 'rwp',
  isa     => Int,
  default => 0
);

sub _url { return join '/', shift->server, 'v1', grep( defined, @_ ); }

sub _acc { return 'AUTH_' . shift->user; }

sub _authorize {
  my ($self) = @_;

  unless ( time - $self->_token_time < 3600 ) {
    my $response;

    # Swiftstack might not be initialized yet (especially in testing mode)
    my $code = 500;
    while ( $code >= 500 ) {
      $response = $self->_agent->get(
        join( '/', $self->server, 'auth', 'v1.0' ),
        [
          'X-Auth-User' => $self->user,
          'X-Auth-Key'  => $self->password
        ]
      );
      $code = $response->code;
      if ( $code >= 500 ) {
        sleep(1);
      }
    }

    if ( $code < 300 ) {
      $self->_set__token( $response->header('X-Auth-Token') );
      $self->_set__token_time(time);
    } else {
      croak "Swiftstack authorization failure: $code";
    }
  }

  return ['X-Auth-Token' => $self->_token];
}

sub info {
  my ($self) = @_;
  return CIHM::Swift::Client::Response->new( {
      basis =>
        $self->_agent->get( $self->server . '/info', $self->_authorize ),
      deserialize => 'application/json'
    }
  );
}

sub _request {
  my ( $self, $method, $options, $container, $object ) = @_;
  my $deserialize;
  $method = uc $method;
  $options ||= {};
  my $url     = $self->_url( $self->_acc, $container, $object );
  my $headers = $self->_authorize;
  my $content;

  if ( $options->{file} ) {
    my $fh;
    if ( ref $options->{file} eq 'GLOB' ) {
      $fh = $options->{file};
    } else {
      open( $fh, '<:raw', $options->{file} ) or
        croak "Cannot open " . $options->{file} . ": $!";
    }
    $headers = [
      @$headers,
      'Content-Type' => $self->_mt->mimeTypeOf($object)->type ||
        'application/octet-stream',
      'Content-Length' => -s $fh
    ];
    $content = $fh;
  }

  if ( $options->{json} ) {
    $url         = $url . '?format=json';
    $deserialize = 'application/json';
  }

  return CIHM::Swift::Client::Response->new( {
      basis => $self->_agent->request(
        method  => $method,
        url     => $url,
        headers => $headers,
        content => $content
      ),
      deserialize => $deserialize
    }
  );
}

sub account_head { return shift->_request('head'); }

sub account_get { return shift->_request( 'get', { json => 1 } ); }

sub _container_request {
  my ( $self, $method, $options, $container ) = @_;
  croak 'cannot make container request without container name'
    unless $container;
  return $self->_request( $method, $options, $container );
}

sub container_put { return shift->_container_request( 'put', {}, shift ); }

sub container_delete {
  return shift->_container_request( 'delete', {}, shift );
}

sub _object_request {
  my ( $self, $method, $options, $container, $object ) = @_;
  croak 'cannot make object request without container name' unless $container;
  croak 'cannot make object request without object name'    unless $object;
  return $self->_request( $method, $options, $container, $object );
}

sub object_put {
  my ( $self, $container, $object, $file ) = @_;
  croak 'cannot put object without filename/filehandle' unless $file;
  return $self->_object_request( 'put', { file => $file }, $container,
    $object );
}

sub object_head { return shift->_object_request( 'head', {}, shift, shift ); }

sub object_get { return shift->_object_request( 'get', {}, shift, shift ); }

sub object_delete {
  return shift->_object_request( 'delete', {}, shift, shift );
}

1;