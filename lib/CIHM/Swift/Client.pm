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

use v5.20;
use strictures 2;

use Carp;
use Moo;
use Types::Standard qw/Str Int InstanceOf/;
use Furl;
use MIME::Types;
use URI;

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

=head2 account

Instances of C<CIHM::Swift::Client> operate on a single Swift account. By
default, the account name is set to the
L<SwiftStack|https://www.swiftstack.com/> default of C<AUTH_$user>. Pass
C<account> as an option to C<< CIHM::Swift::Client->new >>.

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

has 'account' => (
  is      => 'lazy',
  isa     => Str,
  default => sub { return 'AUTH_' . shift->user; }
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

sub _uri {
  return URI->new( join '/', shift->server, 'v1', grep( defined, @_ ) );
}

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

L<GET /info|https://developer.openstack.org/api-ref/object-store/#list-activated-capabilities>

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
  my $uri     = $self->_uri( $self->account, $container, $object );
  my $headers = $self->_authorize;
  my $content;

  if ( $options->{query} ) {
    $uri->query_form( $options->{query} );
  }

  if ( $options->{headers} ) {
    $headers = [@$headers, @{ $options->{headers} }];
  }

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
    $headers     = [@$headers, 'Accept' => 'application/json'];
    $deserialize = 'application/json';
  }

  return CIHM::Swift::Client::Response->new( {
      basis => $self->_agent->request(
        method  => $method,
        url     => $uri->as_string,
        headers => $headers,
        content => $content
      ),
      deserialize => $deserialize
    }
  );
}

sub _metadata_headers {
  my ( $metadata, $prefix ) = @_;
  return [map { $prefix . $_ => $metadata->{$_} } keys %$metadata];
}

sub _list_options {
  my ($q) = @_;
  return { %$q{qw/limit marker end_marker prefix delimiter/} };
}

=head2 account_head

L<HEAD /v1/AUTH_$user|https://developer.openstack.org/api-ref/object-store/#show-account-metadata>

Gets information about the user's account.

=cut

sub account_head { return shift->_request('head'); }

=head2 account_get($query_options)

L<GET /v1/AUTH_$user|https://developer.openstack.org/api-ref/object-store/#show-account-details-and-list-containers>

Gets a list of containers in the user's account. C<$query_options> is an
optional hashref for specifying list constraints, accepting these keys:
C<limit>, C<marker>, C<end_marker>, C<prefix>, C<delimiter>. Response content
is deserialized JSON.

=cut

sub account_get {
  my ( $self, $query_options ) = @_;
  return $self->_request( 'get',
    { json => 1, query => _list_options($query_options) } );
}

=head2 account_post($metadata)

L<POST /v1/AUTH_$user|https://docs.openstack.org/api-ref/object-store/#create-update-or-delete-account-metadata>

Posts account metadata. The C<$metadata> hashref will have its keys prefixed
with C<X-Account-Meta-> before being added to the request's headers.

=cut

sub account_post {
  my ( $self, $metadata ) = @_;
  croak 'Making a POST request to an account without metadata'
    unless $metadata;
  return $self->_request( 'post',
    { headers => _metadata_headers( $metadata, 'X-Account-Meta-' ) } );
}

sub _container_request {
  my ( $self, $method, $options, $container ) = @_;
  croak 'cannot make container request without container name'
    unless $container;
  return $self->_request( $method, $options, $container );
}

=head2 container_put($container, $metadata)

L<PUT /v1/AUTH_$user/$container|https://developer.openstack.org/api-ref/object-store/#create-container>

Creates a container. Optionally takes C<$metadata> hashref, akin to
C<container_post>.

=cut

#sub container_put { return shift->_container_request( 'put', {}, shift ); }
sub container_put {
  my ( $self, $container, $metadata ) = @_;
  my $options = {};
  if ( $metadata && ref $metadata eq 'HASH' ) {
    $options->{headers} = _metadata_headers( $metadata, 'X-Container-Meta-' );
  }
  return $self->_container_request( 'put', $options, $container );
}

=head2 container_head($container)

L<HEAD /v1/AUTH_$user/$container|https://docs.openstack.org/api-ref/object-store/#show-container-metadata>

Retrieves container information and metadata.

=cut

sub container_head { return shift->_container_request( 'head', {}, shift ); }

=head2 container_get($container, $query_options)

L<GET /v1/AUTH_$user/$container|https://docs.openstack.org/api-ref/object-store/#show-container-details-and-list-objects>

Lists objects in a container. C<$query_options> is an optional hashref for
specifying list constraints, accepting these keys: C<limit>, C<marker>,
C<end_marker>, C<prefix>, C<delimiter>. Response content is deserialized JSON.

=cut

sub container_get {
  my ( $self, $container, $query_options ) = @_;
  return $self->_container_request( 'get',
    { json => 1, query => _list_options($query_options) }, $container );
}

=head2 container_post($container, $metadata)

L<POST /v1/AUTH_$user/$container|https://docs.openstack.org/api-ref/object-store/#create-update-or-delete-container-metadata>

Posts container metadata. The C<$metadata> hashref will have its keys prefixed
with C<X-Container-Meta-> before being added to the request's headers.

=cut

sub container_post {
  my ( $self, $container, $metadata ) = @_;
  croak 'Making a POST request to an object without metadata' unless $metadata;
  return $self->_container_request( 'post',
    { headers => _metadata_headers( $metadata, 'X-Container-Meta-' ) },
    $container );
}

=head2 container_delete($container)

L<DELETE /v1/AUTH_$user/$container|https://developer.openstack.org/api-ref/object-store/#delete-container>

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

=head2 object_put($container, $object, $file, $metadata)

L<PUT /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/#create-or-replace-object>

Creates or replaces an object within a container. C<$file> can be a filehandle
or a path. Metadata can be added akin to C<object_post> below.

=cut

sub object_put {
  my ( $self, $container, $object, $file, $metadata ) = @_;
  croak 'cannot put object without filename/filehandle' unless $file;
  my $options = { file => $file };
  if ( $metadata && ref $metadata eq 'HASH' ) {
    $options->{headers} = _metadata_headers( $metadata, 'X-Object-Meta-' );
  }
  return $self->_object_request( 'put', $options, $container, $object );
}

=head2 object_head($container, $object)

L<HEAD /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/#show-object-metadata>

Shows object metadata.

=cut

sub object_head { return shift->_object_request( 'head', {}, shift, shift ); }

=head2 object_get($container, $object)

L<GET /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/#get-object-content-and-metadata>

Gets object content. Content will be deserialized into XML or JSON if its
C<Content-Type> is set accordingly.

=cut

sub object_get { return shift->_object_request( 'get', {}, shift, shift ); }

=head2 object_post($container, $object, $metadata)

L<POST /v1/AUTH_$user/$container/$object|https://docs.openstack.org/api-ref/object-store/#create-or-update-object-metadata>

Posts object metadata. The C<$metadata> hashref will have its keys prefixed
with C<X-Object-Meta-> before being added to the request's headers.

=cut

sub object_post {
  my ( $self, $container, $object, $metadata ) = @_;
  croak 'Making a POST request to an object without metadata' unless $metadata;
  return $self->_object_request( 'post',
    { headers => _metadata_headers( $metadata, 'X-Object-Meta-' ) },
    $container, $object );
}

=head2 object_delete($container, $object)

L<DELETE /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/#delete-object>

Deletes an object.

=cut

sub object_delete {
  return shift->_object_request( 'delete', {}, shift, shift );
}

1;