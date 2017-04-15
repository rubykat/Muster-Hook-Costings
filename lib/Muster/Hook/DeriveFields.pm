package Muster::Hook::DeriveFields;

=head1 NAME

Muster::Hook::DeriveFields - Muster hook for field derivation

=head1 DESCRIPTION

L<Muster::Hook::DeriveFields> does field derivation;
that is, derives field values from other fields
(aka the meta-data for the Leaf).

This just does a bunch of specific calculations;
I haven't figured out a good way of defining derivations in a config file.

=cut

use Mojo::Base 'Muster::Hook';
use Muster::Hooks;
use Muster::LeafFile;
use DBI;
use Lingua::EN::Inflexion;
use YAML::Any;
use Carp;

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

    # and in the other databases as well!
    $self->{databases} = {};
    while (my ($alias, $file) = each %{$conf->{hook_conf}->{'Muster::Hook::SqlReport'}})
    {
        if (!-r $file)
        {
            warn __PACKAGE__, " cannot read database '$file'";
        }
        else
        {
            my $dbh = DBI->connect("dbi:SQLite:dbname=$file", "", "");
            if (!$dbh)
            {
                croak "Can't connect to $file $DBI::errstr";
            }
            $self->{databases}->{$alias} = $dbh;
        }
    }
    $self->{config} = $conf->{hook_conf}->{'Muster::Hook::DeriveFields'};

    $hookmaster->add_hook('derivefields' => sub {
            my %args = @_;

            return $self->process(%args);
        },
    );
    return $self;
} # register

=head2 process

Process (scan or modify) a leaf object.
This only does stuff in the scan phase.
This expects the leaf meta-data to be populated.

  my $new_leaf = $self->process(%args);

=cut
sub process {
    my $self = shift;
    my %args = @_;

    my $leaf = $args{leaf};
    my $phase = $args{phase};

    # only does derivations in scan phase
    if ($phase ne $Muster::Hooks::PHASE_SCAN)
    {
        return $leaf;
    }

    my $meta = $leaf->meta;

    # -----------------------------------------
    # Do derivations
    # -----------------------------------------

    # split the page-name on '-'
    # useful for project-types
    my @bits = split('-', $leaf->name);
    for (my $i=0; $i < scalar @bits; $i++)
    {
        my $p1 = sprintf('p%d', $i + 1); # page-bits start from 1 not 0
        $meta->{$p1} = $bits[$i];
    }

    # sections being the parts of the full page name
    @bits = split(/\//, $leaf->pagename);
    # remove the actual page-file from this list
    pop @bits;
    for (my $i=0; $i < scalar @bits; $i++)
    {
        my $section = sprintf('section%d', $i + 1); # sections start from 1 not 0
        $meta->{$section} = $bits[$i];
    }

    # the first Alpha of the name; good for headers in reports
    $meta->{name_a} = uc(substr($leaf->name, 0, 1));

    # plural and singular 
    # assuming that the page-name is a noun...
    my $noun = noun($leaf->name);
    if ($noun->is_plural())
    {
        $meta->{singular} = $noun->singular();
        $meta->{plural} = $leaf->name;
    }
    elsif ($noun->is_singular())
    {
        $meta->{singular} = $leaf->name;
        $meta->{plural} = $noun->plural();
    }
    else # neither
    {
        $meta->{singular} = $leaf->name;
        $meta->{plural} = $leaf->name;
    }

    # Classify the prose length for those pages that have wordcounts. Of course,
    # this assumes that all of the words are in one page, which for long
    # stories won't be the case. Hmmm.
    if ($meta->{wordcount})
    {
        my $len = '';
        if ($meta->{wordcount} == 100)
        {
            $len = 'Drabble';
        } elsif ($meta->{wordcount} == 200)
        {
            $len = 'Double-Drabble';
        } elsif ($meta->{wordcount} >= 75000)
        {
            $len = 'Long-Novel';
        } elsif ($meta->{wordcount} >= 50000)
        {
            $len = 'Novel';
        } elsif ($meta->{wordcount} >= 25000)
        {
            $len = 'Novella';
        } elsif ($meta->{wordcount} >= 7500)
        {
            $len = 'Novelette';
        } elsif ($meta->{wordcount} >= 2000)
        {
            $len = 'Short-Story';
        } elsif ($meta->{wordcount} > 500)
        {
            $len = 'Short-Short';
        } elsif ($meta->{wordcount} <= 500)
        {
            $len = 'Flash';
        }
        if ($meta->{tags})
        {
            if (ref $meta->{tags} eq 'ARRAY')
            {
                push @{$meta->{tags}}, $len;
            }
            else
            {
                $meta->{tags} .= "|$len";
            }
        }
        else
        {
            $meta->{tags} = $len;
        }
    }
    $leaf->{meta} = $meta;

    $leaf = $self->costings(%args);
    return $leaf;
} # process

sub costings {
    my $self = shift;
    my %args = @_;

    my $leaf = $args{leaf};
    my $phase = $args{phase};

    my $meta = $leaf->meta;

    # -----------------------------------------------------------
    # LABOUR TIME
    # If "construction" is given, use that to calculate the labour time
    # There may be more than one means of contruction; for example,
    # a resin pendant with a maille chain.
    # An explicit "labour_time" overrides this
    # -----------------------------------------------------------
    if (exists $meta->{construction}
            and defined $meta->{construction}
            and not exists $meta->{labour_time}
            and not defined $meta->{labour_time})
    {
        my $labour = 0;
        my $constr = $meta->{construction};
        if (!ref $meta->{construction} and $meta->{construction} =~ /^---/ms) # YAML
        {
            $constr = Load($meta->{construction});
        }
        foreach my $key (sort keys %{$constr})
        {
            my $item = $constr->{$key};
            my $item_mins = 0;
            if ($item->{uses} eq 'yarn')
            {
                # This is a yarn/stitch related method
                # Look in the yarn database

                my $cref = $self->_do_n_col_query('yarn',
                    "SELECT Minutes,StitchesWide,StitchesLong FROM metrics WHERE Method = '$item->{method}';");
                if ($cref and $cref->[0])
                {
                    my $row = $cref->[0];
                    my $minutes = $row->{Minutes};
                    my $wide = $row->{StitchesWide};
                    my $long = $row->{StitchesLong};

                    $item_mins = ((($item->{stitches_width} * $item->{stitches_length}) / ($wide * $long)) * $minutes);
                    # round them
                    $item_mins=sprintf ("%.0f",$item_mins+.5);
                }
            }
            elsif ($item->{uses} eq 'chainmaille')
            {
                # default time-per-ring is 30 seconds
                # but it can be overridden for something like, say, Titanium, or experimental weaves
                my $secs_per_ring = ($item->{secs_per_ring} ? $item->{secs_per_ring} : 30);
                $item_mins = ($secs_per_ring * $item->{rings}) / 60.0;
            }
            $labour += $item_mins;
        }
        $meta->{labour_time} = $labour if $labour;
    }

    # -----------------------------------------------------------
    # MATERIAL COSTS
    # -----------------------------------------------------------
    if (exists $meta->{materials} and defined $meta->{materials})
    {
        my $cost = 0;
        my $labour = 0;
        my $mat = $meta->{materials};
        if (!ref $meta->{materials} and $meta->{materials} =~ /^---/ms) # YAML
        {
            my $mat = Load($meta->{materials});
        }
        foreach my $key (sort keys %{$mat})
        {
            my $item = $mat->{$key};
            my $item_cost = 0;
            # for consistency all calculated item times will be in MINUTES
            my $item_mins = 0;
            if ($item->{cost})
            {
                $item_cost = $item->{cost};
            }
            elsif ($item->{type})
            {
                if ($item->{type} eq 'yarn')
                {
                    my $cref = $self->_do_one_col_query('yarn',
                        "SELECT BallCost FROM yarn WHERE SourceCode = '$item->{source}' AND Name = '$item->{name}';");
                    if ($cref and $cref->[0])
                    {
                        $item_cost = $cref->[0];
                    }
                }
                elsif ($item->{type} eq 'maille')
                {
                    # the cost-per-ring in the chainmaille db is in cents, not dollars
                    my $cref = $self->_do_one_col_query('chainmaille',
                        "SELECT CostPerRing FROM rings WHERE Code = '$item->{code}';");
                    if ($cref and $cref->[0])
                    {
                        $item_cost = ($cref->[0]/100.0);
                    }
                }
            }

            if ($item->{amount})
            {
                $item_cost = $item_cost * $item->{amount};
            }
            $cost += $item_cost;
            $labour += $item_mins;
        } # for each item
        $meta->{materials_cost} = $cost;
        $meta->{labour_time} = $labour if ($labour and !exists $meta->{labour_time});
    }
    # -----------------------------------------------------------
    # LABOUR COSTS
    # the labour_time will either be defined or derived
    # if no suffix is given, assume minutes
    # -----------------------------------------------------------
    if (exists $meta->{labour_time} and defined $meta->{labour_time})
    {
        my $hours;
        if ($meta->{labour_time} =~ /(\d+)h/i)
        {
            $hours = $1;
        }
        elsif ($meta->{labour_time} =~ /(\d+)d/i)
        {
            # assume an eight-hour day
            $hours = $1 * 8;
        }
        elsif ($meta->{labour_time} =~ /(\d+)s/i)
        {
            # seconds
            $hours = $1 / (60.0 * 60.0);
        }
        elsif ($meta->{labour_time} =~ /(\d+)/i)
        {
            # minutes
            $hours = $1 / 60.0;
        }
        if ($hours)
        {
            my $per_hour = (exists $meta->{cost_per_hour}
                ? $meta->{cost_per_hour}
                : (exists $self->{config}->{cost_per_hour}
                    ? $self->{config}->{cost_per_hour}
                    : 20));
            $meta->{labour_cost} = $hours * $per_hour;
        }
    }
    # -----------------------------------------------------------
    # TOTAL COSTS AND OVERHEADS
    # Calculate total costs from previously derived costs
    # Add in the overheads, then re-calculate the total;
    # this is because some overheads depend on a percentage of the total cost.
    # -----------------------------------------------------------
    if (exists $meta->{materials_cost} or exists $meta->{labour_cost})
    {
        my $wholesale = $meta->{materials_cost} + $meta->{labour_cost};
        my $overheads = $self->_calculate_overheads($wholesale);
        $meta->{estimated_overheads1} = $overheads;
        my $retail = $wholesale + $overheads;
        $overheads = $self->_calculate_overheads($retail);
        $meta->{estimated_overheads} = $overheads;
        $meta->{estimated_cost} = $retail;
        if ($meta->{actual_price})
        {
            $meta->{actual_overheads} = $self->_calculate_overheads($meta->{actual_price});
        }
    }
    if (exists $meta->{postage} and defined $meta->{postage})
    {
        # I'm going to have to double-check this
        if ($meta->{postage} eq 'small') # large letter
        {
            $meta->{postage_au} = 6;
        }
        else # parcel
        {
            $meta->{postage_au} = 14;
        }
        $meta->{postage_us} = 24;
        $meta->{postage_nz} = 20;
        $meta->{postage_uk} = 29;
    }

    $leaf->{meta} = $meta;
    return $leaf;
} # costings

=head2 _calculate_overheads

Calculate overheads like listing fees and COMMISSION (which depends on the total, backwards)

=cut
sub _calculate_overheads {
    my $self = shift;
    my $retail = shift;

    # Etsy fees are 20c US per listing, plus 3.5% commission
    # Etsy Direct Checkout fees are 25c per item, plus 4% of item cost
    # Paypal ... is a bit confusing. 3.5% plus 30c per transaction?
    my $overheads = 0.26 + ($retail * 0.035)
    + 0.30 + ($retail * 0.04)
    + 0.35 + ($retail * 0.035);

    return $overheads;
} # _calculate_overheads

=head2 _do_one_col_query

Do a SELECT query, and return the first column of results.
This is a freeform query, so the caller must be careful to formulate it correctly.

my $results = $self->_do_one_col_query($dbname,$query);

=cut

sub _do_one_col_query {
    my $self = shift;
    my $dbname = shift;
    my $q = shift;

    if ($q !~ /^SELECT /)
    {
        # bad boy! Not a SELECT.
        return undef;
    }
    my $dbh = $self->{databases}->{$dbname};
    return undef if !$dbh;

    my $sth = $dbh->prepare($q);
    if (!$sth)
    {
        croak "FAILED to prepare '$q' $DBI::errstr";
    }
    my $ret = $sth->execute();
    if (!$ret)
    {
        croak "FAILED to execute '$q' $DBI::errstr";
    }
    my @results = ();
    my @row;
    while (@row = $sth->fetchrow_array)
    {
        push @results, $row[0];
    }
    return \@results;
} # _do_one_col_query

=head2 _do_n_col_query

Do a SELECT query, and return all the results.
This is a freeform query, so the caller must be careful to formulate it correctly.

my $results = $self->_do_n_col_query($dbname,$query);

=cut

sub _do_n_col_query {
    my $self = shift;
    my $dbname = shift;
    my $q = shift;

    if ($q !~ /^SELECT /)
    {
        # bad boy! Not a SELECT.
        return undef;
    }
    my $dbh = $self->{databases}->{$dbname};
    return undef if !$dbh;

    my $sth = $dbh->prepare($q);
    if (!$sth)
    {
        croak "FAILED to prepare '$q' $DBI::errstr";
    }
    my $ret = $sth->execute();
    if (!$ret)
    {
        croak "FAILED to execute '$q' $DBI::errstr";
    }
    my @results = ();
    my $row;
    while ($row = $sth->fetchrow_hashref)
    {
        push @results, $row;
    }
    return \@results;
} # _do_n_col_query

1;
