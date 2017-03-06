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

has path        => '';
has path_prefix => '';
has name        => sub { shift->build_name };
has meta        => sub { {} };
has html        => sub { shift->build_html };
has raw         => sub { shift->build_raw };
has title       => sub { shift->build_title };

sub build_name {
    my $self = shift;
    croak 'build_name needs to be overwritten by subclass';
}

sub build_html {
    my $self = shift;
    croak 'build_html needs to be overwritten by subclass';
}

sub build_raw {
    my $self = shift;
    croak 'build_raw needs to be overwritten by subclass';
}

sub build_title {
    my $self = shift;

    # try to extract title
    return $self->meta->{title} if exists $self->meta->{title};
    return $1 if defined $self->html and $self->html =~ m|<h1>(.*?)</h1>|i;
    return $self->name;
}

sub get_all_meta {
    my $self = shift;
    croak 'get_all_meta needs to be overwritten by subclass';
}

sub find {
    my ($self, $path) = @_;

    # no search
    return $self unless $path;

    # not found
    return;
}

1;
