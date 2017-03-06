package Muster::Controller::Pages;

#ABSTRACT: Muster::Controller::Pages - Pages controller for Muster
=head1 NAME

Muster::Controller::Pages - Pages controller for Muster

=head1 SYNOPSIS

    use Muster::Controller::Pages;

=head1 DESCRIPTION

Pages controller for Muster

=cut

use Mojo::Base 'Mojolicious::Controller';

sub options {
    my $c  = shift;
    $c->muster_set_options();
    $c->render(template => 'settings');
}

sub pagelist {
    my $c  = shift;
    $c->render(template=>'pagelist');
}

sub page {
    my $c  = shift;
    $c->muster_serve_page();
}

sub debug {
    my $c  = shift;
    my $pagename = $c->param('pagename');
    $c->reply->exception("Debug" . (defined $pagename ? " $pagename" : ''));
}

1;
