package CIHM::Swift::Client;

=encoding utf8

=head1 NAME

CIHM::Swift::Client - Client for accessing OpenStack Swift installations

=head1 SYNOPSIS

  use CIHM::Swift::Client;

  my $swift = CIHM::Swift::Client->new({
    server   => 'https://swift.server',
    user     => 'user'
    password => 'password'
  });

  my $file = 'some/dir/kittens.jpg';

  $swift->object_put('MyContainer', 'kittens.jpg', $file);

=cut

use strictures 2;

use Carp;
use Moo;
use Types::Standard qw/Str Int InstanceOf/;
use Furl;
use MIME::Types;

use CIHM::Swift::Client::Response;

=head1 ATTRIBUTES

=head2 server

URL of the Swift installation. e.g. 'https://swift.server'

=cut

has 'server' => (
  is       => 'ro',
  isa      => Str,
  required => 1
);

=head2 user, password

Authentication information for accessing Swift. Currently, we only support v1
of the authentication API.

We also make the assumption that the user will only be accessing containers
and objects within the user's account.

=cut

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

=head1 METHODS

=head2 info

L<GET /info|https://developer.openstack.org/api-ref/object-store/?expanded=#list-activated-capabilities>

=cut

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

=head2 account_head

L<HEAD /v1/AUTH_$user|https://developer.openstack.org/api-ref/object-store/?expanded=#show-account-metadata>

Gets information about the user's account.

=cut

sub account_head { return shift->_request('head'); }

=head2 account_get

L<GET /v1/AUTH_$user|https://developer.openstack.org/api-ref/object-store/?expanded=#show-account-details-and-list-containers>

Gets a list of containers in the user's account.

=cut

sub account_get { return shift->_request( 'get', { json => 1 } ); }

sub _container_request {
  my ( $self, $method, $options, $container ) = @_;
  croak 'cannot make container request without container name'
    unless $container;
  return $self->_request( $method, $options, $container );
}

=head2 container_put($container)

L<PUT /v1/AUTH_$user/$container|https://developer.openstack.org/api-ref/object-store/?expanded=#create-container>

Creates a container.

=cut

sub container_put { return shift->_container_request( 'put', {}, shift ); }

=head2 container_delete($container)

L<DELETE /v1/AUTH_$user/$container|https://developer.openstack.org/api-ref/object-store/?expanded=#delete-container>

Deletes a container. Will fail if the container contains any objects.

=cut

sub container_delete {
  return shift->_container_request( 'delete', {}, shift );
}

sub _object_request {
  my ( $self, $method, $options, $container, $object ) = @_;
  croak 'cannot make object request without container name' unless $container;
  croak 'cannot make object request without object name'    unless $object;
  return $self->_request( $method, $options, $container, $object );
}

=head2 object_put($container, $object)

L<PUT /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/?expanded=#create-or-replace-object>

Creates or replaces an object within a container.

=cut

sub object_put {
  my ( $self, $container, $object, $file ) = @_;
  croak 'cannot put object without filename/filehandle' unless $file;
  return $self->_object_request( 'put', { file => $file }, $container,
    $object );
}

=head2 object_head($container, $object)

L<HEAD /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/?expanded=#show-object-metadata>

Shows object metadata.

=cut

sub object_head { return shift->_object_request( 'head', {}, shift, shift ); }

=head2 object_get($container, $object)

L<GET /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/?expanded=#get-object-content-and-metadata>

Gets object content. Content will be deserialized into XML or JSON if its
C<Content-Type> is set accordingly.

=cut

sub object_get { return shift->_object_request( 'get', {}, shift, shift ); }

=head2 object_delete($container, $object)

L<DELETE /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/?expanded=#delete-object>

Deletes an object.

=cut

sub object_delete {
  return shift->_object_request( 'delete', {}, shift, shift );
}

1;