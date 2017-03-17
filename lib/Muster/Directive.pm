package Muster::Directive;
use Mojo::Base -base;
use Muster::LeafFile;

use Carp 'croak';

=encoding utf8

=head1 NAME

Muster::Directive - Muster directive base class

=head1 SYNOPSIS

  # CamelCase plugin name
  package Muster::Directive::MyDirective;
  use Mojo::Base 'Muster::Directive';

  sub register {
      my $self = shift;

      return $self;
  }

  sub scan {
    my ($self, $leaf) = @_;

    # Magic here! :)

    return $leaf;
  }

  sub process {
    my ($self, $leaf) = @_;

    # Magic here! :)

    return $leaf;
  }

=head1 DESCRIPTION

L<Muster::Directive> is an abstract base class for L<Muster> directives.
Directives are a special type of hook.

=head1 METHODS

L<Muster::Directive> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 id

The id of the directive. Used as the command-name.
By default, it is the last component of the class name,
but it can be called something else instead.

=cut

sub id {
    my $class = shift;
    
    my $fullname = (ref ($class) ? ref ($class) : $class);

    my @bits = split('::', $fullname);
    return pop @bits;
}

=head2 register_directive

Register

=cut
sub register_directive {
    my $self = shift;
    my $scanner = shift;
    my $conf = shift;

    return $self;
} # register_directive

=head2 process

Scan or Processes a leaf object, as part of its processing.
May leave the leaf untouched.

  my $new_leaf = $self->process($leaf,$scan,%params);

=cut

sub process { 
    my $self = shift;
    my $leaf = shift;
    my $scan = shift;
    my %params = @_;

    return "";
}

1;
