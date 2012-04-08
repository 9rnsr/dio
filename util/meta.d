/**
    original of this module is by rsinfu (http://gist.github.com/598659)
*/
module util.meta;

private import std.conv : to;
private import std.string;
private import std.traits;


@safe:


/**
 */
template Sequence(seq...)
{
    alias seq Sequence;
}


//----------------------------------------------------------------------------//
// Algorithms
//----------------------------------------------------------------------------//


/**
 */
template staticMap(alias map, seq...)
{
    static if (seq.length < 2)
    {
        static if (seq.length == 0)
        {
            alias Sequence!() staticMap;
        }
        else
        {
            alias Sequence!(Instantiate!map.With!(seq[0])) staticMap;
        }
    }
    else
    {
        alias Sequence!(staticMap!(map, seq[ 0  .. $/2]),
                        staticMap!(map, seq[$/2 ..  $ ]))
              staticMap;
    }
}

unittest
{
}


/**
 */
template staticFilter(alias pred, seq...)
{
    static if (seq.length < 2)
    {
        static if (seq.length == 1 && Instantiate!pred.With!(seq[0]))
        {
            alias seq staticFilter;
        }
        else
        {
            alias Sequence!() staticFilter;
        }
    }
    else
    {
        alias Sequence!(staticFilter!(pred, seq[ 0  .. $/2]),
                        staticFilter!(pred, seq[$/2 ..  $ ]))
              staticFilter;
    }
}

unittest
{
}


/**
 */
template staticReduce(alias compose, Seed, seq...)
{
    static if (seq.length == 0)
    {
        alias Seed staticReduce;
    }
    else
    {
        alias staticReduce!(compose,
                            Instantiate!compose.With!(Seed, seq[0]),
                            seq[1 .. $])
              staticReduce;
    }
}

/// ditto
template staticReduce(alias compose, alias Seed, seq...)
{
    static if (seq.length == 0)
    {
        alias Seed staticReduce;
    }
    else
    {
        alias staticReduce!(compose,
                            Instantiate!compose.With!(Seed, seq[0]),
                            seq[1 .. $])
              staticReduce;
    }
}

unittest
{
}


/**
 */
template staticRemove(E, seq...)
{
    alias staticRemoveIf!(Instantiate!isSame.bindFront!E, seq) staticRemove;
}

/// ditto
template staticRemove(alias E, seq...)
{
    alias staticRemoveIf!(Instantiate!isSame.bindFront!E, seq) staticRemove;
}

unittest
{
}


/// ditto
template staticRemoveIf(alias pred, seq...)
{
    alias staticFilter!(templateNot!pred, seq) staticRemoveIf;
}

unittest
{
}


// Groundwork for find-family algorithms
private template _staticFindChunk(alias pred, size_t m)
{
    template index(seq...)
        if (seq.length < m)
    {
        enum index = seq.length;
    }

    template index(seq...)
        if (m <= seq.length && seq.length < 2*m)
    {
        static if (Instantiate!pred.With!(seq[0 .. m]))
        {
            enum index = cast(size_t) 0;
        }
        else
        {
            enum index = index!(seq[1 .. $]) + 1;
        }
    }

    template index(seq...)
        if (2*m <= seq.length)
    {
        static if (index!(seq[0 .. $/2 + m - 1]) < seq.length/2)
        {
            enum index = index!(seq[0 .. $/2 + m - 1]);
        }
        else
        {
            enum index = index!(seq[$/2 .. $]) + seq.length/2;
        }
    }
}


/**
 */
template staticFind(E, seq...)
{
    alias staticFindIf!(Instantiate!isSame.bindFront!E, seq) staticFind;
}

/// ditto
template staticFind(alias E, seq...)
{
    alias staticFindIf!(Instantiate!isSame.bindFront!E, seq) staticFind;
}

unittest
{
}


/// ditto
template staticFindIf(alias pred, seq...)
{
    alias seq[_staticFindChunk!(pred, 1).index!seq .. $] staticFindIf;
}

unittest
{
}


/**
 */
template staticFindAdjacentIf(alias pred, seq...)
{
    alias seq[_staticFindChunk!(pred, 2).index!seq .. $] staticFindAdjacentIf;
}

unittest
{
}


/**
 */
template staticIndexOf(E, seq...)
{
    static if (staticFind!(E, seq).length == 0)
    {
        enum /*sizediff_t*/ staticIndexOf = -1;
    }
    else
    {
        enum /*sizediff_t*/ staticIndexOf = (seq.length -
                                         staticFind!(E, seq).length);
    }
}

/// ditto
template staticIndexOf(alias E, seq...)
{
    static if (staticFind!(E, seq).length == 0)
    {
        enum /*sizediff_t*/ staticIndexOf = -1;
    }
    else
    {
        enum /*sizediff_t*/ staticIndexOf = (seq.length -
                                         staticFind!(E, seq).length);
    }
}

unittest
{
}


/**
 */
template staticUntil(E, seq...)
{
    alias staticUntilIf!(Instantiate!isSame.bindFront!E, seq) staticUntil;
}

/// ditto
template staticUntil(alias E, seq...)
{
    alias staticUntilIf!(Instantiate!isSame.bindFront!E, seq) staticUntil;
}

unittest
{
}


/// ditto
template staticUntilIf(alias pred, seq...)
{
    alias seq[0 .. _staticFindChunk!(pred, 1).index!seq] staticUntilIf;
}

unittest
{
}


/**
 */
template staticCount(E, seq...)
{
    alias staticCountIf!(Instantiate!isSame.bindFront!E, seq) staticCount;
}

/// ditto
template staticCount(alias E, seq...)
{
    alias staticCountIf!(Instantiate!isSame.bindFront!E, seq) staticCount;
}

unittest
{
}


/// ditto
template staticCountIf(alias pred, seq...)
{
    static if (seq.length <= 1)
    {
        static if (seq.length == 0 || !Instantiate!pred.With!(seq[0]))
        {
            enum size_t staticCountIf = 0;
        }
        else
        {
            enum size_t staticCountIf = 1;
        }
    }
    else
    {
        enum staticCountIf = staticCountIf!(pred, seq[ 0  .. $/2]) +
                             staticCountIf!(pred, seq[$/2 ..  $ ]);
    }
}

unittest
{
}


/**
 */
template staticReplace(From, To, seq...)
{
    alias staticMap!(_staticReplace!(From, To).map, seq) staticReplace;
}

/// ditto
template staticReplace(alias From, To, seq...)
{
    alias staticMap!(_staticReplace!(From, To).map, seq) staticReplace;
}

/// ditto
template staticReplace(From, alias To, seq...)
{
    alias staticMap!(_staticReplace!(From, To).map, seq) staticReplace;
}

/// ditto
template staticReplace(alias From, alias To, seq...)
{
    alias staticMap!(_staticReplace!(From, To).map, seq) staticReplace;
}

private template _staticReplace(tr...)
{
    alias Identity!(tr[0]) from;
    alias Identity!(tr[1])   to;

    template map(e...)
    {
        static if (isSame!(e, from))
        {
            alias to map;
        }
        else
        {
            alias e  map;
        }
    }
}

unittest
{
}


/**
 */
template staticMost(alias comp, seq...)
    if (seq.length >= 1)
{
    static if (seq.length <= 2)
    {
        static if (seq.length == 1 || !Instantiate!comp.With!(seq[1], seq[0]))
        {
            alias Identity!(seq[0]) staticMost;
        }
        else
        {
            alias Identity!(seq[1]) staticMost;
        }
    }
    else
    {
        alias staticMost!(comp, staticMost!(comp, seq[ 0  .. $/2]),
                                staticMost!(comp, seq[$/2 ..  $ ]))
              staticMost;
    }
}

unittest
{
}


/**
 */
template staticSort(alias comp, seq...)
{
    static if (seq.length < 2)
    {
        alias seq staticSort;
    }
    else
    {
         alias _staticMerger!comp.Merge!(staticSort!(comp, seq[ 0  .. $/2]))
                                  .With!(staticSort!(comp, seq[$/2 ..  $ ]))
               staticSort;
    }
}

private template _staticMerger(alias comp)
{
    template Merge()
    {
        template With(B...)
        {
            alias B With;
        }
    }

    template Merge(A...)
    {
        template With()
        {
            alias A With;
        }

        template With(B...)
        {
            static if (Instantiate!comp.With!(B[0], A[0]))
            {
                alias Sequence!(B[0], Merge!(A        )
                                      .With!(B[1 .. $])) With;
            }
            else
            {
                alias Sequence!(A[0], Merge!(A[1 .. $])
                                      .With!(B       )) With;
            }
        }
    }
}

/// ditto
template isStaticSorted(alias comp, seq...)
{
    static if (seq.length < 2)
    {
        enum isStaticSorted = true;
    }
    else
    {
        static if (Instantiate!comp.With!(seq[$/2], seq[$/2 - 1]))
        {
            enum isStaticSorted = false;
        }
        else
        {
            enum isStaticSorted = isStaticSorted!(comp, seq[ 0  .. $/2]) &&
                                  isStaticSorted!(comp, seq[$/2 ..  $ ]);
        }
    }
}

unittest
{
}


/**
 */
template staticUniqSort(alias comp, seq...)
{
    static if (seq.length < 2)
    {
        alias seq staticUniqSort;
    }
    else
    {
        alias _staticUniqMerger!comp
                    .Merge!(staticUniqSort!(comp, seq[ 0  .. $/2]))
                     .With!(staticUniqSort!(comp, seq[$/2 ..  $ ]))
              staticUniqSort;
    }
}

private template _staticUniqMerger(alias comp)
{
    template Merge()
    {
        template With(B...)
        {
            alias B With;
        }
    }

    template Merge(A...)
    {
        template With()
        {
            alias A With;
        }

        template With(B...)
        {
            static if (Instantiate!comp.With!(A[0], B[0]))
            {
                alias Sequence!(A[0], Merge!(A[1 .. $])
                                      .With!(B[0 .. $])) With;
            }
            else static if (Instantiate!comp.With!(B[0], A[0]))
            {
                alias Sequence!(B[0], Merge!(A[0 .. $])
                                      .With!(B[1 .. $])) With;
            }
            else
            {
                alias Merge!(A[0 .. $])
                      .With!(B[1 .. $]) With;
            }
        }
    }
}

/// ditto
template isStaticUniqSorted(alias comp, seq...)
{
    static if (seq.length < 2)
    {
        enum isStaticUniqSorted = true;
    }
    else
    {
        static if (Instantiate!comp.With!(seq[$/2 - 1], seq[$/2]))
        {
            enum isStaticUniqSorted =
                    isStaticUniqSorted!(comp, seq[ 0  .. $/2]) &&
                    isStaticUniqSorted!(comp, seq[$/2 ..  $ ]);
        }
        else
        {
            enum isStaticUniqSorted = false;
        }
    }
}

unittest
{
}


/**
 */
template staticUniq(seq...)
{
    static if (seq.length <= 1)
    {
        alias seq staticUniq;
    }
    else
    {
        static if (isSame!(seq[$/2 - 1], seq[$/2]))
        {
            alias Sequence!(staticUniq!(seq[0 .. $/2]),
                            staticUniq!(seq[$/2 .. $])[1 .. $])
                  staticUniq;
        }
        else
        {
            alias Sequence!(staticUniq!(seq[0 .. $/2]),
                            staticUniq!(seq[$/2 .. $]))
                  staticUniq;
        }
    }
}

unittest
{
}


/**
 */
template staticRemoveDuplicates(seq...)
{
    static if (seq.length <= 1)
    {
        alias seq staticRemoveDuplicates;
    }
    else
    {
        alias Sequence!(seq[0],
                        staticRemoveDuplicates!(staticRemove!(seq[0],
                                                              seq[1 .. $])))
              staticRemoveDuplicates;
    }
}

unittest
{
}


/**
 */
template staticReverse(seq...)
{
    static if (seq.length < 2)
    {
        alias seq staticReverse;
    }
    else
    {
        alias Sequence!(staticReverse!(seq[$/2 ..  $ ]),
                        staticReverse!(seq[ 0  .. $/2]))
              staticReverse;
    }
}

unittest
{
}


/**
 */
template staticRepeat(size_t n, seq...)
{
    static if (n == 0)
    {
        alias Sequence!() staticRepeat;
    }
    else
    {
        static if (n == 1 || seq.length == 0)
        {
            alias seq staticRepeat;
        }
        else
        {
            alias Sequence!(staticRepeat!(   n    / 2, seq),
                            staticRepeat!((n + 1) / 2, seq))
                  staticRepeat;
        }
    }
}

unittest
{
}


/**
 */
template staticStride(size_t n, seq...)
    if (n >= 1)
{
    static if (n == 1 || seq.length <= 1)
    {
        alias seq staticStride;
    }
    else
    {
        static if (seq.length <= n)
        {
            alias seq[0 .. 1] staticStride;
        }
        else
        {
            alias Sequence!(staticStride!(n, seq[0 .. _strideMid!($, n)]),
                            staticStride!(n, seq[_strideMid!($, n) .. $]))
                  staticStride;
        }
    }
}

private template _strideMid(size_t n, size_t k)
{
    enum _strideMid = ((n + k - 1) / k / 2) * k;
}

unittest
{
}


/**
 */
template staticTransverse(size_t i, tuples...)
{
    static if (tuples.length < 2)
    {
        static if (tuples.length == 0)
        {
            alias Sequence!() staticTransverse;
        }
        else
        {
            alias Sequence!(tuples[0].Expand[i]) staticTransverse;
        }
    }
    else
    {
        alias Sequence!(staticTransverse!(i, tuples[ 0  .. $/2]),
                        staticTransverse!(i, tuples[$/2 ..  $ ]))
              staticTransverse;
    }
}

/// ditto
template staticFrontTransverse(tuples...)
{
    alias staticTransverse!(0, tuples) staticFrontTransverse;
}

unittest
{
}


/**
 */
template staticZip(tuples...)
{
    alias staticMap!(_ZipTransverser!tuples,
                     staticIota!(0, _minLength!tuples))
          staticZip;
}

private
{
    template _ZipTransverser(tuples...)
    {
        template _ZipTransverser(size_t i)
        {
            alias Wrap!(staticTransverse!(i, tuples)) _ZipTransverser;
        }
    }

    template _minLength(tuples...)
    {
        static if (tuples.length == 0)
            enum _minLength = 0;
        else
            alias staticMost!(q{ a < b }, staticMap!(q{ a.length }, tuples))
                  _minLength;
    }
}

unittest
{
}


/**
 */
template staticPermutations(seq...)
{
    static if (seq.length > 5)
    {
        static assert(0, "too many elements for compile-time permutation");
    }
    else
    {
        alias _staticPermutations!(seq.length, seq).Result
               staticPermutations;
    }
}

private
{
    template _staticPermutations(size_t k, seq...)
        if (k == 0)
    {
        alias Sequence!(metaArray!()) Result;
    }

    template _staticPermutations(size_t k, seq...)
        if (k == 1)
    {
        alias staticMap!(metaArray, seq) Result;
    }

    template _staticPermutations(size_t k, seq...)
        if (k >= 2)
    {
        template consLater(car...)
        {
            template consLater(alias wrap)
            {
                alias Wrap.insertFront!car consLater;
            }
        }

        template consMapAt(size_t i)
        {
            alias staticMap!(consLater!(seq[i]),
                            _staticPermutations!(k - 1,
                                                 seq[  0   .. i],
                                                 seq[i + 1 .. $]).Result)
                  consMapAt;
        }

        alias staticMap!(consMapAt, staticIota!(seq.length)) Result;
    }
}

unittest
{
}


/**
 */
template staticCombinations(size_t k, seq...)
    if (k <= seq.length)
{
    alias _staticCombinations!(k, seq).Result staticCombinations;
}

private
{
    template _staticCombinations(size_t k, seq...)
        if (k == 0)
    {
        alias Sequence!(Wrap!()) Result;
    }

    template _staticCombinations(size_t k, seq...)
        if (k == 1)
    {
        alias staticMap!(Wrap, seq) Result;
    }

    template _staticCombinations(size_t k, seq...)
        if (k >= 2)
    {
        template consLater(car...)
        {
            template consLater(alias wrap)
            {
                alias wrap.insertFront!car consLater;
            }
        }

        template consMapFrom(size_t i)
        {
            alias staticMap!(consLater!(seq[i]),
                            _staticCombinations!(k - 1,
                                                 seq[i + 1 .. $]).Result)
                  consMapFrom;
        }

        alias staticMap!(consMapFrom, staticIota!(seq.length)) Result;
    }
}

version(unittest)
{
    //pragma(msg, staticCombinations!(3, int, long, float, double));
//  static assert(
//      is(staticCombinations!(3, int, long, float, double)
//          == Sequence!(
//              Wrap!(int,long,float), Wrap!(int,long,double),
//              Wrap!(int,float,double), Wrap!(long,float,double))));
}


/**
 */
template staticCartesian(tuples...)
    if (tuples.length >= 1)
{
    alias _staticCartesian!tuples.Result staticCartesian;
}

private
{
    template _staticCartesian(alias wrap)
    {
        alias staticMap!(Wrap, wrap.Expand) Result;
    }

    template _staticCartesian(alias wrap, rest...)
    {
        alias _staticCartesian!rest.Result subCartesian;

        template consLater(car...)
        {
            template consLater(alias wrap)
            {
                alias wrap.insertFront!car consLater;
            }
        }

        template consMap(car...)
        {
            alias staticMap!(consLater!car, subCartesian) consMap;
        }

        alias staticMap!(consMap, wrap.Expand) Result;
    }
}

version(unittest)
{
    //pragma(msg, staticCartesian!(Wrap!(int, long), Wrap!(float, double)));
}


/**
 */
template staticIota(int beg, int end, int step = 1)
    if (step != 0)
{
    static if (beg + 1 >= end)
    {
        static if (beg >= end)
        {
            alias Sequence!() staticIota;
        }
        else
        {
            alias Sequence!(+beg) staticIota;
        }
    }
    else
    {
        alias Sequence!(staticIota!(beg, _iotaMid!(beg, end)     ),
                        staticIota!(     _iotaMid!(beg, end), end))
              staticIota;
    }
}

private template _iotaMid(int beg, int end)
{
    enum _iotaMid = beg + (end - beg) / 2;
}

/// ditto
template staticIota(int end)
{
    alias staticIota!(0, end) staticIota;
}

unittest
{
}


/**
 */
template allSatisfy(alias pred, seq...)
{
    enum allSatisfy = (staticCountIf!(pred, seq) == seq.length);
}

/// ditto
template anySatisfy(alias pred, seq...)
{
    enum anySatisfy = (staticCountIf!(pred, seq) > 0);
}

/// ditto
template noneSatisfy(alias pred, seq...)
{
    enum noneSatisfy = (staticCountIf!(pred, seq) == 0);
}

unittest
{
}



//----------------------------------------------------------------------------//
// Convenience Templates
//----------------------------------------------------------------------------//


/**
 */
template Identity(alias E)
{
    alias E Identity;
}

/// ditto
template Identity(E)
{
    alias E Identity;
}

unittest
{
}


/**
 */
template Wrap(seq...)
{
    /**
     */
    alias seq Expand;


    /**
     */
    enum bool empty = !seq.length;


    /**
     */
    enum size_t length = seq.length;


    /**
     */
    template at(size_t i)
    {
        alias Identity!(seq[i]) at;
    }


    /**
     */
    template slice(size_t i, size_t j)
    {
        alias Wrap!(seq[i .. j]) slice;
    }


    /**
     */
    template take(size_t n)
    {
        alias Wrap!(seq[0 .. (n < $ ? n : $)]) take;
    }


    /**
     */
    template drop(size_t n)
    {
        alias Wrap!(seq[(n < $ ? n : $) .. $]) drop;
    }


    /**
     */
    template insertFront(aseq...)
    {
        alias Wrap!(aseq, seq) insertFront;
    }


    /**
     */
    template insertBack(aseq...)
    {
        alias Wrap!(seq, aseq) insertBack;
    }


    /**
     */
    template insertAt(size_t i, aseq...)
    {
        alias Wrap!(seq[0 .. i], aseq, seq[i .. $]) insertAt;
    }


    /**
     */
    template contains(subseq...)
    {
        static if (subseq.length == 0 || subseq.length > seq.length)
        {
            enum contains = (subseq.length == 0);
        }
        else
        {
            enum contains = _staticFindChunk!(MatchSequence!aseq.With,
                                              subseq.length)
                                .index!seq < seq.length;
        }
    }


 private:

    template ToType()
    {
        struct ToType {}
    }

    version (unittest) alias ToType!() _T;
}

unittest
{
}


/**
 */
template MatchSequence(seq...)
{
    /**
     */
    template With(aseq...)
    {
        enum With = is(Wrap!seq.ToType!() == Wrap!aseq.ToType!());
    }
}

unittest
{
}


/**
 */
template isSame(A, B)
{
    enum isSame = is(A == B);
}

/// ditto
template isSame(alias A, alias B)
{
    enum isSame = is(Wrap!A.ToType!() == Wrap!B.ToType!());
}

/// ditto
template isSame(alias A, B)
{
    enum isSame = false;
}

/// ditto
template isSame(A, alias B)
{
    enum isSame = false;
}

unittest
{
}


/**
 */
template templateFun(string expr)
{
    alias _templateFun!expr._ templateFun;
}

// XXX
private template _templateFun(string expr)
{
    enum size_t maxArgs = ('z' - 'a' + 1);

    template _(args...)
        if (args.length <= maxArgs)
    {
        alias invoke!args.result _;
    }

    template invoke(args...)
        if (args.length <= maxArgs)
    {
        mixin bind!(0, args);
        mixin("alias Identity!(" ~ expr ~ ") result;");
    }

    template bind(size_t i, args...)
    {
        static if (i < args.length)
        {
            mixin("alias Identity!(args[i]) " ~ paramAt!i ~ ";");
            mixin bind!(i + 1, args);
        }
    }

    template paramAt(size_t i)
        if (i < maxArgs)
    {
        enum dchar paramAt = ('a' + i);
    }
}

unittest
{
}


//----------------------------------------------------------------------------//
// Templationals
//----------------------------------------------------------------------------//

/**
 */
template Instantiate(alias templat)
{
    /**
     */
    template With(args...)
    {
        alias templat!args With;
    }

    /**
     */
    template Returns(string name)
    {
        template Returns(args...)
        {
            mixin("alias templat!args." ~ name ~ " Returns;");
        }
    }

    /**
     */
    template bindFront(bind...)
    {
        template bindFront(args...)
        {
            alias templat!(bind, args) bindFront;
        }
    }

    /**
     */
    template bindBack(bind...)
    {
        template bindBack(args...)
        {
            alias templat!(args, bind) bindBack;
        }
    }
}

/// ditto
template Instantiate(string templat)
{
    alias Instantiate!(templateFun!templat) Instantiate;
}

unittest
{
}


private template Instantiator(args...)
{
    template Instantiator(alias templat)
    {
        alias Instantiate!templat.With!args Instantiator;
    }
}


/**
 */
template templateNot(alias pred)
{
    template templateNot(args...)
    {
        enum templateNot = !Instantiate!pred.With!args;
    }
}

unittest
{
}


/**
 */
template templateAnd(preds...)
{
    template templateAnd(args...)
    {
        alias allSatisfy!(Instantiator!args, preds) templateAnd;
    }
}

/// ditto
template templateOr(preds...)
{
    template templateOr(args...)
    {
        alias anySatisfy!(Instantiator!args, preds) templateOr;
    }
}

unittest
{
}


/**
 */
template templateCompose(templates...)
    if (templates.length >= 1)
{
    template templateCompose(args...)
    {
        static if (templates.length == 1)
        {
            alias Instantiate!(templates[0]).With!args templateCompose;
        }
        else
        {
            alias Instantiate!(templates[0])
                        .With!(Instantiate!(.templateCompose!(templates[1 .. $]))
                                     .With!args)
                  templateCompose;
        }
    }
}

unittest
{
}



//----------------------------------------------------------------------------//


/**
 */
template Select(bool condition, Then, Else)
{
    static if (cnodition)
    {
        alias Then Select;
    }
    else
    {
        alias Else Select;
    }
}

/// ditto
template Select(bool condition, Then, alias Else)
{
    static if (condition)
    {
        alias Then Select;
    }
    else
    {
        alias Else Select;
    }
}

/// ditto
template Select(bool condition, alias Then, Else)
{
    static if (condition)
    {
        alias Then Select;
    }
    else
    {
        alias Else Select;
    }
}

/// ditto
template Select(bool condition, alias Then, alias Else)
{
    static if (condition)
    {
        alias Then Select;
    }
    else
    {
        alias Else Select;
    }
}

unittest
{
}


/**
 */
A select(bool cond, A, B)(A a, lazy B b)
    if (cond)
{
    return a;
}

/// Ditto
B select(bool cond, A, B)(lazy A a, B b)
    if (!cond)
{
    return b;
}

unittest
{
}


//----------------------------------------------------------------------------//
// Filtering Predicates
//----------------------------------------------------------------------------//
/**
 */
template TypeOf(alias a)
{
    alias typeof(a) TypeOf;
}


/**
 */
template StringOf(T...)
{
    enum StringOf = T[0].stringof;
}


/**
    std.typetuple.staticLength ?
 */
template LengthOf(T...)
{
    enum size_t LengthOf = T.length;
}


/**
    alternation of built-in __traits(identifier, A)
 */
template Identifier(alias A)
{
    enum Identifier = __traits(identifier, A);
}
/// ditto
alias Identifier NameOf;
unittest
{
    int v;
    static assert(Identifier!v == __traits(identifier, v));
}


//----------------------------------------------------------------------------//
// Conditional Predicates
//----------------------------------------------------------------------------//
/**
 */
template isStruct(T)
{
    enum isStruct= is(T == struct);
}


/**
 */
template isUnion(T)
{
    enum isUnion= is(T == union);
}


/**
 */
template isClass(T)
{
    enum isClass= is(T == class);
}


/**
 */
template isInterface(T)
{
    enum isInterface = is(T == interface);
}


/**
 */
template isType(T)
{
    enum isType = true;
}
/// ditto
template isType(alias A)
{
    enum isType = false;
}


/**
 */
template isAlias(T)
{
    enum isAlias = false;
}
/// ditto
template isAlias(alias A)
{
    enum isAlias = true;
}

unittest
{
    alias Sequence!(int, long, 10, 2.0) S;

    alias staticFilter!(isType,  S) Rt;
    alias Sequence!(int, long) At;
    static assert(is(Rt == At));

    alias staticFilter!(isAlias, S) Ra;
    alias Sequence!(10, 2.0) Aa;
//  static assert(Ra == Aa);
    static assert(Ra[0] == Aa[0]);
    static assert(Ra[1] == Aa[1]);
}


version(none)
{
/**
 */
template isInstantiatedWith(alias T, alias X)
{
    static if (is(T))   // use isType ?
    {
        static assert(0);   // doesn't work.

//      pragma(msg, "> ", T, "[" ~ T.mangleof ~ "], ", X);
        static if (is(Unqual!T Unused : X!Specs, Specs...))
        {
            // doesn't work.
            // -> mangleof使えば可能か？
            enum isInstantiatedWith = true;
        }
        else
        {
            enum isInstantiatedWith = false;
        }
    }
    else
    {
//      pragma(msg, "$ ", T, ", ", X);
        static if (__traits(compiles, Identifier!T))
        {
            enum isInstantiatedWith =
                chompPrefix(
                    Identifier!T,
                    "__T" ~
                    to!string(Identifier!X.length) ~
                    Identifier!X)
                != Identifier!T;
        }
        else
        {
            enum isInstantiatedWith = false;
        }
    }
}

version(unittest)
{
    template TestTemplate(T...)
    {
    }
    static assert(isInstantiatedWith!(TestTemplate!int, TestTemplate));


    struct TestType(T...)
    {
    }
//  pragma(msg, is(typeof(TestType!int)));
//  static assert(isInstantiatedWith!(TestType!int, TestType));
}
}


//----------------------------------------------------------------------------//
// Sequences
//----------------------------------------------------------------------------//

template VirtualFunctionsOfImpl(T, string name)
{
    alias Sequence!(__traits(getVirtualFunctions, T, name)) Result;
}
/**
    does not reduce overloads
    Parameter:
        name :  specified member name.
                if it is empty string, all of virtual-functions on T returns.
 */
template VirtualFunctionsOf(T, string name="")
{
    static if (name == "")
    {
        alias staticMap!(
            Instantiate!(
                Instantiate!VirtualFunctionsOfImpl.bindFront!T
            ).Returns!"Result",
            Sequence!(__traits(allMembers, T))
        ) VirtualFunctionsOf;
    }
    else
    {
        alias VirtualFunctionsOfImpl!(T, name).Result VirtualFunctionsOf;
    }
}


private template staticIndexOfIfImpl(alias pred, seq...)
{
    enum len = seq.length;
    enum len2 = staticFindIf!(pred, seq).length;
    static if (len2 == 0)
    {
        enum int Result = -1;
    }
    else
    {
        enum int Result = len - len2;
    }
}
template staticIndexOfIf(alias pred, seq...)
{
    enum staticIndexOfIf = staticIndexOfIfImpl!(pred, seq).Result;
}


//----------------------------------------------------------------------------//
// Mixins
//----------------------------------------------------------------------------//

/**
    both of template-mixin or string-mixin
 */
template mixinAll(mixins...)
{
    static if (mixins.length == 1)
    {
        static if (is(typeof(mixins[0]) == string))
        {
            mixin(mixins[0]);
        }
        else
        {
            alias mixins[0] it;
            mixin it;
        }
    }
    else static if (mixins.length >= 2)
    {
        mixin mixinAll!(mixins[ 0 .. $/2]);
        mixin mixinAll!(mixins[$/2 .. $ ]);
    }
}




//----------------------------------------------------------------------------//
// Traits
//----------------------------------------------------------------------------//


/**
 */
enum FunctionStorageClass : uint
{
    /**
     * These flags can be bitwise OR-ed together to represent complex storage
     * class.
     */
    NONE            = 0,
    SHARED          = 0b0001,
    CONST           = 0b0010,
    IMMUTABLE       = 0b0100,
    SHARED_CONST    = SHARED | CONST,
}
/**
 */
template functionStorageClass(func...) if (func.length==1)
{
    static if (is(FunctionTypeOf!(func) F))
        enum uint functionStorageClass =
            (is(F == const    ) ? FunctionStorageClass.CONST     : 0) |
            (is(F == shared   ) ? FunctionStorageClass.SHARED    : 0) |
            (is(F == immutable) ? FunctionStorageClass.IMMUTABLE : 0);
    else
        static assert(0, "argument is not a function");
}

///
enum ParameterStorageClasses : ParameterStorageClass
{
    NONE = ParameterStorageClass.none,  //dummy
}

///
enum FunctionStorageClasses : FunctionStorageClass
{
    NONE = FunctionStorageClass.NONE,   //dummy
}


/**
    Specialized template for ParameterStorageClass
 */
template StringOf(ParameterStorageClass pstc)
{
    static if (pstc & ParameterStorageClass.scope_) enum StringOf = "scope ";
    static if (pstc & ParameterStorageClass.out_  ) enum StringOf = "out ";
    static if (pstc & ParameterStorageClass.ref_  ) enum StringOf = "ref ";
    static if (pstc & ParameterStorageClass.lazy_ ) enum StringOf = "lazy ";
}

/**
    Specialized template for FunctionAttribute
 */
template StringOf(FunctionAttribute attr)
{
    static if (attr == FunctionAttribute.pure_    ) enum StringOf = "pure ";
    static if (attr == FunctionAttribute.nothrow_ ) enum StringOf = "nothrow ";
    static if (attr == FunctionAttribute.ref_     ) enum StringOf = "ref ";
    static if (attr == FunctionAttribute.property) enum StringOf = "@property ";
    static if (attr == FunctionAttribute.trusted ) enum StringOf = "@trusted ";
    static if (attr == FunctionAttribute.safe    ) enum StringOf = "@safe ";
}

/**
    Specialized template for FunctionStorageClass
 */
template StringOf(FunctionStorageClass pstc)
{
    static if (pstc & FunctionStorageClass.NONE     ) enum StringOf = "";
    static if (pstc & FunctionStorageClass.CONST    ) enum StringOf = "const ";
    static if (pstc & FunctionStorageClass.SHARED   ) enum StringOf = "shared ";
    static if (pstc & FunctionStorageClass.IMMUTABLE) enum StringOf = "immutable ";
}

/**
    Specialized template for ParameterStorageClasses
 */
template StringOf(ParameterStorageClasses pstcs)
{
    enum StringOf =
        DeclareTemplate!q{
            alias Identity!(args[0]) pstcs;
            alias Identity!(args[1]) i;
            static if (pstcs == 0)
                enum Result = "";
            else static if (pstcs & (1<<i))
                enum Result =
                    StringOf!(cast(ParameterStorageClass)(pstcs & (1<<i)))
                    ~ Self!(cast(ParameterStorageClasses)(pstcs & ~(1<<i)), i+1).Result;
            else
                enum Result =
                    Self!(cast(ParameterStorageClasses)(pstcs), i+1).Result;
    }.With!(pstcs, 0).Result;
}

/**
    Specialized template for FunctionStorageClasses
 */
template StringOf(FunctionStorageClasses fstcs)
{
    enum StringOf =
        DeclareTemplate!q{
            alias Identity!(args[0]) fstcs;
            alias Identity!(args[1]) i;
            static if (fstcs == 0)
                enum Result = "";
            else static if (fstcs & (1<<i))
                enum Result =
                    StringOf!(cast(FunctionStorageClass)(fstcs & (1<<i)))
                    ~ Self!(cast(FunctionStorageClasses)(fstcs & ~(1<<i)), i+1).Result;
            else
                enum Result =
                    Self!(cast(FunctionStorageClasses)(fstcs), i+1).Result;
        }.With!(fstcs, 0).Result;
}


///
enum FunctionAttributes : FunctionAttribute
{
    NONE = FunctionAttribute.none,  //dummy
}

/**
    Specialized template for FunctionAttributes
*/
template StringOf(FunctionAttributes attrs)
{
    enum StringOf =
        DeclareTemplate!q{
            alias Identity!(args[0]) attrs;
            alias Identity!(args[1]) i;
            static if (attrs == 0)
                enum Result = "";
            else static if (attrs & (1<<i))
                enum Result =
                    .StringOf!(cast(FunctionAttribute)(attrs & (1<<i)))
                    ~ Self!(cast(FunctionAttributes)(attrs & ~(1<<i)), i+1).Result;
            else
                enum Result =
                    Self!(cast(FunctionAttributes)(attrs), i+1).Result;
        }.With!(attrs, 0).Result;
}


/**
 */
template ParameterInfo(alias Param)
{
    alias Identity!(Param.at!0) Type;

    enum ParameterStorageClasses storageClass =
        cast(ParameterStorageClasses)(Param.at!1);
    enum isScope = (storageClass & ParameterStorageClass.scope_) != 0;
    enum isOut   = (storageClass & ParameterStorageClass.out_  ) != 0;
    enum isRef   = (storageClass & ParameterStorageClass.ref_  ) != 0;
    enum isLazy  = (storageClass & ParameterStorageClass.lazy_ ) != 0;
}


/**
 */
template FunctionTypeInfo(A...) if (is(FunctionTypeOf!A))
{
    alias FunctionTypeOf!A F;

    alias .ReturnType!F ReturnType;

    alias staticMap!(
        ParameterInfo,
        staticZip!(
            Wrap!(ParameterTypeTuple!F),
            Wrap!(ParameterStorageClassTuple!F))) Parameters;

    enum FunctionStorageClasses storageClass =
        cast(FunctionStorageClasses)(functionStorageClass!F);
    enum isConst        = (storageClass & FunctionStorageClass.CONST       ) != 0;
    enum isShared       = (storageClass & FunctionStorageClass.SHARED      ) != 0;
    enum isSharedConst  = (storageClass & FunctionStorageClass.SHARED_CONST) != 0;
    enum isImmutable    = (storageClass & FunctionStorageClass.IMMUTABLE   ) != 0;

    enum FunctionAttributes attributes =
        cast(FunctionAttributes)(functionAttributes!F);
    enum isPure     = (attributes & FunctionAttribute.pure_    ) != 0;
    enum isNothrow  = (attributes & FunctionAttribute.nothrow_ ) != 0;
    enum isRef      = (attributes & FunctionAttribute.ref_     ) != 0;
    enum isProperty = (attributes & FunctionAttribute.property) != 0;
    enum isTrusted  = (attributes & FunctionAttribute.trusted ) != 0;
    enum isSafe     = (attributes & FunctionAttribute.safe    ) != 0;
}

unittest
{
    alias ParameterStorageClass PStC;
    alias FunctionAttribute FA;

    void test(int, scope int, out int, ref int, lazy int) nothrow @safe { }
    alias FunctionTypeInfo!test T;

    static assert(is(T.ReturnType == void));

    alias Identity!(T.Parameters[0]) P0;
    alias Identity!(T.Parameters[1]) P1;
    alias Identity!(T.Parameters[2]) P2;
    alias Identity!(T.Parameters[3]) P3;
    alias Identity!(T.Parameters[4]) P4;
    static assert(is(P0.Type == int));
    static assert(is(P1.Type == int));
    static assert(is(P2.Type == int));
    static assert(is(P3.Type == int));
    static assert(is(P4.Type == int));

    static assert(P0.storageClass == PStC.none);
    static assert(P1.storageClass == PStC.scope_);
    static assert(P2.storageClass == PStC.out_);
    static assert(P3.storageClass == PStC.ref_);
    static assert(P4.storageClass == PStC.lazy_);
    static assert(StringOf!(T.Parameters[0].storageClass) == "");
    static assert(StringOf!(T.Parameters[1].storageClass) == "scope ");
    static assert(StringOf!(T.Parameters[2].storageClass) == "out ");
    static assert(StringOf!(T.Parameters[3].storageClass) == "ref ");
    static assert(StringOf!(T.Parameters[4].storageClass) == "lazy ");

    static assert(T.attributes == (FA.safe | FA.nothrow_));
    static assert(StringOf!(T.attributes) == "nothrow @safe ");
}


//----------------------------------------------------------------------------//
// Declarations
//----------------------------------------------------------------------------//

/**
 */
template Declare(T, string name, init...)
{
//  import std.traits : isSomeFunction, FunctionTypeOf;
//
//  static if (isSomeFunction!T)
//  {
//      mixin DeclareFunction!(FunctionTypeOf!T, name, init);
//  }
//  else
//  {
        static if (init.length == 0)
        {
            mixin("T " ~ name ~ ";");
        }
        static if (init.length == 1)
        {
            mixin("T " ~ name ~ " = init[0];");
        }
//  }
}
/// ditto
template Declare(alias wrap)
{
    mixin Declare!(wrap.Expand);
}

unittest
{
    mixin Declare!(int, "a");
    assert(a == int.init);
    a = 10;

    mixin Declare!(double, "b", 10.0);
    assert(b == 10.0);
    b = 20.0;

    mixin Declare!(Wrap!(string, "c", "test"));
    assert(c == "test");
}


/**
 */
template DeclareFunction(F, string name, string code)
{
private:
    alias FunctionTypeInfo!F FTI;
    alias staticMap!(
        Instantiate!q{ a.at!0 ~ a.at!1 ~ " a" ~ to!string(a.at!2) }.With,
        staticZip!(
            Wrap!(
                staticMap!(
                    Instantiate!q{ StringOf!(a.storageClass) }.With,
                    FTI.Parameters)),
            Wrap!(
                staticMap!(
                    Instantiate!q{ StringOf!(a.Type) }.With,
                    FTI.Parameters)),
            Wrap!(
                staticIota!(0, FTI.Parameters.length))
        )
    ) ParamStrings;

    // workaround for std.string.join cannot CFTE.
    private template Join(alias words, string sep)
    {
        static if (words.length == 0)
            enum Join = "";
        else static if (words.length == 1)
            enum Join = words.Expand[0];
        else
            enum Join = words.Expand[0] ~ sep ~ Join!(words.drop!1, sep);
    }

public:
    import util.metastrings_expand;
    mixin(mixin(expand!q{
        ${StringOf!(FTI.storageClass)}
        ${StringOf!(FTI.attributes)}
        FTI.ReturnType
        ${name}
        (${Join!(Wrap!ParamStrings, ", ")})
        {
            alias Sequence!(${
                Join!(Wrap!(
                    staticMap!(
                        Instantiate!` "a" ~ to!string(a) `.With,
                        staticIota!(0, FTI.Parameters.length))), ", ")
                }) args;
            mixin(code);
        }
    }));
}

unittest
{
    static class C
    {
        alias int function(scope int, ref double) F;

        int value = 10;
        mixin DeclareFunction!(F, "f", q{ a1      *= 2; return value*2; });
        mixin DeclareFunction!(F, "g", q{ args[1] *= 3; return value*3; });
    }

    auto c = new C();
    double v = 1.0;
    assert(c.f(1, v) == 20);  assert(v == 2.0);
    assert(c.g(1, v) == 30);  assert(v == 6.0);
}
unittest
{
    static class C
    {
        int f()             { return 10; }
        int g() const       { return 20; }
        int h() shared      { return 30; }
        int i() shared const{ return 40; }
        int j() immutable   { return 50; }

        // for overload set
        mixin DeclareFunction!(typeof(f), "a1", q{ return f(); });  alias a1 a;
        mixin DeclareFunction!(typeof(g), "a2", q{ return g(); });  alias a2 a;
        mixin DeclareFunction!(typeof(h), "a3", q{ return h(); });  alias a3 a;
        mixin DeclareFunction!(typeof(i), "a4", q{ return i(); });  alias a4 a;
        mixin DeclareFunction!(typeof(j), "a5", q{ return j(); });  alias a5 a;
    }
    auto           c = new C();
    const         cc = new C();
    shared        sc = new shared(C)();
    shared const scc = new shared(const(C))();
    immutable     ic = new immutable(C)();
    assert(  c.a() == 10);
    assert( cc.a() == 20);
    assert( sc.a() == 30);
    assert(scc.a() == 40);
    assert( ic.a() == 50);
}


/**
    Self    declared template itself
    args    tuple of template parameters
 */
private template DeclareTemplateImpl(string def)
{
    template Self(args...)
    {
        mixin(def);
    }
    alias Instantiate!Self Result;
}
template DeclareTemplate(string def)    // ditto
{
    alias DeclareTemplateImpl!def.Result DeclareTemplate;
}


/**
 */
template DelegateTypeOf(F) if (is(FunctionTypeOf!F == function))
{
    alias
        DeclareTemplate!q{
            struct generate
            {
                mixin DeclareFunction!(args[0], "dummy", q{
                    static if (!is(typeof(return) == void))
                        return typeof(return).init;
                });
            }
            alias typeof(&((new generate()).dummy)) Result;
        }.With!(FunctionTypeOf!F).Result
        DelegateTypeOf;
}
unittest
{
    alias void function(int, float) @safe F;
    static assert(is(DelegateTypeOf!F == void delegate(int, float) @safe));
}


