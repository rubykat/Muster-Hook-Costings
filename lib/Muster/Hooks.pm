package Muster::Hooks;

#ABSTRACT: Muster::Hooks - scanning and processing hooks
=head1 NAME

Muster::Hooks - scanning and processing hooks

=head1 DESCRIPTION

Content Management System
scanning and processing hooks

=cut

use Mojo::Base -base;
use Carp;
use Muster::LeafFile;
use Muster::Hook;
use File::Spec;
use File::Find;
use YAML::Any;
use Module::Pluggable search_path => ['Muster::Hook'], instantiate => 'new';

=head1 METHODS

=head2 init

Set the defaults for the object if they are not defined already.

=cut
sub init {
    my $self = shift;
    my $config = shift;

    # Hooks are defined by Muster::Hook objects. The Pluggable module will find
    # all possible hooks but the config will have defined a subset in the order
    # we want to apply them.
    # The way this is done is that we call "register" for the hooks in that order,
    # and while a given hook object may have more than one callback, at least
    # all of the hooks for THAT module will come after the module before, etc.
    $self->{hooks} = {};
    $self->{hookorder} = [];
    my %phooks = ();
    foreach my $ph ($self->plugins())
    {
        $phooks{ref $ph} = $ph;
    }
    foreach my $hookmod (@{$config->{hooks}})
    {
        my $cf = $config->{hook_conf}->{$hookmod};
        if ($phooks{$hookmod})
        {
            $phooks{$hookmod}->register($self,$cf);
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

=head2 run_hooks

Run the hooks over the given leaf.
Leaf must already be created and reclassified.
The "scanning" flag says whether we are scanning or assembling.
    
    $leaf = $self->run_hooks(leaf=>$leaf,scanning=>$scanning);

=cut

sub run_hooks {
    my $self = shift;
    my %args = @_;

    my $leaf = $args{leaf};
    my $scanning = $args{scanning};

    foreach my $hn (@{$self->{hookorder}})
    {
        $leaf = $self->{hooks}->{$hn}($leaf,$scanning);
    }

    return $leaf;
} # run_hooks

1; # End of Muster::Hooks
__END__
