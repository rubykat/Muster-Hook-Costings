package Muster::Directive;
use Mojo::Base -base;
use Muster::Crate;

use Carp 'croak';

=encoding utf8

=head1 NAME

Muster::Directive - Muster directive base class

=head1 SYNOPSIS

  # CamelCase plugin name
  package Muster::Directive::MyDirective;
  use Mojo::Base 'Muster::Directive';

  sub init {
      my $self = shift;

      return $self;
  }

  sub scan {
    my ($self, $crate) = @_;

    # Magic here! :)

    return $crate;
  }

  sub process {
    my ($self, $crate) = @_;

    # Magic here! :)

    return $crate;
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

=head2 init

Do some intialization.

=cut
sub init {
    my $self = shift;
    return $self;
}

=head2 scan

Scans a crate object, updating it with meta-data.
May leave the crate untouched.

Expects the parameters to the directive.

  my $new_crate = $self->scan($crate,%params);

=cut

sub scan { 
    my $self = shift;
    my $crate = shift;
    my %params = @_;

    return "";
}

=head2 process

Processes the "cooked" attribute of a crate object, as part of its processing.
May leave the crate untouched.

  my $new_crate = $self->process($crate,%params);

=cut

sub process { 
    my $self = shift;
    my $crate = shift;
    my %params = @_;

    return "";
}

1;
