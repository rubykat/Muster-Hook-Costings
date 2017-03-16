package Muster::Crate;

#ABSTRACT: Muster::Crate - container for meta-data about pages and globals
=head1 NAME

Muster::Crate - container for meta-data about pages and globals

=head1 DESCRIPTION

Content Management System
Container meta-data about pages and globals.
During the scanning pass, we collect per-page data
and also global data (such as shortcuts).
This is a container for that.

=cut

use Mojo::Base -base;
use Hash::Merge;
use Carp;
use YAML::Any;

has pageinfo => undef;
has globals => undef;
has contents => '';

=head1 METHODS

=head2 init

Set the defaults for the object if they are not defined already.

=cut
sub init {
    my $self = shift;

    return $self;
} # init

=head2 add_to_pageinfo

Adds more meta to the pageinfo without overwriting the original.

=cut
sub add_to_pageinfo {
    my $self = shift;
    my $more_pageinfo = shift;

    my $merge = Hash::Merge->new();
    my $new_info = $merge->merge($self->{pageinfo}, $more_pageinfo);
    $self->{pageinfo} = $new_info;
    return $self;
} # add_to_pageinfo

=head2 add_to_globals

Adds more meta to the globals without overwriting the original.

=cut
sub add_to_globals {
    my $self = shift;
    my $more_globals = shift;

    my $merge = Hash::Merge->new();
    my $new_info = $merge->merge($self->{globals}, $more_globals);
    $self->{globals} = $new_info;
    return $self;
} # add_to_globals

1; # End of Muster::Crate
__END__
