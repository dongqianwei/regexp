use v5.16;
use Engine;
use Data::Dump 'dump';
use Test::More tests => 9;

ok(Engine::_compareHash({a=>1,b=>2},{b=>2,a=>1}),'compare hash test1');
ok(!Engine::_compareHash({a=>2,b=>2},{b=>2,a=>1}),'compare hash test2');
ok(!Engine::_compareHash({c=>3,a=>1,b=>2},{b=>2,a=>1}),'compare hash test3');

my $regexp = 'abc+d?h*ef(xy(zt)*)+g';
my $tsStr = 'abcchhhefxyztztxyg';
ok(match($regexp,$tsStr),'4 test');

$regexp = 'abc|def|ghi';
$tsStr = 'abc';
ok(match($regexp,$tsStr),'5 test');
$tsStr = 'def';
ok(match($regexp,$tsStr),'6 test');
$tsStr = 'ghi';
ok(match($regexp,$tsStr),'7 test');
$regexp = 'abc|de[fgh]+';
$tsStr = 'deffhg';
ok(match($regexp,$tsStr),'8 test');

$regexp = '\+\-\*';
$tsStr = '+-*';
ok(match($regexp,$tsStr),'9 test');

$regexp = 'abc+d?[tum]+\+\-h*ef(xy|qpr(zt)*)+g';
visualNFA $regexp;
visualDFA $regexp;

