use v5.16;
use Data::Dump 'dump';
use constant OMG => 'ε';
use Test::More tests => 1;
use subs qw(_genGraph _genId _resetId);

sub _genNFA {
    my @tokens = split '',shift;
    my @stack;

    while (@tokens) {
        my $token = shift @tokens;
        if ($token ne ')') {
            push @stack, $token;
            next;
        }
        else {
            my @cache;
            while (@stack) {
                my $chr = pop @stack;
                last if $chr eq '(';
                unshift @cache, $chr;
            }
            my $graph = _genGraph @cache;
            push @stack, $graph;
        }
    }
    _genGraph @stack;
}

sub _genGraph {
    my @tokens = @_;
    my $graph = {};
    my $curId = _genId;
    my $startId = $curId;
    my $nextId;
    my $no_or_more_mark; #*
    my $one_or_more_mark;#+
    my $no_or_one_mark;  #?

    my $tokenMap = {
                    '*' => \$no_or_more_mark,
                    '+' => \$one_or_more_mark,
                    '?' => \$no_or_one_mark,
                    };

    while (@tokens) {
        my $token = shift @tokens;

        if (exists $tokenMap->{$tokens[0]}) {
            ${$tokenMap->{$tokens[0]}} = 1;
            shift @tokens;
        }

        if (ref $token) {
            while (my ($k, $v) = each %{$token->{graph}}) {
                $graph->{$k} = $v;
            }

            unshift @{$graph->{$curId}{+OMG}}, $token->{start};
            if ($one_or_more_mark) {
                unshift @{$graph->{$token->{end}}{+OMG}}, $token->{start};
            }
            if ($no_or_one_mark) {
                unshift @{$graph->{$token->{start}}{+OMG}}, $token->{end};
            }
            if ($no_or_more_mark) {
                unshift @{$graph->{$token->{end}}{+OMG}}, $token->{start};
                unshift @{$graph->{$token->{start}}{+OMG}}, $token->{end};
            }
            $curId = $token->{end};
        }
        else {
            $nextId = _genId;

            $graph->{$curId}{$token} = $nextId;
            if ($one_or_more_mark) {
                unshift @{$graph->{$nextId}{+OMG}}, $curId;
            }
            if ($no_or_one_mark) {
                unshift @{$graph->{$curId}{+OMG}}, $nextId;
            }
            if ($no_or_more_mark) {
                unshift @{$graph->{$nextId}{+OMG}}, $curId;
                unshift @{$graph->{$curId}{+OMG}}, $nextId;
            }

            $curId = $nextId;
        }
        for my $value (values $tokenMap) {
            $$value = 0;
        }

    }
    {start => $startId, graph => $graph, end => $curId};
}

sub _combineDFA {
    my $r = shift;
    my $graph = $r->{graph};
    for my $id (sort keys %$graph) {
        my $paths = $graph->{$id};
        if (exists $paths->{+OMG} and @{$paths->{+OMG}}) {
            for my $dupId (@{$paths->{+OMG}}) {
                for my $dupPath (keys %{$graph->{$dupId}}) {
                    if ($graph->{$dupId}{$dupPath} ne OMG) {
                        $paths->{$dupPath} = $graph->{$dupId}{$dupPath};
                    }
                    else {
                        unshift @{$paths->{+OMG}}, @{$graph->{$dupId}{+OMG}};
                    }
                }
                delete $graph->{$dupId};
                if ($r->{end} eq $dupId) {
                    $r->{end} = $id;
                }
                for my $renameId (sort keys %$graph) {
                    for my $renamePath (sort grep {$_ ne OMG} keys %{$graph->{$renameId}}) {
                        if ($graph->{$renameId}{$renamePath} eq $dupId) {
                            $graph->{$renameId}{$renamePath} = $id;
                        }
                    }
                    if (exists $graph->{$renameId}{+OMG}) {
                        my %set;
                        $graph->{$renameId}{+OMG} = [grep {$set{$_}?0:($set{$_} = 1) }
                                                    grep {$_ ne $renameId}
                                                    map {$_ ne $dupId? $_:$id} @{$graph->{$renameId}{+OMG}}];
                    }

                }
            }
            redo;
        }
    }
    $r;
}

sub match {
    _resetId;
    my ($regexp, $str) = @_;
    my $dfa = _combineDFA _genNFA $regexp;
    my $graph = $dfa->{graph};
    my @tokens = split '', $str;
    my $curId = $dfa->{start};
    for my $token (@tokens) {
        if (exists $graph->{$curId}{$token}) {
            $curId = $graph->{$curId}{$token};
        }
        elsif (exists $graph->{$curId}{'.'}) {
            $curId = $graph->{$curId}{'.'};
        }
        else {
            say dump $dfa;
            return 0;
        }
    }
    if ($curId eq $dfa->{end}) {
        return 1;
    }
    else {
        say dump $dfa;
        return 0;
    }

}

my $id;
sub _genId {
    $id ++;
}

sub _resetId {
    $id = 0;
}

my $regexp = 'abc+d?h*ef(xy(zt)*)+g';
my $tsStr = 'abcchhhefxyztztxyg';

ok(match($regexp,$tsStr),'one test');
