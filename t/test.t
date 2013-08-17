use v5.16;
use Engine;
use Test::More tests => 6;

my $regexp = 'abc+d?h*ef(xy(zt)*)+g';
my $tsStr = 'abcchhhefxyztztxyg';

ok(match($regexp,$tsStr),'one test');

$regexp = 'abc|def|ghi';
$tsStr = 'abc';
ok(match($regexp,$tsStr),'two test');
$tsStr = 'def';
ok(match($regexp,$tsStr),'three test');
$tsStr = 'ghi';
ok(match($regexp,$tsStr),'four test');
$regexp = 'abc|de[fgh]+';
$tsStr = 'deffhg';
ok(match($regexp,$tsStr),'five test');
$regexp = '\+\-\*';
$tsStr = '+-*';
ok(match($regexp,$tsStr),'six test');

visualDFA 'abc+d?h*ef(xy(zt)*)+g';
