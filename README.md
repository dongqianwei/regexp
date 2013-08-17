regexp
======

# a pure perl simple regexp engine(NFA and DFA)

currently, it only implements very limited features.

following features are supported:

* . any character
* + one or more
* * no or more
* ? no or one
* () group
* [] character set
* | or
* a-z character range
* \ escape

* now you can generate a image file to see NFA or DFA using following methods,this feature require GraphViz2.
>* visualNFA
>* visualDFA
