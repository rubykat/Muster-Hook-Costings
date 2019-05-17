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
            if (defined $item->{from}
                    and ($item->{from} eq 'metrics' or $item->{from} eq 'yarn'))
            {
                # Calculate stitches_length if need be
                if (!$item->{stitches_length}
                        and defined $item->{length}
                        and defined $item->{stitches_per})
                {
                    $item->{stitches_length} = ($item->{stitches_per}->{stitches} / $item->{stitches_per}->{length}) * $item->{length};
                }

                # Look in the reference database for metrics
                my $cref = $self->_do_n_col_query('reference',
                    "SELECT minutes,width,length FROM flatfields WHERE page GLOB 'Craft/metrics/*' AND (title = '$item->{method}' OR name = '$item->{method}');");
                if ($cref and $cref->[0])
                {
                    my $row = $cref->[0];
                    my $minutes = $row->{minutes};
                    my $wide = $row->{width};
                    my $long = $row->{length};

                    if ($wide and $long and $item->{stitches_width} and $item->{stitches_length})
                    {
                        $item_mins = ((($item->{stitches_width} * $item->{stitches_length}) / ($wide * $long)) * $minutes);
                    }
                    elsif ($item->{count}) # There is a single multiplier
                    {
                        $item_mins = $item->{count} * $minutes;
                    }
                    elsif ($item->{amount}) # There is a single multiplier
                    {
                        $item_mins = $item->{amount} * $minutes;
                    }
                    else # there is no multiplier, it is a set time
                    {
                        $item_mins = $minutes;
                    }
                    # round them - don't add 0.5, that is a fallacy, sprintf will round without that
                    $item_mins=sprintf ("%.0f",$item_mins);
                }
                else
                {
                    warn "construction from metrics, failed to find '$item->{method}'";
                }
            }
            elsif (defined $item->{from} and $item->{from} eq 'chainmaille')
            {
                # default time-per-ring is 30 seconds
                # but it can be overridden for something like, say, Titanium, or experimental weaves
                my $secs_per_ring = ($item->{secs_per_ring} ? $item->{secs_per_ring} : 30);
                $item_mins = ($secs_per_ring * $item->{rings}) / 60.0;
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
            else
            {
                warn "unknown construction method $item->{from}";
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
                    my $cref = $self->_do_n_col_query('yarns',
                        "SELECT cost,materials FROM yarn WHERE source = '$item->{source}' AND label = '$item->{id}';");
                    if ($cref and $cref->[0])
                    {
                        my $row = $cref->[0];
                        $item_cost = $row->{cost};
                        my @mar = split(/[|]/, $row->{materials});
                        foreach my $mm (@mar)
                        {
                            $mm =~ s/Viscose/Artificial Silk/;
                            $mm =~ s/Rayon/Artificial Silk/;
                            $materials_hash{$mm}++;
                        }
                    }
                }
                elsif ($item->{from} eq 'yarns') # new yarn database
                {
                    my $cref = $self->_do_n_col_query('yarns',
                        "SELECT cost,materials FROM yarn WHERE id_name = '$item->{id}';");
                    if ($cref and $cref->[0])
                    {
                        my $row = $cref->[0];
                        $item_cost = $row->{cost};
                        my @mar = split(/[|]/, $row->{materials});
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
                        "SELECT cost,materials FROM supplies_info WHERE id_name = '$item->{id}';");
                    if ($cref and $cref->[0])
                    {
                        my $row = $cref->[0];
                        $item_cost = $row->{cost};
                        my @mar = split(/[|]/, $row->{materials});
                        foreach my $mm (@mar)
                        {
                            $materials_hash{$mm}++;
                        }
                    }
                }
                elsif ($item->{from} eq 'made_parts'
                        or $item->{from} eq 'prints')
                {
                    my $from = $item->{from};

                    # The component information is from the reference wiki.
                    # Note that we are looking for a page which starts with
                    # Craft/components/<section> but it can be anywhere
                    # underneath; this is because we might be using "seconds"
                    # or need to put the one-off components into the "used_up"
                    # section to indicate that they are no longer available
                    # (since they got used by some given item of inventory --
                    # this one!)
                    
                    # Note we need the labour time and the materials cost, BOTH
                    # We don't use the wholesale_cost for this, because we need
                    # to record the *materials* cost for every piece of inventory.
                    # And because we need to use a consistent labour cost.
                    my $cref = $self->_do_n_col_query('reference',
                        "SELECT labour_time,materials_list,materials_cost FROM flatfields WHERE page GLOB 'Craft/components/${from}/*' AND name = '$item->{id}';");
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
        
    }
    # POSTAGE - Inventory only
    my $max_postage_cost = 0;
    if ($leaf->pagename =~ /inventory/
            and exists $meta->{postage}
            and defined $meta->{postage})
    {
        # Note that some of my jewellery is too thick to be able to be sent as
        # a Large Letter, while the really flat pieces do fit into the Large
        # Letter category.
        # Also note that there is a tendency for international items to be
        # sent as a Small Parcel even though they are small enough to be a Large Letter.

        # The postage information is from the reference wiki,
        # to make it easier to add new postage profiles.

        my $cref = $self->_do_n_col_query('reference',
            "SELECT packaging,postage,postage_offset FROM flatfields WHERE parent_page = 'Craft/components/postage' AND name = '$meta->{postage}';");
        if ($cref and $cref->[0])
        {
            my $row = $cref->[0];
            if ($row->{packaging})
            {
                my $post = Load($row->{postage});
                # Need to add the packaging onto the materials cost of the item
                # because it is the same no matter what the destination is
                # and it is 'materials' used in the item-making
                # and thus needs to be counted for book-keeping.
                $meta->{materials}->{packaging}->{cost} = $row->{packaging};
                $meta->{materials_cost} += $row->{packaging};
                
                $meta->{postage_cost} = {};
                foreach my $country (keys %{$post})
                {
                    $meta->{postage_cost}->{$country}->{cost} = $post->{$country}->{cost};
                    # we need to remember the actual price which the post office charges
                    $meta->{postage_cost}->{$country}->{actual} = $post->{$country}->{cost};
                }
                # Postage-offset is a percentage of the domestic postage
                # cost to offset; that is, adjust the prices to add that
                # amount to the item cost and remove that amount from the
                # postage charge. If the postage-offset is 100%, then that
                # gives free domestic postage.
                if ($row->{postage_offset})
                {
                    $meta->{postage_offset} = $row->{postage_offset};
                    $meta->{postage_offset_cost} =
                    ($meta->{postage_cost}->{au}->{cost}
                        * ($row->{postage_offset}/100));
                    foreach my $country (keys %{$post})
                    {
                        $meta->{postage_cost}->{$country}->{cost} -=
                            $meta->{postage_offset_cost};
                    }
                }
                else
                {
                    $meta->{postage_offset_cost} = 0;
                }
                # Per-additional is a percentage of the country's postage cost which
                # is added to postage for each additional item bought.
                # Normally it is 100%, but one can offer discounts because
                # one can combine postage.
                # Now doing this on a per-country basis, because domestic may differ from international.
                foreach my $country (keys %{$post})
                {
                    if (defined $post->{$country}->{per_additional} && $post->{$country}->{per_additional} == 0)
                    {
                        $meta->{postage_cost}->{$country}->{per_additional} = 0;
                    }
                    elsif (defined $post->{$country}->{per_additional} && $post->{$country}->{per_additional} > 0)
                    {
                        $meta->{postage_cost}->{$country}->{per_additional} = 
                            $meta->{postage_cost}->{$country}->{cost} * ($post->{$country}->{per_additional}/100);
                    }
                    else
                    {
                        $meta->{postage_cost}->{$country}->{per_additional} = 
                            $meta->{postage_cost}->{$country}->{cost};
                    }
                }
                # If there is free postage, than the AU postage has zero per_additional
                if (defined $row->{postage_offset} && $row->{postage_offset} == 100) # free postage
                {
                    $meta->{postage_cost}->{au}->{per_additional} = 0;
                }
                
                # And Etsy are now charging 5% on shipping costs as well!
                # Fold these fees into the general fees, by taking the max
                foreach my $country (keys %{$post})
                {
                    my $f = ($post->{$country}->{cost} * 0.05);
                    if ($post->{$country}->{cost} > $max_postage_cost)
                    {
                        $max_postage_cost = $post->{$country}->{cost};
                    }
                    $meta->{postage_cost}->{$country}->{fees} = $f;
                }
            }
        }
    }

    # -----------------------------------------------------------
    # Market prices
    # Trying this to get a better idea of how to tweak prices
    # The class of item is the first part of the name if there isn't
    # a specific item_class given.
    # mkt_prices[0] - bargain-bottom
    # mkt_prices[1] - bargain-top and midrange-bottom
    # mkt_prices[2] - midrange-top and premium-bottom
    # mkt_prices[3] - premium-top
    # -----------------------------------------------------------
    my $item_class = ($meta->{item_class} ? $meta->{item_class} : $meta->{p1});
    $meta->{item_class} = $item_class;
    my @mkt_prices = ();
    if ($item_class)
    {
        my $cref = $self->_do_n_col_query('reference',
            "SELECT prices FROM flatfields WHERE page GLOB 'Craft/market/*' AND name = '$item_class';");
        if ($cref and $cref->[0])
        {
            my $row = $cref->[0];
            @mkt_prices = split(/[|]/, $row->{prices});
        }
    }

    # -----------------------------------------------------------
    # INVENTORY TOTAL COSTS AND FEES
    # Calculate total costs from previously derived costs
    # Add in the fees, then re-calculate the total;
    # this is because some fees depend on a percentage of the total cost.
    # -----------------------------------------------------------
    if ($leaf->pagename =~ /inventory/)
    {
        if (exists $meta->{materials_cost} or exists $meta->{labour_cost})
        {
            # --------------------------------------------------------
            # FORMULA:
            # wholesale = (materials + labour) * wholesale-markup
            # retail = (wholesale * markup) + postage-offset-cost
            # (the fees come out of the markup)
            # cost_price = materials + fees
            # --------------------------------------------------------
            my $wholesale_markup = ($meta->{wholesale_markup} ? $meta->{wholesale_markup} : 1.2);
            my $wholesale = ($meta->{materials_cost} + $meta->{labour_cost}) * $wholesale_markup;
            my $retail_markup = ($meta->{retail_markup} ? $meta->{retail_markup} : 2);
            my $retail = ($wholesale * $retail_markup)
            + ($meta->{postage_offset_cost} ? $meta->{postage_offset_cost} : 0);
            $meta->{wholesale_price} = $wholesale;
            $meta->{est_retail_price} = $retail;
            my $fees_hash = calculate_fees($retail,$max_postage_cost);
            my $fees = $fees_hash->{total};
            $meta->{est_fees_breakdown} = $fees_hash;
            $meta->{estimated_fees} = $fees;
            my $cost_price = $meta->{materials_cost} + $fees;
            $meta->{cost_price} = $cost_price;

            # --------------------------------------------------------
            # Market price
            # Figure out what price-class the calculated retail price falls into
            # --------------------------------------------------------
            if (@mkt_prices)
            {
                $meta->{price_class} = _market_class(\@mkt_prices,
                    $meta->{est_retail_price});
            }

            # -----------------------------------------------------------
            # This is the actual price set by the human being
            if ($meta->{actual_price})
            {
                my $fh = calculate_fees($meta->{actual_price},
                    ($meta->{sold_postage} ? $meta->{sold_postage}
                        : $max_postage_cost));
                $meta->{actual_fees} = $fh->{total};
                $meta->{fees_breakdown} = $fh; # this replaces estimated fees
                $meta->{actual_cost_price} = $meta->{materials_cost} + $meta->{actual_fees};
                if (@mkt_prices)
                {
                    $meta->{actual_price_class} = _market_class(\@mkt_prices,
                        $meta->{actual_price});
                }
                if ($meta->{on_sale}) # percentage off actual price
                {
                    $meta->{sale_price} = $meta->{actual_price} - ($meta->{actual_price} * ($meta->{on_sale} / 100));
                    my $fh2 = calculate_fees($meta->{sale_price}, $max_postage_cost);
                    $meta->{sale_fees} = $fh2->{total};
                    $meta->{sale_return} = $meta->{sale_price} - ($meta->{sale_fees} + $meta->{materials_cost});
                }
                if ($leaf->pagename =~ /sold/)
                {
                    $meta->{gross_price} = ($meta->{sale_price} ? $meta->{sale_price} : $meta->{actual_price})
                    + ($meta->{sold_postage} ? $meta->{sold_postage} : 0);
                    $meta->{actual_return} = $meta->{gross_price} -
                    (
                        $meta->{materials_cost}
                        + ($meta->{on_sale} ? $meta->{sale_fees} : $meta->{actual_fees})
                        + ($meta->{actual_postage} ? $meta->{actual_postage} : $meta->{sold_postage})
                    );
                }
            }
        }
    }
    else # components
    {
        # COMPONENTS TOTAL COSTS
        # Components don't have fees.
        # All that components do is enable me to save time later
        # and to record information which might otherwise be forgotten.
        if (exists $meta->{materials_cost} or exists $meta->{labour_cost})
        {
            my $wholesale = $meta->{materials_cost}
            + (defined $meta->{labour_cost} ? $meta->{labour_cost} : 0);
            $meta->{wholesale_cost} = $wholesale;
        }
    }


    $leaf->{meta} = $meta;
    return $leaf;
} # process

=head2 calculate_fees

Calculate fees like listing fees and COMMISSION (which depends on the total, backwards)

=cut
sub calculate_fees {
    my $bare_cost = shift;
    my $postage_cost = shift;

    my $feesb = {};
    my $fees = 0;
    $feesb->{listing} = ((0.2 / 0.7) # US 20c per listing per four months
        * 3); # most things are not selling, need to relist more frequently to improve search rank
    $fees += $feesb->{listing};
    # "Etsy Payments" fees are 25c AU per item, plus 4% of item cost
    $feesb->{etsy_payments} = 0.25 + ($bare_cost * 0.04);
    $fees += $feesb->{etsy_payments};
    # Etsy transaction fees are now: 5% commission
    $feesb->{etsy_transaction} = ($bare_cost * 0.05);
    $fees += $feesb->{etsy_transaction};
    # -- and that is on shipping too!
    $feesb->{postage_fees} = ($postage_cost * 0.05);
    $fees += $feesb->{postage_fees};

    # Add another 10% for Promoted Listings (at a budget of US$1 per day)
    # (Originally added $2 but for low-cost items that is too much)
    $feesb->{promoted} = (($bare_cost * 0.1) > 2 ? 2 : ($bare_cost * 0.1));
    $fees += $feesb->{promoted};
    
    # And now Etsy are charging GST on their fees
    # I think they aren't charging me any more
    ##$feesb->{GST} = $fees * 0.1;
    ##$fees += $feesb->{GST};

    # I'm not including Paypal here -- that's for if I'm not selling through Etsy.
    # (Paypal fees: 3.5% plus 30c per transaction?)
    # GST is not included because I don't have to pay GST because I'm not making $75,000
    $feesb->{total} = $fees;

    return $feesb;
} # calculate_fees

=head2 _market_class

Figure out the market class of this item

=cut
sub _market_class {
    my $mkt_prices = shift;
    my $price = shift;

    my $price_class = '';
    if (@{$mkt_prices})
    {
        if ($price < $mkt_prices->[0])
        {
            $price_class = 'below-bargain';
        }
        elsif ($price  <= $mkt_prices->[1])
        {
            $price_class = 'bargain';
        }
        elsif ($price  > $mkt_prices->[1]
                and $price <= $mkt_prices->[2])
        {
            $price_class = 'midrange';
        }
        elsif ($price  > $mkt_prices->[2]
                and $price <= $mkt_prices->[3])
        {
            $price_class = 'premium';
        }
        else
        {
            $price_class = 'OVERPRICED';
        }
    }
    return $price_class;
} #_market_class

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
        warn "NOT A SELECT: $q";
        return undef;
    }
    my $dbh = $self->{databases}->{$dbname};
    if (!$dbh)
    {
        warn "database $dbname NOT FOUND";
        return undef;
    }

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
    my $count = 0;
    my @results = ();
    my $row;
    while ($row = $sth->fetchrow_hashref)
    {
        push @results, $row;
        $count++;
    }
    return \@results;
} # _do_n_col_query

1;
