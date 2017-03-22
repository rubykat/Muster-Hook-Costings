package Muster::PagesHelper;

#ABSTRACT: Muster::PagesHelper - helping with pages
=head1 NAME

Muster::PagesHelper - helping with pages

=head1 SYNOPSIS

    use Muster::PagesHelper;

=head1 DESCRIPTION

Content management system; getting and showing pages.

=cut

use Mojo::Base 'Mojolicious::Plugin';
use Carp;
use Muster::MetaDb;
use common::sense;
use Text::NeatTemplate;
use YAML::Any;
use File::Basename 'basename';
use Mojo::URL;
use HTML::LinkList;

=head1 REGISTER

=cut

sub register {
    my ( $self, $app, $conf ) = @_;

    $self->_init($app,$conf);

    $app->helper( 'muster_sidebar' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_sidebar($c,%args);
    } );
    $app->helper( 'muster_rightbar' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_rightbar($c,%args);
    } );
    $app->helper( 'muster_header' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_header($c,%args);
    } );
    $app->helper( 'muster_footer' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_footer($c,%args);
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
    $app->helper( 'muster_page_attachments_list' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_make_page_attachments_list($c,%args);
    } );

    $app->helper( 'muster_pagelist' => sub {
        my $c        = shift;
        my %args = @_;

        return $self->_pagelist($c,%args);
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

    $self->{metadb} = Muster::MetaDb->new(%{$app->config});
    $self->{metadb}->init();
    $self->{hookmaster} = Muster::Hooks->new();
    $self->{hookmaster}->init($app->config);
    return $self;
} # _init

=head2 _sidebar

Fill in the sidebar.
I have decided, for the sake of speed, to "hardcode" the contents of the sidebar,
considering that for some pages it too 2.5 seconds to load the page with an external sidebar,
and only .6 seconds when using the internal default.

=cut

sub _sidebar {
    my $self  = shift;
    my $c  = shift;

    my $pagename = $c->param('cpath');
    $pagename =~ s!/$!!; # remove trailing slash -- TEMPORARY FIX

    my $info = $self->{metadb}->page_or_file_info($pagename);
    my $out = $self->_make_page_related_list($c);
    return "<nav>$out</nav>\n";
} # _sidebar

=head2 _rightbar

Fill in the rightbar.
I have decided, for the sake of speed, to "hardcode" the contents of the rightbar also.

=cut

sub _rightbar {
    my $self  = shift;
    my $c  = shift;

    my $pagename = $c->param('cpath');
    $pagename =~ s!/$!!; # remove trailing slash -- TEMPORARY FIX

    my $info = $self->{metadb}->page_or_file_info($pagename);
    my $total = $self->_total_pages($c);
    my $atts = $self->_make_page_attachments_list($c);
    my $out=<<EOT;
<p class="total">$total pages</p>
$atts
EOT
        return $out;
} # _rightbar

=head2 _header

Fill in the header.
By default, there is no page header.
But for some pages, this is heavily depended upon.

=cut

sub _header {
    my $self  = shift;
    my $c  = shift;

    my $pagename = $c->param('cpath');
    $pagename =~ s!/$!!; # remove trailing slash -- TEMPORARY FIX
    my $side_page = $self->_find_side_page(current_page=>$pagename, side_page=>'_Header');
    if ($side_page)
    {
        my $leaf = $self->_process_side_page(current_page=>$pagename, side_page=>$side_page);
        return $leaf->html;
    }

    return "";
} # _header

=head2 _footer

Fill in the footer.
By default, there is no page footer.
But for some pages, this is heavily depended upon.

=cut

sub _footer {
    my $self  = shift;
    my $c  = shift;

    my $pagename = $c->param('cpath');
    $pagename =~ s!/$!!; # remove trailing slash -- TEMPORARY FIX
    my $side_page = $self->_find_side_page(current_page=>$pagename, side_page=>'_Footer');
    if ($side_page)
    {
        my $leaf = $self->_process_side_page(current_page=>$pagename, side_page=>$side_page);
        return $leaf->html;
    }

    return "";
} # _footer

=head2 _find_side_page

Find the desired Sidebar/Rightbar/Header/Footer page which
applies to the given page.
First search in the same level as the page, then in its
parent level, and so on.

    my $spage = $self->_find_side_page(current_page=>$page,side_page=>'_Sidebar');

=cut
sub _find_side_page {
    my $self = shift;
    my %args = @_;

    my $current_page = $args{current_page};
    my $side_page = $args{side_page};
    my $cp_info = $self->{metadb}->page_or_file_info($current_page);

    # find a "local" side-page first, which has priority
    # This will have an extra '_' at the front of it.
    # This can only be in the same folder as the current page.
    my $local_sp = $cp_info->{parent_page} . '/_' . $side_page;
    if ($self->{metadb}->page_exists($local_sp))
    {
        return $local_sp;
    }

    my @bits = split('/', $current_page);
    my $found_page = '';
    do {
        my $cwd = join('/', @bits);
        my $q = "SELECT page FROM pagefiles WHERE name = '$side_page' AND parent_page IN (SELECT parent_page FROM pagefiles WHERE page = '$cwd');";
        my $pages = $self->{metadb}->query($q);
        if ($pages)
        {
            $found_page = $pages->[0];
        }
        pop @bits;
    } while (scalar @bits and !$found_page);

    return $found_page;
} # _find_side_page

=head2 _process_side_page

Process the contents of the given side-page as if it had the meta-data of the given page.

    my $content = $self->_process_side_page(current_page=>$page,side_page=>'_Sidebar');

=cut
sub _process_side_page {
    my $self = shift;
    my %args = @_;

    my $current_page = $args{current_page};
    my $side_page = $args{side_page};
    my $cp_info = $self->{metadb}->page_or_file_info($current_page);
    my $side_info = $self->{metadb}->page_or_file_info($side_page);

    my $side_leaf = Muster::LeafFile->new(%{$side_info});
    $side_leaf = $side_leaf->reclassify();
    if (!$side_leaf)
    {
        croak "ERROR: leaf did not reclassify\n";
    }

    my $cp_leaf = Muster::LeafFile->new(%{$cp_info});
    $cp_leaf = $cp_leaf->reclassify();
    if (!$cp_leaf)
    {
        croak "ERROR: leaf did not reclassify\n";
    }

    # set the content
    my $content = $side_leaf->raw;
    $cp_leaf->{cooked} = $content;

    return $self->{hookmaster}->run_hooks(leaf=>$cp_leaf,scanning=>0);
} # _process_side_page

=head2 _total_pages

Return the total number of records in this db

=cut

sub _total_pages {
    my $self  = shift;
    my $c  = shift;

    my $total = $self->{metadb}->total_pages();
    if (!defined $total)
    {
        $c->render(template => 'apperror',
            errormsg=>"UNKNOWN");
        return undef;
    }
    return $total;
} # _total_pages

=head2 _make_page_attachments_list

Make a list of related pages to this page.

=cut

sub _make_page_attachments_list {
    my $self  = shift;
    my $c  = shift;

    my $pagename = $c->param('cpath');
    $pagename =~ s!/$!!; # remove trailing slash -- TEMPORARY FIX

    my $info = $self->{metadb}->page_or_file_info($pagename);
    my $att_list = '';
    if ($info and $info->{attachments})
    {
        my @att = ();
        my %labels = ();
        # just link to the basenames, since this should be relative
        foreach my $att (@{$info->{attachments}})
        {
            my $bn = basename($att);
            push @att, $bn;
            $labels{$bn} = $bn;
        }
        $att_list = HTML::LinkList::link_list(
            urls=>\@att,
            labels=>\%labels,
        );
        $att_list = "<div><p><b>Attachments:</b></p>$att_list</div>" if $att_list;
    }
    
    return $att_list;
} # _make_page_attachments_list

=head2 _make_page_related_list

Make a list of related pages to this page.

=cut

sub _make_page_related_list {
    my $self  = shift;
    my $c  = shift;

    my $pagename = $c->param('cpath');
    $pagename =~ s!/$!!; # remove trailing slash -- TEMPORARY FIX

    # for this, add a leading and trailing slash to every page
    my @pagenames = map { '/' . $_ . '/' } $self->{metadb}->pagelist();

    my $link_list = HTML::LinkList::nav_tree(
        current_url=>"/$pagename/",
        paths=>\@pagenames,
    );

    return $link_list;
} # _make_page_related_list

=head2 _pagelist

Make a pagelist

=cut

sub _pagelist {
    my $self  = shift;
    my $c  = shift;

    my $location = $c->url_for('pagelist');
    # for this, add a leading and trailing slash to every page
    my @pagenames = map { '/' . $_ . '/' } $self->{metadb}->pagelist();

    my $link_list = HTML::LinkList::full_tree(
        current_url=>$location,
        paths=>\@pagenames,
    );
    return $link_list;
} # _pagelist

1; # End of Muster::PagesHelper
__END__
