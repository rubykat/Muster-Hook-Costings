package Muster::Hook;
use Mojo::Base -base;
use Muster::Leaf;

use Carp 'croak';

sub scan { 
    my ($self, $leaf) = @_;

    return $leaf;
}

sub modify { 
    my ($self, $leaf) = @_;

    return $leaf;
}

sub init {
    my $self = shift;
    return $self;
}

1;

=encoding utf8

=head1 NAME

Muster::Hook - Muster hook base class

=head1 SYNOPSIS

  # CamelCase plugin name
  package Muster::Hook::MyHook;
  use Mojo::Base 'Muster::Hook';

  sub init {
      my $self = shift;

      return $self;
  }

  sub scan {
    my ($self, $leaf) = @_;

    # Magic here! :)

    return $leaf;
  }

  sub modify {
    my ($self, $leaf) = @_;

    # Magic here! :)

    return $leaf;
  }

=head1 DESCRIPTION

L<Muster::Hook> is an abstract base class for L<Muster> hooks.

I was thinking of separating out "scanner" hooks and "modification" hooks,
but for some, you want to have everything together (such as processing links);
the data collected in the scanning pass will be used in the assembly pass.

=head1 METHODS

L<Muster::Hook> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 scan

Scans a leaf object, updating it with meta-data.
May leave the leaf untouched.

  my $new_leaf = $self->scan($leaf);

=head2 modify

Modifies the "cooked" attribute of a leaf object, as part of its processing.
May leave the leaf untouched.

  my $new_leaf = $self->modify($leaf);

=cut

