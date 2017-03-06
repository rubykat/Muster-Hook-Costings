package Muster::Plugin::PagesHelper;

#ABSTRACT: Muster::Plugin::PagesHelper - helping with pages
=head1 NAME

Muster::Plugin::PagesHelper - helping with pages

=head1 SYNOPSIS

    use Muster::Plugin::PagesHelper;

=head1 DESCRIPTION

Content management system; finding and showing pages.

=cut

use Mojo::Base 'Mojolicious::Plugin';
use Muster::Pages;
use Muster::Leaf;
use Muster::MetaDb;
use common::sense;
use DBI;
use Text::NeatTemplate;
use YAML::Any;
use POSIX qw(ceil);
use Mojo::URL;

=head1 REGISTER

=cut

sub register {
    my ( $self, $app, $conf ) = @_;

    $self->_init($app,$conf);

    $app->helper( 'muster_serve_page' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_serve_page($c);
    } );

    $app->helper( 'muster_total_pages' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_total_pages($c,%args);
    } );

    $app->helper( 'muster_page_related_list' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_make_page_related_list($c,%args);
    } );

    $app->helper( 'muster_pagelist' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_pagelist($c,%args);
    } );

    $app->helper( 'muster_set_options' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_set_options($c,%args);
    } );
    $app->helper( 'muster_settings' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_settings($c,%args);
    } );
}

=head1 Helper Functions

These are functions which are NOT exported by this plugin.

=cut

=head2 _init

Initialize.

=cut
sub _init {
    my $self = shift;
    my $app = shift;
    my $conf = shift;

    $self->{pages} = Muster::Pages->new(page_sources => $app->config->{page_sources});
    $self->{pages}->init();
    $self->{metadb} = Muster::MetaDb->new(%{$app->config});
    $self->{metadb}->init();
    return $self;
} # _init

=head2 _serve_page

Serve a single page.

=cut

sub _serve_page {
    my $self = shift;
    my $c = shift;
    my $app = $c->app;

    my $pagename = $c->param('pagename') // '';

    my $leaf = $self->{pages}->find($pagename);
    unless (defined $leaf)
    {
        $c->reply->not_found;
        return;
    }

    my $html = $leaf->html();
    unless (defined $html)
    {
        $c->reply->not_found;
        return;
    }

    $c->stash('pagename' => $pagename);
    $c->stash('content' => $html);
    $c->render(template => 'page');

    # cache this page or not?
    $leaf->decache unless $app->config->{'cached'};
} # _serve_page

=head2 _total_pages

Return the total number of records in this db

=cut

sub _total_pages {
    my $self  = shift;
    my $c  = shift;

    my $total = $self->{pages}->total_pages();
    if (!defined $total)
    {
        $c->render(template => 'apperror',
            errormsg=>$self->{pages}->what_error());
        return undef;
    }
    return $total;
} # _total_pages

=head2 _make_page_related_list

Make a list of related pages to this page.

=cut

sub _make_page_related_list {
    my $self  = shift;
    my $c  = shift;

    my $pagename = $c->param('pagename');
    my @out = ();
    push @out, "<div class='pagelist'><ul>";
    push @out, "<li>$pagename</li>";
    push @out, "</ul></div>";
    my $out = join("\n", @out);
    return $out;
} # _make_page_related_list

=head2 _pagelist

Make a pagelist

=cut

sub _pagelist {
    my $self  = shift;
    my $c  = shift;

    my $pagename = $c->param('pagename') // '';
    my $opt_url = $c->url_for("/opt");
    my $location = $c->url_for($pagename);
    my $res = $self->{pages}->pagelist(location=>$location,
        opt_url=>$opt_url,
        pagename=>$pagename,
        n=>0,
    );
    if (!defined $res)
    {
        $c->render(template => 'apperror',
            errormsg=>$self->{pages}->what_error());
        return undef;
    }
    return $res->{results};
} # _pagelist

=head2 _set_options

Set options in the session

=cut

sub _set_options {
    my $self  = shift;
    my $c  = shift;
    my %args = @_;

    # Set options for things like n
    my @db = (sort keys %{$self->{dbtables}});

    my @fields = (qw(n));
    foreach my $db (@db)
    {
        push @fields, "${db}_sort_by";
        push @fields, "${db}_sort_by2";
        push @fields, "${db}_sort_by3";
    }
    my %fields_set = ();
    foreach my $field (@fields)
    {
        my $val = $c->param($field);
        if ($val)
        {
            $c->session->{$field} = $val;
            $fields_set{$field} = 1;
        }
        else
        {
            if ($field =~ /(\w+)_sort_by./)
            {
                # We want to delete later sort-by values
                # if they are blank and the first one was set,
                # because we want to be able to sort by just
                # one or two fields if we want.
                my $db = $1;
                if ($fields_set{"${db}_sort_by"})
                {
                    delete $c->session->{$field};
                }
            }
        }
    }
    my $referrer = $c->req->headers->referrer;
} # _set_options

=head2 _settings

Show the current settings

=cut

sub _settings {
    my $self  = shift;
    my $c  = shift;
    my %args = @_;

    my $db = $c->param('db');

    my @fields = (qw(n));
    push @fields, "${db}_sort_by";
    push @fields, "${db}_sort_by2";
    push @fields, "${db}_sort_by3";
    
    my @out = ();
    foreach my $field (@fields)
    {
        my $val = $c->session->{$field};
        push @out, "<p><b>$field:</b> $val</p>";
    }
    my $referrer = $c->req->headers->referrer;
    print STDERR "_settings referrer=$referrer\n";
    push @out, "<p>Back: <a href='$referrer'>$referrer</a></p>";

    return join("\n", @out);
} # _settings

1; # End of Muster::Plugin::PagesHelper
__END__
