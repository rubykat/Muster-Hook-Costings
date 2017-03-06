package Muster;

# ABSTRACT: web application for content management
=head1 NAME

Muster - web application for content management

=head1 SYNOPSIS

    use Muster;

=head1 DESCRIPTION

Content management system; muster your pages.
This uses
Mojolicious
Mojolicious::Plugin::Foil

=cut

use Mojo::Base 'Mojolicious';
use Path::Tiny;
use File::ShareDir;

# This method will run once at server start
sub startup {
    my $self = shift;

    # -------------------------------------------
    # Configuration
    # check:
    # * current working directory
    # * relative to the calling program
    # -------------------------------------------
    my $the_prog = path($0)->absolute;
    my $conf_basename = "muster.conf";
    my $conf_file = path(Path::Tiny->cwd, $conf_basename);
    if (! -f $conf_file)
    {
        $conf_file = path($the_prog->parent->stringify, $conf_basename);
        if (! -f $conf_file)
        {
            $conf_file = path($the_prog->parent->parent->stringify, $conf_basename);
        }
    }
    # the MUSTER_CONFIG environment variable overrides the default
    if (defined $ENV{MUSTER_CONFIG} and -f $ENV{MUSTER_CONFIG})
    {
        $conf_file = $ENV{MUSTER_CONFIG};
    }
    print STDERR "CONFIG: $conf_file\n";
    my $mojo_config = $self->plugin('Config' => { file => $conf_file });

    # Append public directories
    # Find the Muster "public" directory
    # It could be relative to the CWD
    # It could be relative to the calling program
    # It could be in a FileShared location.
    my $pubdir = path(Path::Tiny->cwd, "public");
    if (!-d $pubdir)
    {
        $pubdir = path($the_prog->parent->stringify, "public");
        if (!-d $pubdir)
        {
            # use File::ShareDir with the distribution name
            my $dist = __PACKAGE__;
            $dist =~ s/::/-/g;
            my $dist_dir = path(File::ShareDir::dist_dir($dist));
            $pubdir = $dist_dir;
        }
    }
    if (-d $pubdir)
    {
        push @{$self->static->paths}, $pubdir;
        print STDERR "PUBLIC: $pubdir\n";
    }
 
    # -------------------------------------------
    # Pages
    # -------------------------------------------
    $self->plugin('Muster::Plugin::PagesHelper');
    
    $self->plugin('Foil');
    $self->plugin(NYTProf => $mojo_config);

    # -------------------------------------------
    # Templates
    # -------------------------------------------
    push @{$self->renderer->classes}, __PACKAGE__;

    # -------------------------------------------
    # secrets, cookies and defaults
    # -------------------------------------------
    $self->secrets([qw(aft3CoidIttenImtuj)]);
    $self->sessions->cookie_name('muster');
    $self->sessions->default_expiration(60 * 60 * 24 * 3); # 3 days
    foreach my $key (keys %{$self->config->{defaults}})
    {
        $self->defaults($key, $self->config->{defaults}->{$key});
    }

    # -------------------------------------------

    # -------------------------------------------
    # Router
    # -------------------------------------------
    my $r = $self->routes;

    $r->get('/')->to('pages#page');
    $r->get('/opt')->to('pages#options');
    $r->get('/pagelist')->to('pages#pagelist');
    $r->get('/debug')->to('pages#debug');
    $r->get('/debug/*pagename')->to('pages#debug');
    $r->get('/scan')->to('pages#scan');
    $r->get('/scan/*pagename')->to('pages#scan');
    # anything else should be a page
    $r->get('/*pagename')->to('pages#page');
}

1; # end of Muster

# Here come the TEMPLATES!

__DATA__

