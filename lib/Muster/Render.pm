package Muster::Render;

#ABSTRACT: Muster::Render - page rendering
=head1 NAME

Muster::Render - page rendering

=head1 SYNOPSIS

    use Muster::Render;

=head1 DESCRIPTION

Content Management System - page rendering

=cut
use Mojo::Base -base;

use Carp;

has backlinks   => sub { {} };
has rendered    => sub { {} };
has scanned     => sub { {} };


1;
