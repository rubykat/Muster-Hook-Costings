package Muster::PageStore;

#ABSTRACT: Muster::PageStore - a store of pages
=head1 NAME

Muster::PageStore - a store of pages

=head1 SYNOPSIS

    use Muster::PageStore;

=head1 DESCRIPTION

Content Management System - a store of pages

=cut
use Mojo::Base -base;

use Carp;

has parent_page => '';
has name        => sub { shift->build_name };
has pagename        => sub { shift->build_pagename };
has leaf        => sub { shift->this_leaf };

sub this_leaf {
    my $self = shift;
    croak 'this_leaf needs to be overwritten by subclass';
}

sub build_name {
    my $self = shift;
    croak 'build_name needs to be overwritten by subclass';
}

sub build_pagename {
    my $self = shift;
    croak 'build_pagename needs to be overwritten by subclass';
}

sub get_all_meta {
    my $self = shift;
    croak 'get_all_meta needs to be overwritten by subclass';
}

sub find {
    my ($self, @names) = @_;

    # can only return self, we ain't searching
    return $self unless @names;

    # not found
    return;
}

1;
