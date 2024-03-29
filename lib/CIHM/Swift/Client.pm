package CIHM::Swift::Client;

=encoding utf8

=head1 NAME

CIHM::Swift::Client - Client for accessing OpenStack Swift installations

=head1 SYNOPSIS

  use CIHM::Swift::Client;

  my $swift = CIHM::Swift::Client->new({
    server       => 'https://swift.server',
    user         => 'user',
    password     => 'password',
    furl_options => { timeout => 60 }
  });

  my $content = 'this is a string that will be written to a Swift object';

  $swift->object_put('MyContainer', 'string.txt', $content);

  open(my $fh, '<:raw', '/path/to/image.jpg');
  $swift->object_put('MyContainer', 'image.jpg', $fh);
  close $fh;

=cut

use strictures 2;

use Carp;
use Moo;
use Types::Standard qw/Str Int HashRef InstanceOf/;
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

=head2 furl_options

An optional hashref containing options to be passed to L<Furl>, the HTTP agent
used by C<CIHM::Swift::Client>. You may be interested in setting C<timeout>
to something higher than 10.

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

has 'furl_options' => (
    is      => 'ro',
    isa     => HashRef,
    default => sub { return {}; }
);

has '_agent' => (
    is      => 'lazy',
    isa     => InstanceOf ['Furl'],
    default => sub { return Furl->new( %{ shift->furl_options } ); },
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

sub _uri {
    return URI->new( join '/', shift->server, 'v1', grep( defined, @_ ) );
}

sub _authorize {
    my ($self) = @_;

    if ( $self->_token eq '' ) {
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
                warn "Error during Swift authorization: code=$code  message=".$response->message."\n";
                sleep(1);
            }
        }

        if ( $code < 300 ) {
            $self->_set__token( $response->header('X-Auth-Token') );
        }
        else {
            croak "Swiftstack authorization failure: $code";
        }
    }

    return [ 'X-Auth-Token' => $self->_token ];
}

=head1 METHODS

=head2 info

L<GET /info|https://developer.openstack.org/api-ref/object-store/#list-activated-capabilities>

=cut

sub info {
    my ($self) = @_;

    my $response = CIHM::Swift::Client::Response->new(
        {
            basis =>
              $self->_agent->get( $self->server . '/info', $self->_authorize ),
            deserialize => 'application/json'
        }
    );

    if ( $response->code == 401 ) {
        $self->_set__token('');
        return $self->info();
    }

    return $response;
}

sub _request {
    my ( $self, $method, $options, $container, $object ) = @_;
    $method = uc $method;
    $options ||= {};
    my $uri = $self->_uri( $self->account, $container, $object );
    my $headers = $self->_authorize;
    my $content;
    my $deserialize = $options->{deserialize};

    if ( $options->{query} ) {
        $uri->query_form( $options->{query} );
    }

    if ( $options->{headers} ) {
        $headers = [ @$headers, @{ $options->{headers} } ];
    }

    if ( $options->{content} ) {
        my $mime = $self->_mt->mimeTypeOf($object);
        my $mimeType = $mime ? $mime->type : 'application/octet-stream';
        $content = $options->{content};
        $headers = [ @$headers, 'Content-Type' => $mimeType ];
    }

    if ( $options->{json} ) {
        $headers = [ @$headers, 'Accept' => 'application/json' ];
        $deserialize = 'application/json';
    }

    my $response = CIHM::Swift::Client::Response->new(
        {
            basis => $self->_agent->request(
                method     => $method,
                url        => $uri->as_string,
                headers    => $headers,
                content    => $content,
                write_file => $options->{write_file}
            ),
            deserialize => $deserialize
        }
    );

    if ( $response->code == 401 ) {
        $self->_set__token('');
        return $self->_request( $method, $options, $container, $object );
    }

    return $response;
}

sub _metadata_headers {
    my ( $metadata, $prefix ) = @_;
    return [ map { $prefix . $_ => $metadata->{$_} } keys %$metadata ];
}

sub _list_options {
    my ($q) = @_;
    return { map { $q->{$_} ? ( $_, $q->{$_} ) : () }
          qw/limit marker end_marker prefix delimiter/ };
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
        $options->{headers} =
          _metadata_headers( $metadata, 'X-Container-Meta-' );
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
    croak 'Making a POST request to an object without metadata'
      unless $metadata;
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
    croak 'cannot make object request without container name'
      unless $container;
    croak 'cannot make object request without object name' unless $object;
    return $self->_request( $method, $options, $container, $object );
}

=head2 object_put($container, $object, $file, $metadata)

L<PUT /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/#create-or-replace-object>

Creates or replaces an object within a container. C<$content> can either be a
string or a filehandle. Metadata can be added akin to C<object_post> below.

=cut

sub object_put {
    my ( $self, $container, $object, $content, $metadata ) = @_;
    croak 'cannot put object without string/filehandle' unless $content;
    my $options = { content => $content };
    if ( $metadata && ref $metadata eq 'HASH' ) {
        $options->{headers} = _metadata_headers( $metadata, 'X-Object-Meta-' );
    }
    return $self->_object_request( 'put', $options, $container, $object );
}

=head2 object_head($container, $object)

L<HEAD /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/#show-object-metadata>

Shows object metadata.

=cut

sub object_head {
    return shift->_object_request( 'head', {}, shift, shift );
}

=head2 object_get($container, $object, $options)

L<GET /v1/AUTH_$user/$container/$object|https://developer.openstack.org/api-ref/object-store/#get-object-content-and-metadata>

Gets object content. Content can be deserialized if C<deserialize> is set to
either C<application/json> or C<application/xml> in C<$options>.

Content sent to a file if C<write_file> is a filehandle in C<$options>.

=cut

sub object_get {
    my ( $self, $container, $object, $options ) = @_;
    $options = {
        deserialize => $options->{deserialize},
        write_file  => $options->{write_file}
    };
    return $self->_object_request( 'get', $options, $container, $object );
}

=head2 object_post($container, $object, $metadata)

L<POST /v1/AUTH_$user/$container/$object|https://docs.openstack.org/api-ref/object-store/#create-or-update-object-metadata>

Posts object metadata. The C<$metadata> hashref will have its keys prefixed
with C<X-Object-Meta-> before being added to the request's headers.

=cut

sub object_post {
    my ( $self, $container, $object, $metadata ) = @_;
    croak 'Making a POST request to an object without metadata'
      unless $metadata;
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

=head2 object_copy($sourcecontainer, $sourceobject, $destinationcontainer, $destinationobject)

L<COPY /v1/AUTH_$user/$container/$object|https://docs.openstack.org/api-ref/object-store/#copy-object>

Copies an object to another location.

=cut

sub object_copy {
    my ( $self, $sourcecontainer, $sourceobject, $destinationcontainer,
        $destinationobject )
      = @_;

    my $dest = join '/', $destinationcontainer, $destinationobject;

    return $self->_object_request( 'copy',
        { headers => [ 'Destination' => $dest ] },
        $sourcecontainer, $sourceobject );
}

1;
