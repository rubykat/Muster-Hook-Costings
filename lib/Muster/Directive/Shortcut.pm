package Muster::Directive::Shortcut;
use Mojo::Base -base;
use Muster::LeafFile;

use Carp 'croak';

=encoding utf8

=head1 NAME

Muster::Directive::Shortcut - Muster shortcut directive

=head1 DESCRIPTION

L<Muster::Directive::Shortcut> creates shortcuts.

=head1 METHODS

L<Muster::Directive::Shortcut> inherits all methods from L<Muster::Directive>.

=head2 id

The id of the directive. Used as the command-name.

=cut

sub id {
    my $class = shift;
    return 'shortcut';
}

=head2 register_directive

Do some intialization.

=cut
sub register_directive {
    my $self = shift;
    my $dirmod = shift;
    my $conf = shift;

    # the shortcuts are defined in the config
    foreach my $sh (keys %{$conf})
    {
        $dirmod->add_directive($sh => sub {
                my $leaf = shift;
                my $scan = shift;
                my @params = @_;

                return $self->shortcut_expand(
                    $conf->{$sh}->{url},
                    $conf->{$sh}->{desc},
                    scanning=>$scan,
                    @params);
            },
        );
    }
    return $self;
} # register_directive

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
