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
use Muster::Assemble;
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
    my $mojo_config = $self->plugin('Config' => { file => $conf_file });

    # -------------------------------------------
    # New commands in Muster::Command namespace
    # -------------------------------------------
    push @{$self->commands->namespaces}, 'Muster::Command';

    # -------------------------------------------
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
    }
 
    # -------------------------------------------
    # Pages
    # -------------------------------------------
    $self->plugin('Muster::PagesHelper');
    
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
    # Rendering
    # -------------------------------------------
    $self->{assemble} = Muster::Assemble->new();

    my $do_pagelist = sub {
        my $c  = shift;
        $c->render(template=>'pagelist');
    };
    my $do_page = sub {
        my $c  = shift;
        $self->{assemble}->serve_page($c);
    };
    my $do_meta = sub {
        my $c  = shift;
        $self->{assemble}->serve_meta($c);
    };
    my $do_debug = sub {
        my $c  = shift;

        my $pagename = $c->param('cpath');
        $c->reply->exception("Debug" . (defined $pagename ? " $pagename" : ''));
    };
    my $r = $self->routes;

    $r->get('/' => $do_page);
    $r->get('/pagelist' => $do_pagelist);
    $r->get('/debug' => $do_debug);
    $r->get('/debug/*cpath' => $do_debug);
    $r->get('/meta/*cpath' => $do_meta);
    # anything else should be a page or file
    $r->get('/*cpath' => $do_page);
}

1; # end of Muster

# Here come the TEMPLATES!

__DATA__

