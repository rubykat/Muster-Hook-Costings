package Muster::Hook::DynamicField;

=head1 NAME

Muster::Hook::DynamicField - Muster hook for dynamic fields

=head1 SYNOPSIS

  # CamelCase plugin name
  package Muster::Hook::DynamicField;
  use Mojo::Base 'Muster::Hook';

=head1 DESCRIPTION

L<Muster::Hook::DynamicField> does dynamic fields:
field-substitution for derived values which are not always constant, such as the current date.

The pattern for dynamic fields is "{{!I<fieldname>}}".

=cut

use Mojo::Base 'Muster::Hook';
use Muster::Hooks;
use Muster::LeafFile;
use YAML::Any;
use POSIX qw(strftime);

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

    $hookmaster->add_hook('dynamicfield' => sub {
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

    if (!$leaf->is_page)
    {
        return $leaf;
    }
    if ($phase ne $Muster::Hooks::PHASE_BUILD)
    {
        return $leaf;
    }

    my $content = $leaf->cooked();
    my $page = $leaf->pagename;

    # substitute {{!var}} variables (source-page)
    $content =~ s/(\\?)\{\{\!([-\w]+)\}\}/$self->get_dynamic_value($1,$2,$leaf)/eg;

    $leaf->{cooked} = $content;
    return $leaf;
} # process

=head2 get_dynamic_value

Get the dynamic value for this page.

=cut
sub get_dynamic_value {
    my $self = shift;
    my $escape = shift;
    my $field = shift;
    my $leaf = shift;

    if (length $escape)
    {
	return "{{\$${field}}}";
    }

    # force all fields to lower-case
    $field = lc($field);

    my $value = '';

    if ($field eq 'now')
    {
        $value = strftime '%H:%M:%S', localtime;
    }
    elsif ($field eq 'today')
    {
        $value = strftime '%Y-%m-%d', localtime;
    }
    elsif ($field eq 'thisyear')
    {
        $value = strftime '%Y', localtime;
    }
    elsif ($field eq 'firstimage')
    {
        # find the first image file attached to this page
        my $page = $leaf->pagename;
        my $ret = $self->{metadb}->query("SELECT page FROM flatfields WHERE parent_page = '$page' AND (extension = 'jpg' OR extension = 'png' OR extension = 'gif') ORDER BY page LIMIT 1");
        $value = (scalar @{$ret} ? $ret->[0] : '');
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
} # get_dynamic_value


1;
