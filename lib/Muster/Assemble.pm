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
use Muster::LeafFile;
use Muster::Hook;
use File::Slurper 'read_binary';
use YAML::Any;
use Module::Pluggable search_path => ['Muster::Hook'], instantiate => 'new';

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
    # Hooks are defined by Muster::Hook objects. The Pluggable module will find
    # all possible hooks but the config will have defined a subset in the order
    # we want to apply them.
    # The way this is done is that we call "register_scan" for the hooks in that order,
    # and while a given hook object may have more than one callback, at least
    # all of the hooks for THAT module will come after the module before, etc.
    $self->{hooks} = {};
    $self->{hookorder} = [];
    my %phooks = ();
    foreach my $ph ($self->plugins())
    {
        $phooks{ref $ph} = $ph;
    }
    foreach my $hookmod (@{$app->config->{hooks}})
    {
        my $cf = $app->config->{hook_conf}->{$hookmod};
        if ($phooks{$hookmod})
        {
            $phooks{$hookmod}->register_modify($self,$cf);
        }
        else
        {
            warn "Hook '$hookmod' does not exist";
        }
    }
    return $self;
} # init

=head2 add_hook

Add a hook.

=cut
sub add_hook {
    my ($self, $name, $call) = @_;
    $self->{hooks}->{$name} = $call;
    push @{$self->{hookorder}}, $name;
    return $self;
} # add_hook

=head2 serve_page

Serve one page (or a file)

=cut
sub serve_page {
    my $self = shift;
    my $c = shift;
    my $app = $c->app;

    $self->init($c);

    # If this is a page, there ought to be a trailing slash in the cpath.
    # If there isn't, either this isn't canonical, or it isn't a page.
    # However, pagenames don't have a trailing slash.
    # Yes, this is confusing.
    my $pagename = $c->param('cpath') // 'index';
    my $has_trailing_slash = 0;
    if ($pagename =~ m!/$!)
    {
        $has_trailing_slash = 1;
        $pagename =~ s!/$!!;
    }

    # now we need to find if this page exists, and what type it is
    my $info = $self->{metadb}->page_or_file_info($pagename);
    unless (defined $info and defined $info->{filename} and -f -r $info->{filename})
    {
        $c->reply->not_found;
        return;
    }
    if (!$info->{pagetype}) # a non-page
    {
        return $self->_serve_file($c, $info->{filename});
    }
    elsif (!$has_trailing_slash and $pagename ne 'index') # non-canonical
    {
        return $c->redirect_to("/${pagename}/");
    }
    # and get the global info too
    $info->{_globalinfo} = $self->{metadb}->global_info();


    my $leaf = $self->_create_and_process_leaf(%{$info});

    my $html = $leaf->html();
    unless (defined $html)
    {
        $c->reply->not_found;
        return;
    }

    $c->stash('pagename' => $pagename);
    $c->stash('content' => $html);
    $c->render(template => 'page');
} # serve_page

=head2 serve_meta

Serve the meta-data for a page (for debugging purposes)

=cut
sub serve_meta {
    my $self = shift;
    my $c = shift;
    my $app = $c->app;

    $self->init($c);

    my $pagename = $c->param('cpath') // 'index';
    $pagename =~ s!/$!!; # remove trailing slash

    my $info = $self->{metadb}->page_or_file_info($pagename);
    unless (defined $info)
    {
        $c->reply->not_found;
        return;
    }
    # and get the global info too
    $info->{_globalinfo} = $self->{metadb}->global_info();

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

=head2 _create_and_process_leaf

Create and process a leaf (which contains meta-data and content).
    
    $leaf = $self->_create_and_process_leaf(page_dir=>$page_dir, filename=>$File::Find::name, dir=>$File::Find::dir);

=cut

sub _create_and_process_leaf {
    my $self = shift;
    my %info = @_;

    # -------------------------------------------
    # Create
    # -------------------------------------------
    my $leaf = Muster::LeafFile->new(%info);
    $leaf = $leaf->reclassify();
    if (!$leaf)
    {
        croak "ERROR: leaf did not reclassify\n";
    }

    # -------------------------------------------
    # Scan
    # -------------------------------------------
    foreach my $hn (@{$self->{hookorder}})
    {
        $leaf = $self->{hooks}->{$hn}($leaf);
    }

    return $leaf;
} # _create_and_process_leaf
1;
# end of Muster::Assemble
