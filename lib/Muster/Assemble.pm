package Muster::Assemble;

#ABSTRACT: Muster::Assemble - page rendering
=head1 NAME

Muster::Assemble - page rendering

=head1 SYNOPSIS

    use Muster::Assemble;

=head1 DESCRIPTION

Content Management System - page rendering

=cut
use Mojo::Base -base;

use Carp;
use Muster::MetaDb;
use Muster::Leaf::File;
use File::Slurper 'read_binary';
use YAML::Any;

=head1 Methods

=head2 init

Initialize.

=cut
sub init {
    my $self = shift;
    my $c = shift;
    my $app = $c->app;

    if (!$self->{metadb})
    {
        $self->{metadb} = Muster::MetaDb->new(%{$app->config});
        $self->{metadb}->init();
    }
    return $self;
} # init

=head2 serve_page

Serve one page.

=cut
sub serve_page {
    my $self = shift;
    my $c = shift;
    my $app = $c->app;

    $self->init($c);

    my $pagename = $c->param('pagename') // 'index';

    my $info = $self->{metadb}->page_info($pagename);
    my $leaf = undef;
    if (-f $info->{filename})
    {
        $leaf = Muster::Leaf::File->new(%{$info});
        $leaf = $leaf->reclassify();
    }

    unless (defined $leaf)
    {
        $c->reply->not_found;
        return;
    }

    if ($leaf->pagetype eq 'NonPage')
    {
        $self->_serve_file($c, $leaf->filename);
    }
    else
    {
        my $html = $leaf->html();
        unless (defined $html)
        {
            $c->reply->not_found;
            return;
        }

        $c->stash('pagename' => $pagename);
        $c->stash('content' => $html);
        $c->render(template => 'page');
    }
}

=head2 serve_meta

Serve the meta-data for a page (for debugging purposes)

=cut
sub serve_meta {
    my $self = shift;
    my $c = shift;
    my $app = $c->app;

    $self->init($c);

    my $pagename = $c->param('pagename') // 'index';

    my $info = $self->{metadb}->page_info($pagename);
    unless (defined $info)
    {
        $c->reply->not_found;
        return;
    }

    my $html = "<pre>\n" . Dump($info) . "\n</pre>\n";

    $c->stash('pagename' => $pagename);
    $c->stash('content' => $html);
    $c->render(template => 'page');
}

=head1 Helper Functions

=head2 _serve_file

Serve a file rather than a page.
    
    $self->_serve_file($filename);

=cut

sub _serve_file {
    my $self = shift;
    my $c = shift;
    my $filename = shift;

    if (!-f $filename)
    {
        # not found
        return;
    }
    # extenstion is format (exclude the dot)
    my $ext = '';
    if ($filename =~ /\.(\w+)$/)
    {
        $ext = $1;
    }
    # read the image
    my $bytes = read_binary($filename);

    # now display the logo
    $c->render(data => $bytes, format => $ext);
} # _serve_file

1;
# end of Muster::Assemble
