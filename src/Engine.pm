package Engine;
use v5.16;
use utf8;
use Carp;
use Data::Dump 'dump';
use GraphViz2;
use constant OMG => 'ε';
use subs qw(_genGraph _genId _resetId _combineGraph _visualize);
use base 'Exporter';
use vars qw(@EXPORT);

@EXPORT = qw(match visualNFA visualDFA);

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

    my @square_stack;    #tokens is square bracket
    my $square_mark;     #square bracket mark

    my $tokenMap = {
                    '*' => \$no_or_more_mark,
                    '+' => \$one_or_more_mark,
                    '?' => \$no_or_one_mark,
                    };

    while (@tokens) {
        my $token = shift @tokens;

        if ($token eq '\\') {
            my $chr = shift @tokens;
            my ($inId, $outId) = (_genId(), _genId());
            $token = {start => $inId,
                              end => $outId,
                              graph => {$inId => {$chr => $outId}}};
        }


        if (exists $tokenMap->{$tokens[0]}) {
            ${$tokenMap->{$tokens[0]}} = 1;
            shift @tokens;
        }

        if ($token eq '[') {
            $square_mark = 1;
            next;
        }

        if ($square_mark) {
            if ($token ne ']') {
                push @square_stack, $token;
                next;
            }
            else {
                $square_mark = 0;
                my $switchGraph = {};
                my $inId = _genId;
                my $outId = _genId;
                for my $switchToken (@square_stack) {
                    $graph->{$inId}{$switchToken} = $outId;
                }
                unshift @tokens, {start => $inId, graph => $switchGraph, end => $outId};
                next;
            }
        }

        if ($token eq '|') {
            my $lGraph = {start => $startId, graph => $graph, end => $curId};
            my $rGraph = _genGraph @tokens;
            my $combinedGraph = _combineGraph $lGraph->{graph}, $rGraph->{graph};
            my $curId = _genId;
            my $nextId = _genId;

            unshift @{$combinedGraph->{$curId}{+OMG}}, $lGraph->{start};
            unshift @{$combinedGraph->{$curId}{+OMG}}, $rGraph->{start};
            unshift @{$combinedGraph->{$lGraph->{end}}{+OMG}}, $nextId;
            unshift @{$combinedGraph->{$rGraph->{end}}{+OMG}}, $nextId;
            return {start => $curId, graph => $combinedGraph, end => $nextId};
        }


        if (ref $token) {
            $graph = _combineGraph $graph, $token->{graph};

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

sub _combineGraph {
    my ($lGraph, $rGraph) = @_;
    my %graph = (%$lGraph, %$rGraph);
    \%graph;
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

sub visualNFA {
    _visualize _genNFA shift;
}

sub visualDFA {
    _visualize _combineDFA _genNFA shift;
}

sub _visualize {
    my $pic = shift;
    my ($graph, $start, $end) = @$pic{'graph','start','end'};
    my($viz) = GraphViz2 -> new
        (
         edge   => {color => 'green'},
         global => {directed => 1},
         graph  => {label => 'image of state machine', rankdir => 'TB'},
         node   => {shape => 'circle'},
        );
    $viz->add_node(name => $start, color => 'blue');
    $viz->add_node(name => $end, color => 'red');
    #add nodes
    for my $nodeId (keys %$graph) {
        $viz -> add_node(name => $nodeId, color => 'grey') unless $nodeId eq $start;
    }
    #add edges
    for my $nodeId (keys %$graph) {
        for my $edge (keys %{$graph->{$nodeId}}) {
            my $to = $graph->{$nodeId}{$edge};
            if (ref $to) {
                for my $omgId(@$to) {
                    $viz -> add_edge(from => $nodeId, to => $omgId, label => $edge);
                }
            }
            else {
                $viz -> add_edge(from => $nodeId, to => $to, label => $edge);
            }
        }
    }
    $viz -> run(format => 'png', output_file => 'out.png');
}

my $id;
sub _genId {
    $id ++;
}

sub _resetId {
    $id = 0;
}

1;
