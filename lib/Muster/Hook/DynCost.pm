package Muster::Hook::DynCost;

=head1 NAME

Muster::Hook::DynCost - Muster hook for dynamic fields

=head1 SYNOPSIS

  # CamelCase plugin name
  package Muster::Hook::DynCost;
  use Mojo::Base 'Muster::Hook';

=head1 DESCRIPTION

L<Muster::Hook::DynCost> does dynamic fields:
field-substitution for derived values which are not always constant, such as the current date.

The pattern for dynamic fields is "{{!I<fieldname>}}".

=cut

use Mojo::Base 'Muster::Hook';
use Muster::Hooks;
use Muster::LeafFile;
use YAML::Any;
use POSIX qw(strftime);
use Math::Calc::Parser;
use Muster::Hook::Costings;

=head1 METHODS

=head2 register

Initialize, and register hooks.

=cut
sub register {
    my $self = shift;
    my $hookmaster = shift;
    my $conf = shift;

    # we need to be able to look things up in the database
    $self->{metadb} = $hookmaster->{metadb};

    $hookmaster->add_hook('dyncost' => sub {
            my %args = @_;

            return $self->process(%args);
        },
    );
    return $self;
} # register

=head2 process

Process (modify) a leaf object.
In scanning phase, this will do nothing, because it's pointless.
In assembly phase, it will do simple substitutions of calculated data (which may or may not be derived from the leaf data).

  my $new_leaf = $self->process(%args);

=cut
sub process {
    my $self = shift;
    my %args = @_;

    my $leaf = $args{leaf};
    my $phase = $args{phase};

    if ($leaf->is_binary)
    {
        return $leaf;
    }
    if ($phase ne $Muster::Hooks::PHASE_BUILD)
    {
        return $leaf;
    }

    my $content = $leaf->cooked();
    my $page = $leaf->pagename;

    # substitute dyncost(...) 
    $content =~ s/(\\?)(dyncost)\(([^)]+)\)/$self->get_function_result($1,$2,$3,$leaf)/eg;

    $leaf->{cooked} = $content;
    return $leaf;
} # process

=head2 get_function_result

Process the given function for this page.

=cut
sub get_function_result {
    my $self = shift;
    my $escape = shift;
    my $func = shift;
    my $argvals = shift;
    my $leaf = shift;

    if (length $escape)
    {
	return "{{\!${func}(${argvals})}}";
    }
    # This function is broken
    return "BROKEN {{\!${func}(${argvals})}}";

    my $value;

    if ($func eq 'dyncost')
    {
        # dyncost(per_hour)
        if ($leaf->{meta}->{labour_time}
                or $leaf->{meta}->{materials_cost})
        {
            my $cost_per_hour = 1;
            my $retail_multiplier = 1;
            if ($argvals =~ /,/)
            {
                my @av = split(/,/,$argvals);
                $cost_per_hour = $av[0];
                $retail_multiplier = $av[1];
            }
            else
            {
                $cost_per_hour = $argvals;
                $retail_multiplier = (exists $leaf->{meta}->{retail_multiplier}
                    ? $leaf->{meta}->{retail_multiplier}
                    : (exists $self->{config}->{retail_multiplier}
                        ? $self->{config}->{retail_multiplier}
                        : 2));
            }
            my $labour_cost = ($leaf->{meta}->{labour_time} / 60) * $cost_per_hour;
            my $cost_without_oh = $leaf->{meta}->{materials_cost} + $labour_cost;
            my $fh = Muster::Hook::Costings::calculate_fees($cost_without_oh);
            my $overheads = $fh->{total};
            my $wholesale = $cost_without_oh + $overheads;
            my $retail = $wholesale * $retail_multiplier;
            $value = "dyncost($argvals) = ($cost_without_oh + $overheads = $wholesale) * $retail_multiplier = $retail";
        }
    }

    if (!defined $value)
    {
        return '';
    }
    if (ref $value eq 'ARRAY')
    {
        $value = join(' ', @{$value});
    }
    elsif (ref $value eq 'HASH')
    {
        $value = Dump($value);
    }
    return $value;
} # get_function_result


1;
