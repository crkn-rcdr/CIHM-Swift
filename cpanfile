requires 'strictures', 2;
requires 'Carp';
requires 'Moo';
requires 'Types::Standard';
requires 'Furl';
requires 'JSON';
requires 'XML::LibXML';
requires 'MIME::Types';
requires 'URI';
requires 'namespace::clean';

on 'test' => sub {
  requires 'Test::More';
  requires 'Test::RequiresInternet';
  requires 'Test::Pod';
};