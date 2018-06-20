package Muster::Hook::Costings;

=head1 NAME

Muster::Hook::Costings - Muster hook for costings derivation

=head1 DESCRIPTION

L<Muster::Hook::Costings> does costings derivation;
that is, derives costs of things from the page meta-data
plus looking up information in various databases.

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
    $self->{config} = $conf->{hook_conf}->{'Muster::Hook::Costings'};

    $hookmaster->add_hook('costings' => sub {
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

    # -----------------------------------------------------------
    # All these costings are only relevant for craft inventory pages
    # or for craft component pages, so skip everything else
    # -----------------------------------------------------------
    if ($leaf->pagename !~ /(inventory|components)/)
    {
        return $leaf;
    }

    # -----------------------------------------------------------
    # LABOUR TIME
    # If "construction" is given, use that to calculate the labour time
    # There may be more than one means of contruction; for example,
    # a resin pendant with a maille chain.
    # An explicit top-level "labour_time" overrides this
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
            if (defined $item->{from} and $item->{from} eq 'yarn')
            {
                # This is a yarn/stitch related method

                # Calculate stitches_length if need be
                if (!$item->{stitches_length}
                        and defined $item->{length}
                        and defined $item->{stitches_per})
                {
                    $item->{stitches_length} = ($item->{stitches_per}->{stitches} / $item->{stitches_per}->{length}) * $item->{length};
                }

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
            elsif (defined $item->{from} and $item->{from} eq 'chainmaille')
            {
                # default time-per-ring is 30 seconds
                # but it can be overridden for something like, say, Titanium, or experimental weaves
                my $secs_per_ring = ($item->{secs_per_ring} ? $item->{secs_per_ring} : 30);
                $item_mins = ($secs_per_ring * $item->{rings}) / 60.0;
            }
            elsif (defined $item->{from} and $item->{from} =~ /resin/i)
            {
                # Resin time depends on the number of layers
                # but the number of minutes per layer may be overridden; by default 15 mins
                # This of course does not include curing time.
                my $mins_per_layer = ($item->{mins_per_layer} ? $item->{mins_per_layer} : 15);
                $item_mins = $mins_per_layer * $item->{layers};
            }
            elsif ($item->{minutes})
            {
                # generic task override, just say how many minutes it took
                $item_mins = $item->{minutes};

                # This may be multiplied by an "amount", because this could be
                # talking about repeated actions. For example, wire-wrapping the
                # ends of six cords, the amount would be six.
                $item_mins = $item_mins * $item->{amount} if $item->{amount};
            }
            $meta->{construction}->{$key}->{minutes} = $item_mins;
            $labour += $item_mins;
        }
        $meta->{labour_time} = $labour if $labour;
    }

    # -----------------------------------------------------------
    # MATERIAL COSTS
    # -----------------------------------------------------------
    if (exists $meta->{materials} and defined $meta->{materials})
    {
        my %materials_hash = ();
        my $cost = 0;
        my $mat = $meta->{materials};
        if (!ref $meta->{materials} and $meta->{materials} =~ /^---/ms) # YAML
        {
            my $mat = Load($meta->{materials});
        }
        foreach my $key (sort keys %{$mat})
        {
            my $item = $mat->{$key};
            my $item_cost = 0;
            if ($item->{cost})
            {
                $item_cost = $item->{cost};
            }
            elsif ($item->{from})
            {
                if ($item->{from} eq 'yarn')
                {
                    my $cref = $self->_do_n_col_query('yarn',
                        "SELECT BallCost,Materials FROM yarn WHERE SourceCode = '$item->{source}' AND Name = '$item->{id}';");
                    if ($cref and $cref->[0])
                    {
                        my $row = $cref->[0];
                        $item_cost = $row->{BallCost};
                        my @mar = split(/[|]/, $row->{Materials});
                        foreach my $mm (@mar)
                        {
                            $mm =~ s/Viscose/Artificial Silk/;
                            $mm =~ s/Rayon/Artificial Silk/;
                            $materials_hash{$mm}++;
                        }
                    }
                }
                elsif ($item->{from} eq 'maille')
                {
                    # the cost-per-ring in the chainmaille db is in cents, not dollars
                    my $cref = $self->_do_n_col_query('chainmaille',
                        "SELECT CostPerRing,Metal FROM ringsinfo WHERE Code = '$item->{id}';");
                    if ($cref and $cref->[0])
                    {
                        my $row = $cref->[0];
                        $item_cost = ($row->{CostPerRing}/100.0);
                        $materials_hash{$row->{Metal}}++;
                    }
                }
                elsif ($item->{from} eq 'supplies')
                {
                    my $cref = $self->_do_n_col_query('supplies',
                        "SELECT cost,materials,title,tags FROM supplies_info WHERE Name = '$item->{id}';");
                    if ($cref and $cref->[0])
                    {
                        my $row = $cref->[0];
                        $item_cost = $row->{cost};
                        $materials_hash{$row->{materials}}++;
                    }
                }
                elsif ($item->{from} eq 'made_parts'
                        or $item->{from} eq 'prints')
                {
                    my $from = $item->{from};
                    # The component information is from this current wiki
                    # Note we need the labour time and the materials cost, BOTH
                    # We don't use the wholesale_cost for this, because we need
                    # to record the *materials* cost for every piece of inventory.
                    # And because we need to use a consistent labour cost.
                    my $cref = $self->_do_n_col_query('muster',
                        "SELECT labour_time,materials_list,materials_cost FROM flatfields WHERE parent_page = 'craft/components/${from}' AND name = '$item->{id}';");
                    if ($cref and $cref->[0])
                    {
                        my $row = $cref->[0];
                        if ($row->{labour_time})
                        {
                            my $lt = $row->{labour_time};
                            # We have to divide the labour time by the "amount"
                            # of the item, because half an item takes half the time.
                            if ($item->{amount})
                            {
                                $lt = $lt * $item->{amount};
                            }
                            
                            $meta->{labour_time} += $lt;
                            $meta->{materials}->{$key}->{labour} = $lt;
                        }
                        $item_cost = $row->{materials_cost};
                        if ($item->{from} eq 'made_parts'
                                and defined $row->{materials_list})
                        {
                            my @mats = split(/, /, $row->{materials_list});
                            foreach my $m (@mats)
                            {
                                $materials_hash{$m}++;
                            }
                        }
                        elsif ($item->{from} eq 'prints')
                        {
                            $materials_hash{'paper'}++;
                        }
                    }
                }
            }
            if ($item->{materials})
            {
                $materials_hash{$item->{materials}}++;
            }

            if ($item->{amount})
            {
                $item_cost = $item_cost * $item->{amount};
            }
            $meta->{materials}->{$key}->{cost} = $item_cost;
            $cost += $item_cost;
        } # for each item
        $meta->{materials_cost} = $cost;
        $meta->{materials_list} = join(', ', sort keys %materials_hash);
    }
    # -----------------------------------------------------------
    # LABOUR COSTS
    # the labour_time will either be defined or derived
    # if no suffix is given, assume minutes
    # -----------------------------------------------------------
    my $per_hour = (exists $meta->{cost_per_hour}
        ? $meta->{cost_per_hour}
        : (exists $self->{config}->{cost_per_hour}
            ? $self->{config}->{cost_per_hour}
            : 20));
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
            $meta->{used_cost_per_hour} = $per_hour;
            $meta->{labour_cost} = $hours * $per_hour;
        }
        
        # This is a metric to compare to wholesale cost
        # when the materials cost is higher than the labour cost.
        if (defined $meta->{materials_cost}
                and defined $meta->{labour_cost}
                and $meta->{materials_cost} > $meta->{labour_cost})
        {
            $meta->{twice_materials} = $meta->{materials_cost} * 2;
        }
    }
    # POSTAGE - Inventory only
    if ($leaf->pagename =~ /inventory/
            and exists $meta->{postage}
            and defined $meta->{postage})
    {
        # Note that some of my jewellery is too thick to be able to be sent as
        # a Large Letter, while the really flat pieces do fit into the Large
        # Letter category.

        # The postage information is from this current wiki,
        # to make it easier to add new postage profiles.

        my $cref = $self->_do_n_col_query('muster',
            "SELECT packaging,postage_au,postage_nz,postage_us,postage_uk FROM flatfields WHERE parent_page = 'craft/components/postage' AND name = '$meta->{postage}';");
        if ($cref and $cref->[0])
        {
            my $row = $cref->[0];
            if ($row->{packaging})
            {
                foreach my $pkg (qw(postage_au postage_nz postage_us postage_uk))
                {
                    $meta->{$pkg} = $row->{$pkg} + $row->{packaging};
                }
                # If we have free domestic postage, adjust the
                # prices accordingly, the domestic postage cost
                # will be added to the item cost, and removed
                # from the postage costs
                if ($meta->{free_postage})
                {
                    $meta->{free_postage_cost} = $meta->{postage_au};
                    foreach my $pkg (qw(postage_au postage_nz postage_us postage_uk))
                    {
                        $meta->{$pkg} -= $meta->{free_postage_cost};
                    }
                }
                else
                {
                    $meta->{free_postage_cost} = 0;
                }
                # And Etsy are now charging 5% on shipping costs as well!
                foreach my $pkg (qw(postage_au postage_nz postage_us postage_uk))
                {
                    $meta->{$pkg} += ($meta->{$pkg} * 0.05);
                }
            }
        }
    }

    # -----------------------------------------------------------
    # ITEMIZE TIME and ITEMIZE COSTS
    # Inventory:
    # Every item listed in my inventory and listed on Etsy
    # takes a certain amount of labour:
    # * photographing
    # * naming and tagging the photos
    # * adding the item to the inventory
    # * adding the item to Etsy
    # This is in common for all items, no matter what their labour is,
    # so I'm doing this as a separate cost.
    # -----------------------------------------------------------
    my $itemize_mins = 0;
    if ($leaf->pagename =~ /inventory/)
    {
        $itemize_mins = (exists $meta->{itemize_time}
            ? $meta->{itemize_time}
            : (exists $self->{config}->{itemize_time}
                ? $self->{config}->{itemize_time}
                : 20));
    }
    if ($itemize_mins)
    {
        $meta->{itemize_time} = $itemize_mins;
        my $hours = $itemize_mins / 60.0;
        $meta->{used_cost_per_hour} = $per_hour;
        $meta->{itemize_cost} = $hours * $per_hour;
    }

    # -----------------------------------------------------------
    # INVENTORY TOTAL COSTS AND OVERHEADS
    # Calculate total costs from previously derived costs
    # Add in the overheads, then re-calculate the total;
    # this is because some overheads depend on a percentage of the total cost.
    # -----------------------------------------------------------
    my $retail_multiplier = (exists $meta->{retail_multiplier}
        ? $meta->{retail_multiplier}
        : (exists $self->{config}->{retail_multiplier}
            ? $self->{config}->{retail_multiplier}
            : 2));
    if ($leaf->pagename =~ /inventory/)
    {
        if (exists $meta->{materials_cost} or exists $meta->{labour_cost})
        {
            my $cost_without_oh = $meta->{materials_cost}
            + $meta->{labour_cost}
            + $meta->{itemize_cost}
            + $meta->{free_postage_cost};
            my $overheads = calculate_overheads($cost_without_oh);
            $meta->{estimated_overheads1} = $overheads;
            my $wholesale = $cost_without_oh + $overheads;
            $overheads = calculate_overheads($wholesale);
            $meta->{estimated_overheads} = $overheads;
            $meta->{wholesale_cost} = $wholesale;
            $meta->{retail_cost} = $wholesale * $retail_multiplier;
            if ($meta->{actual_price})
            {
                $meta->{actual_overheads} = calculate_overheads($meta->{actual_price});
                $meta->{actual_return} = $meta->{actual_price} - $meta->{actual_overheads};
            }
        }
    }
    else # components
    {
        # COMPONENTS TOTAL COSTS
        # Components don't have overheads.
        # Nor an itemize_cost; don't want to count the itemize_cost twice;
        # all that components do is enable me to save time later.
        if (exists $meta->{materials_cost} or exists $meta->{labour_cost})
        {
            my $wholesale = $meta->{materials_cost} + $meta->{labour_cost};
            $meta->{wholesale_cost} = $wholesale;
        }
    }


    $leaf->{meta} = $meta;
    return $leaf;
} # process

=head2 calculate_overheads

Calculate overheads like listing fees and COMMISSION (which depends on the total, backwards)

=cut
sub calculate_overheads {
    my $bare_cost = shift;

    my $overheads = ((0.2 / 0.7) # US 20c per listing per four months
        * 5) # most things are not selling, need to relist more frequently to improve search rank
    # "Etsy Payments" fees are 25c AU per item, plus 4% of item cost
    +  0.25 + ($bare_cost * 0.04)
    # Etsy transaction fees are now: 5% commission -- and that is on shipping too!
    + ($bare_cost * 0.05);

    # Add another $2 for Promoted Listings (at a budget of US$1 per day)
    # (see the money-etsy page for the calculations)
    $overheads += 2;
    
    # And now Etsy are charging GST on their fees
    $overheads += $overheads * 0.1;

    # I'm not including Paypal here -- that's for if I'm not selling through Etsy.
    # (Paypal fees: 3.5% plus 30c per transaction?)
    # GST is not included because I don't have to pay GST because I'm not making $75,000

    return $overheads;
} # calculate_overheads

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
