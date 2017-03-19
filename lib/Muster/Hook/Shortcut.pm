package Muster::Hook::Shortcut;
use Mojo::Base 'Muster::Hook::Directives';
use Muster::LeafFile;
use Muster::Hooks;

use Carp 'croak';
use YAML::Any;

=encoding utf8

=head1 NAME

Muster::Hook::Shortcut - Muster shortcut directive

=head1 DESCRIPTION

L<Muster::Hook::Shortcut> creates shortcuts.

=head1 METHODS

L<Muster::Hook::Shortcut> inherits all methods from L<Muster::Hook::Directives>.

=head2 register

Do some intialization.

=cut
sub register {
    my $self = shift;
    my $hookmaster = shift;
    my $config = shift;

    # The shortcuts are defined in the config
    # Each shortcut needs a callback to expand that particular shortcut
    # and that callback is passed to the do_directives method,
    # which in turn is called inside the callback added as a hook to the hookmaster.
    foreach my $sh (keys %{$config->{hook_conf}->{'Muster::Hook::Shortcut'}})
    {
        my $callback = sub {
            my $leaf = shift;
            my $scanning = shift;
            my @params = @_;

            return $self->shortcut_expand(
                $config->{hook_conf}->{'Muster::Hook::Shortcut'}->{$sh}->{url},
                $config->{hook_conf}->{'Muster::Hook::Shortcut'}->{$sh}->{desc},
                scanning=>$scanning,
                no_scan=>1,
                @params);
        };
        $hookmaster->add_hook($sh => sub {
                my $leaf = shift;
                my $scanning = shift;

                return $self->do_directives(
                    leaf=>$leaf,
                    scanning=>$scanning,
                    directive=>$sh,
                    call=>$callback);
            },
        );
    }
    return $self;
} # register

=head2 shortcut_expand

Expand the placeholders in the given shortcut.

=cut
sub shortcut_expand ($$@) {
    my $self = shift;
    my $url=shift;
    my $desc=shift;
    my %params=@_;

    # code from IkiWiki
    # Get params in original order.
    my @params;
    while (@_) {
        my $key=shift;
        my $value=shift;
        push @params, $key if ! length $value;
    }

    my $text=join(" ", @params);

    $url=~s{\%([sSW])}{
        if ($1 eq 's') {
            my $t=$text;
            $t=~s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
            $t;
        }
        elsif ($1 eq 'S') {
            $text;
        }
        elsif ($1 eq 'W') {
            my $t=Encode::encode_utf8($text);
            $t=~s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
            $t;
        }
    }eg;

    $text=~s/_/ /g;
    if (defined $params{desc}) {
        $desc=$params{desc};
    }
    if (defined $desc) {
        $desc=~s/\%s/$text/g;
    }
    else {
        $desc=$text;
    }

    return "<a href=\"$url\">$desc</a>";
}
1;
