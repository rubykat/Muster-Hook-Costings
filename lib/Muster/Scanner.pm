package Muster::Scanner;

#ABSTRACT: Muster::Scanner - updating meta-data about pages
=head1 NAME

Muster::Scanner - updating meta-data about pages

=head1 DESCRIPTION

Content Management System
keeping meta-data about pages.

=cut

use Mojo::Base -base;
use Carp;
use Muster::MetaDb;
use Muster::LeafFile;
use Muster::Hooks;
use File::Spec;
use File::Find;
use YAML::Any;
use Module::Pluggable search_path => ['Muster::Hook'], instantiate => 'new';

has command => sub { croak "command is not defined" };

=head1 METHODS

=head2 init

Set the defaults for the object if they are not defined already.

=cut
sub init {
    my $self = shift;
    my $app = $self->command->app;

    $self->{page_dirs} = [];
    foreach my $pd (@{$app->config->{page_dirs}})
    {
        my $pages_dir = File::Spec->rel2abs($pd);
        if (-d $pages_dir)
        {
            push @{$self->{page_dirs}}, $pages_dir;
        }
        else
        {
            croak "pages dir '$pages_dir' not found!";
        }
    }

    $self->{metadb} = Muster::MetaDb->new(%{$app->config});
    $self->{metadb}->init();

    $self->{hookmaster} = Muster::Hooks->new();
    $self->{hookmaster}->init($app->config);

    return $self;
} # init

=head2 scan_one_page

Scan a single page.

    $self->scan_one_page($page);

=cut

sub scan_one_page {
    my $self = shift;
    my $pagename = shift;

    $pagename = 'index' if !$pagename;

    my $found_page;
    foreach my $page_dir (@{$self->{page_dirs}})
    {
        my $finder = sub {

            # only interested in files with extensions
            if ($File::Find::name =~ /\.\w+$/)
            {
                my $chopped_file = $File::Find::name;
                $chopped_file =~ s/\.\w+$//;
                # this 'pagefile' won't be the file itself
                # it will be the file without its extension
                my $pagefile = File::Spec->catfile($page_dir, $pagename);

                if (-f -r $File::Find::name and $chopped_file eq $pagefile)
                {
                    warn "SCANNING: $File::Find::name\n";
                    my $leaf = $self->_create_and_scan_leaf(
                        page_dir=>$page_dir,
                        filename=>$File::Find::name,
                        dir=>$File::Find::dir,
                    );
                    if ($leaf)
                    {
                        if (!$found_page)
                        {
                            $found_page = $leaf;
                        }
                    }
                }
            }
        };
        # Using no_chdir because reclassify needs to "require" modules
        # and the current @INC might just be relative
        find({wanted=>$finder, no_chdir=>1}, $page_dir);
    }

    unless (defined $found_page)
    {
        warn __PACKAGE__, " scan_one_page page '$pagename' not found";
        return;
    }

    my $meta = $found_page->meta();
    unless (defined $meta)
    {
        warn __PACKAGE__, " scan_one_page meta for '$pagename' not found";
        return;
    }
    # add the meta to the metadb
    $self->{metadb}->update_one_page($pagename, %{$meta});

    print Dump($meta);

} # scan_one_page

=head2 delete_one_page

Delete a single page.

    $self->delete_one_page($page);

=cut

sub delete_one_page {
    my $self = shift;
    my $pagename = shift;

    if ($self->{metadb}->delete_one_page($pagename))
    {
        print "DELETED: $pagename\n";
    }
    else
    {
        print "UNKNOWN: $pagename\n";
    }

} # delete_one_page

=head2 scan_all

Scan all pages.

=cut

sub scan_all {
    my $self = shift;

    $self->_find_and_scan_all();

    print "DONE\n";
} # scan_all

=head2 _find_and_scan_all

Use File::Find to find and scan all page files..

=cut

sub _find_and_scan_all {
    my $self = shift;

    my %all_pages = ();

    # We do this in a loop per page-directory
    # because we need to know what the current page_dir is
    # in order to calculate what the pagename ought to be
    # which means we need to define the "wanted" function
    # inside the loop so that it knows the value of $page_dir
    #
    # Note that if a page has already been found, any later pages are ignored
    foreach my $page_dir (@{$self->{page_dirs}})
    {
        my $finder = sub {

            # skip hidden files
            if (-f -r $File::Find::name and $File::Find::name !~ /(^\.|\/\.)/)
            {
                warn "SCANNING: $File::Find::name\n";
                my $leaf = $self->_create_and_scan_leaf(
                    page_dir=>$page_dir,
                    filename=>$File::Find::name,
                    dir=>$File::Find::dir,
                );
                if ($leaf)
                {
                    my $page = $leaf->pagename;
                    if (!exists $all_pages{$page})
                    {
                        $all_pages{$page} = $leaf->meta;
                    }
                }
            }
        };
        # Using no_chdir because reclassify needs to "require" modules
        # and the current @INC might just be relative
        find({wanted=>$finder, no_chdir=>1}, $page_dir);
    }

    $self->{metadb}->update_all_pages(%all_pages);
} # _find_and_scan_all

=head2 _create_and_scan_leaf

Create and scan a leaf (which contains meta-data and content).
    
    $leaf = $self->_create_and_scan_leaf(page_dir=>$page_dir, filename=>$File::Find::name, dir=>$File::Find::dir);

=cut

sub _create_and_scan_leaf {
    my $self = shift;
    my %args = @_;

    my $page_dir = $args{page_dir};
    my $filename = $args{filename};
    my $dir = $args{dir};

    # -------------------------------------------
    # Create
    # -------------------------------------------
    my $parent_page = $dir;
    $parent_page =~ s!${page_dir}!!;
    $parent_page =~ s!^/!!; # remove the leading /

    my $leaf = Muster::LeafFile->new(
        filename    => $filename,
        parent_page => $parent_page,
    );
    $leaf = $leaf->reclassify();
    if (!$leaf)
    {
        croak "ERROR: leaf did not reclassify\n";
    }

    return $self->{hookmaster}->run_hooks(leaf=>$leaf,
        command=>$self->command,
        phase=>$Muster::Hooks::PHASE_SCAN);
} # _create_and_scan_leaf

1; # End of Muster::Scanner
__END__
