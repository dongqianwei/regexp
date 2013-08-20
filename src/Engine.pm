package Engine;
use v5.16;
use utf8;
use Carp;
use Data::Dump 'dump';
use GraphViz2;
use constant {OMG => 'ε',
              DEBUG => 1,
              };
use subs qw(_genGraph _genId _resetId _combineGraph _visualize _debug _compareHash);
use base 'Exporter';
use vars qw(@EXPORT);

sub _debug {
    return unless DEBUG || $_[2];
    my ($name, $para) = @_;
    my @line = (caller)[2];
}

@EXPORT = qw(match visualNFA visualDFA);

sub _genNFA {
    _resetId;
    my @tokens = split '',shift;
    my @stack;
    my $bracketCounter;
    my $catchMap = {};

    while (@tokens) {
        my $token = shift @tokens;
        $bracketCounter ++ if $token eq '(';
        #_debug('bracketCounter', $bracketCounter, $token eq '(');
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
            #_debug('graph', $graph, 1);
            $catchMap->{$bracketCounter} = {start => $graph->{start}, end => $graph->{end}};
            push @stack, $graph;
        }
    }
    my $r =_genGraph @stack;
    $r->{graph}{$r->{end}} = {};
    $r->{catch} = $catchMap;
    _resetId;
    $r;
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
    my @graphs = @_;
    my %graph = map {%$_} @graphs;
    \%graph;
}

sub _combineDFA {
    my $r = shift;
    my $graph = $r->{graph};
    my %dfaMap;
    #iterate all nodes in the graph
    for my $id (sort keys %$graph) {
        #_debug('id', $id);
        #all paths of the current nodes
        #combines all OMG nodes (the same) nodes to current node
        #processed nodes,key :nodeId; value: whether processed
        my %processed;
        my @newFindNodes;
        my @waitForProcessed = ($id);
        while (@waitForProcessed) {
            #_debug('waitForProcessed',\@waitForProcessed);
            my $curIdForComb = shift @waitForProcessed;
            #_debug('curIdForComb',$curIdForComb);
            #current node processed
            $processed{$curIdForComb} = 1;
            #_debug('processed',\%processed);
            #_debug('OMG nodes',$graph->{$curIdForComb}{+OMG});
            #exists unprocessed nodes
            if (exists $graph->{$curIdForComb}{+OMG} and grep {!$processed{$_}} @{$graph->{$curIdForComb}{+OMG}}) {
                #store OMG nodes of current nodes
                @newFindNodes = grep {not exists $processed{$_}} @{$graph->{$curIdForComb}{+OMG}};
                #_debug('newFindNodes', \@newFindNodes);
                unshift @waitForProcessed, @newFindNodes;
                #_debug('waitForProcessed',\@waitForProcessed);
                #_debug('processed',\%processed);
                %processed = %processed, map {$_, 0} @newFindNodes;
            }
        }
        $dfaMap{$id} = [keys %processed];
    }
    _debug('dfaMap', \%dfaMap);
    my %dfaGraph;
    my %endIdSet;
    $endIdSet{$r->{end}} = 1;
    for my $nodeId (keys %dfaMap) {
        for my $mapedId (@{$dfaMap{$nodeId}}) {
            for my $path (grep {$_ ne +OMG} keys %{$graph->{$mapedId}}) {
                $dfaGraph{$nodeId}{$path} = $graph->{$mapedId}{$path};
            }
            ##if end point paths are all OMG
            #if (grep {$_ eq $r->{end}} @{$dfaMap{$mapedId}}) {
            #    $endIdSet{$mapedId} = 1;
            #}

        }
    }

    #reduce dfa
    my @nodes = grep {$_ ne $r->{start}} grep {!$endIdSet{$_}} keys %dfaGraph;
    while (@nodes) {
        my $node = shift @nodes;
        my @dupNodes;
        for my $id (@nodes) {
            unshift @dupNodes, $id if _compareHash($dfaGraph{$node}, $dfaGraph{$id});
        }
        next unless @dupNodes;
        delete $dfaGraph{$_} for @dupNodes;
        my %dupNodesSet = map {$_,1} @dupNodes;
        @nodes = grep {!$dupNodesSet{$_}} @nodes;
        for my $nodeId (keys %dfaGraph) {
            for my $path (keys %{$dfaGraph{$nodeId}}) {
                if ($dupNodesSet{$dfaGraph{$nodeId}{$path}}) {
                    $dfaGraph{$nodeId}{$path} = $node;
                }
            }
        }
    }

    #delete unreachable nodes, grep start node
    my %reachable = map {$_, 1} map {values %{$_}} values %dfaGraph;
    eval{delete $dfaGraph{$_}; delete $endIdSet{$_}} for
        grep {$_ ne $r->{start}}
        grep {!$reachable{$_}} keys %dfaGraph, keys %endIdSet;

    {start => $r->{start}, end => \%endIdSet, graph => \%dfaGraph};
}

sub _compareHash {
    my ($h1, $h2) = @_;
    return 0 if scalar keys %{$h1} != scalar keys %{$h2};
    do {return 0 if $h1->{$_} ne $h2->{$_}} for keys %{$h1};
    return 1;
}

sub match {
    _resetId;
    my ($regexp, $str) = @_;
    my @tokens = split '', $str;
    my $dfa = _combineDFA _genNFA $regexp;
    #_debug('$dfa',$dfa,1);
    my ($graph, $catch, $curId) = @$dfa{qw(graph catch start)};
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
    if ($dfa->{end}{$curId}) {
        return 1;
    }
    else {
        say dump $dfa;
        return 0;
    }

}

sub visualNFA {
    _visualize ((_genNFA shift), 'nfa');
}

sub visualDFA {
    _visualize ((_combineDFA _genNFA shift), 'dfa');
}

sub _visualize {
    my ($pic, $pname) = @_;
    my ($graph, $start, $endIdSet) = @$pic{'graph','start','end'};
    my($viz) = GraphViz2 -> new
        (
         edge   => {color => 'green'},
         global => {directed => 1},
         graph  => {label => 'image of state machine', rankdir => 'TB'},
         node   => {shape => 'circle'},
        );
    my %addedNodeSet;
    $viz->add_node(name => $start, color => 'blue');
    $addedNodeSet{$start} = 1;
    if (ref $endIdSet) {
        _debug('endIdSet',$endIdSet);
        do{$viz->add_node(name => $_, color => 'red');$addedNodeSet{$_} = 1} for keys %{$endIdSet};
    }
    else {
        $viz->add_node(name => $endIdSet, color => 'red');
        $addedNodeSet{$endIdSet} = 1;
    }

    #add nodes
    for my $nodeId (keys %$graph) {
        $viz -> add_node(name => $nodeId, color => 'grey') unless $addedNodeSet{$nodeId};
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
    $viz -> run(format => 'png', output_file => $pname.'.png');
}

my $id;
sub _genId {
    'S'.$id ++;
}

sub _resetId {
    $id = 0;
}

1;
