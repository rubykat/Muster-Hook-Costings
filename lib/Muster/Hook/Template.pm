package Muster::Hook::Template;

=head1 NAME

Muster::Hook::Template - Muster template directive.

=head1 DESCRIPTION

L<Muster::Hook::Template> for template directives inside pages.

=cut

use Mojo::Base 'Muster::Hook::Directives';
use Muster::LeafFile;
use Muster::Hooks;
use Muster::Hook::Links;
use File::Basename qw(basename);
use YAML::Any;
use Module::Runtime qw(require_module);

use Carp 'croak';

=head1 METHODS

L<Muster::Hook::Template> inherits all methods from L<Muster::Hook::Directives>.

=head2 register

Do some intialization.

=cut
sub register {
    my $self = shift;
    my $hookmaster = shift;
    my $conf = shift;

    my $res = eval { require_module('Text::NeatTemplate') };
    if ($@) # template module not found
    {
        # return without adding a hook
        return $self;
    }
    $self->{neat} = Text::NeatTemplate->new();

    $hookmaster->add_hook('template' => sub {
            my %args = @_;

            return $self->do_directives(
                no_scan=>1,
                directive=>'template',
                call=>sub {
                    my %args2 = @_;

                    return $self->process(directive=>'template',%args2);
                },
                %args,
            );
        },
    );
    return $self;
} # register

=head2 process

Process templates.

=cut
sub process {
    my $self = shift;
    my %args = @_;

    my $directive = $args{directive};
    my $leaf = $args{leaf};
    my $phase = $args{phase};
    my @p = @{$args{params}};
    my %params = @p;

    foreach my $wanted (qw(template))
    {
        if (! exists $params{$wanted})
        {
            return "ERROR: missing $wanted parameter";
        }
    }
    if ($phase eq $Muster::Hooks::PHASE_SCAN)
    {
        return "";
    }

    # fill in the template with the leaf's data
    my $result = $self->{neat}->fill_in(
        data_hash=>$leaf->{meta},
        template=>$params{template},
    );

    return $result;
} # process

1;
