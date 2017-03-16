package Muster::Hook;
use Mojo::Base -base;
use Muster::Crate;

use Carp 'croak';

sub scan { 
    my ($self, $crate) = @_;

    return $crate;
}

sub modify { 
    my ($self, $crate) = @_;

    return $crate;
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
    my ($self, $crate) = @_;

    # Magic here! :)

    return $crate;
  }

  sub modify {
    my ($self, $crate) = @_;

    # Magic here! :)

    return $crate;
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

Scans a crate object, updating it with meta-data.
It may also update the "content" attribute of the crate object, in order to
prevent earlier-scanned things being re-scanned by something else later in the
scanning pass.
May leave the crate untouched.

  my $new_crate = $self->scan($crate);

=head2 modify

Modifies the content attribute of a crate object, as part of its processing.
May leave the crate untouched.

  my $new_crate = $self->modify($crate);

=cut

