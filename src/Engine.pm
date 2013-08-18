package Engine;
use v5.16;
use utf8;
use Carp;
use Data::Dump 'dump';
use GraphViz2;
use constant {OMG => '>',
              DEBUG => 0,
              };
use subs qw(_genGraph _genId _resetId _combineGraph _visualize _debug);
use base 'Exporter';
use vars qw(@EXPORT);

sub _debug {
    return unless DEBUG || $_[2];
    my ($name, $para) = @_;
    my @line = (caller)[2];
    say "line number: $line[0]| $name: ", dump $para;
}

@EXPORT = qw(match visualNFA visualDFA);

sub _genNFA {
    my @tokens = split '',shift;
    my @stack;
    my $bracketCounter;
    my $catchMap = {};

    while (@tokens) {
        my $token = shift @tokens;
        $bracketCounter ++ if $token eq '(';
        _debug('bracketCounter', $bracketCounter, $token eq '(');
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
            _debug('graph', $graph, 1);
            $catchMap->{$bracketCounter} = {start => $graph->{start}, end => $graph->{end}};
            push @stack, $graph;
        }
    }
    my $r =_genGraph @stack;
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
    _debug('@graphs',\@graphs);
    my @omgStack;
    for my $g (@graphs) {
        if ($g->{+OMG}) {
            unshift @omgStack, @{$g->{+OMG}};
            delete $g->{+OMG};
        }
    }
    _debug('@graphs',\@graphs);
    my %graph = map {%$_} @graphs;
    $graph{+OMG} = [@omgStack] if @omgStack;
    \%graph;
}

sub _combineDFA {
    my $r = shift;
    my $graph = $r->{graph};
    #iterate all nodes in the graph
    for my $id (sort keys %$graph) {
        _debug('id', $id);
        #all paths of the current nodes
        #combines all OMG nodes (the same) nodes to current node
        #processed nodes,key :nodeId; value: whether processed
        my %processed;
        my @newFindNodes;
        my @waitForProcessed = ($id);
        while (@waitForProcessed) {
            _debug('waitForProcessed',\@waitForProcessed);
            my $curIdForComb = shift @waitForProcessed;
            _debug('curIdForComb',$curIdForComb);
            #current node processed
            $processed{$curIdForComb} = 1;
            _debug('processed',\%processed);
            _debug('OMG nodes',$graph->{$curIdForComb}{+OMG});
            #exists unprocessed nodes
            if (exists $graph->{$curIdForComb}{+OMG} and grep {!$processed{$_}} @{$graph->{$curIdForComb}{+OMG}}) {
                #store OMG nodes of current nodes
                @newFindNodes = grep {not exists $processed{$_}} @{$graph->{$curIdForComb}{+OMG}};
                _debug('newFindNodes', \@newFindNodes);
                unshift @waitForProcessed, @newFindNodes;
                _debug('waitForProcessed',\@waitForProcessed);
                _debug('processed',\%processed);
                %processed = %processed, map {$_, 0} @newFindNodes;
            }
        }
        my @dupIds = keys %processed;
        _debug('@dupIds',\@dupIds);
        next if @dupIds == 1;
        $graph->{$id} = _combineGraph map {$graph->{$_}} @dupIds;
        _debug('$graph',$graph);
        #delete dup nodes of current Id
        for my $dupId (grep {$_ != $id} @dupIds) {
            delete $graph->{$dupId};
        }

        _debug('$graph', $graph);

        for my $renameId (sort keys %$graph) {
            for my $renamePath (grep {$_ ne OMG} keys %{$graph->{$renameId}}) {
                if ($processed{$graph->{$renameId}{$renamePath}}) {
                    $graph->{$renameId}{$renamePath} = $id;
                }
            }
            if (exists $graph->{$renameId}{+OMG}) {
                my %set;
                $graph->{$renameId}{+OMG} = [grep {$set{$_}?0:($set{$_} = 1) }
                                            grep {$_ ne $renameId}
                                            map {$processed{$_} ? $id:$_} @{$graph->{$renameId}{+OMG}}];
            }

        }
        $r->{end} = $id if $processed{$r->{end}};
        for my $catchSeqId (keys %{$r->{catch}}) {
            $r->{catch}{$catchSeqId}{start} = $id if $processed{$r->{catch}{$catchSeqId}{start}};
            $r->{catch}{$catchSeqId}{end}   = $id if $processed{$r->{catch}{$catchSeqId}{end}};
        }
        redo;
    }
    for my $nopId (grep {! grep {$_ ne OMG} keys $graph->{$_}} keys %$graph) {
        delete $graph->{$nopId};
    }
    $r;
}

sub match {
    _resetId;
    my ($regexp, $str) = @_;
    my @tokens = split '', $str;
    my $dfa = _combineDFA _genNFA $regexp;
    _debug('$dfa',$dfa,1);
    my ($catchMark, @catchStack, %catchGroup, $catchdNum);
    my ($graph, $catch, $curId) = @$dfa{qw(graph catch start)};
    for my $token (@tokens) {
        #if in catchGroup
        if (!defined $catchdNum) {
            ($catchdNum) = grep {$catch->{$_}{start} eq $curId} keys %$catch;
            _debug('curId', $curId, 1);
            _debug('catchdNum', $catchdNum, 1);
        }
        if (defined $catchdNum) {
            $catchMark = 1;
        }

        if ($catchMark) {
            _debug('curId', $curId, 1);
            _debug('$catch->{$catchdNum}{end}', $catch->{$catchdNum}{end}, 1);
            if ($curId eq $catch->{$catchdNum}{end}) {
                $catchMark = 0;
                $catchGroup{$catchdNum} = \@catchStack;
                _debug('catchGroup', \%catchGroup, 1);
                undef $catchdNum;
                @catchStack = ();
            }
            else {
              push @catchStack, $token;
              _debug ('catchStack', \@catchStack, 1);
            }
        }

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
        return [1, \%catchGroup];
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
    $viz -> run(format => 'png', output_file => $pname.'.png');
}

my $id;
sub _genId {
    $id ++;
}

sub _resetId {
    $id = 0;
}

1;
