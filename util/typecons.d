/**
 * from Boost.Interfaces
 * Written by Kenji Hara(9rnsr)
 * License: Boost License 1.0
 */
module util.typecons;

import std.traits, std.typecons, std.typetuple;
import std.functional;

//import meta;
//alias meta.staticMap staticMap;
//alias meta.isSame isSame;
//alias meta.allSatisfy allSatisfy;

import std.traits;

import util.meta;
//import metastrings_expand;
alias util.meta.allSatisfy allSatisfy;
alias util.meta.staticMap staticMap;
alias util.meta.isSame isSame;

/*private*/ interface Structural
{
    Object _getSource();
}

private template AdaptTo(Targets...)
    if (allSatisfy!(isInterface, Targets))
{
    alias staticUniq!(staticMap!(VirtualFunctionsOf, Targets)) TgtFuns;

    alias util.meta.NameOf NameOf;
    alias util.meta.TypeOf TypeOf;

    template CovariantSignatures(S)
    {
        alias VirtualFunctionsOf!S SrcFuns;

        template isExactMatch(alias a)
        {
            enum isExactMatch =
                     isSame!(NameOf!(a.Expand[0]), NameOf!(a.Expand[1]))
                  && isSame!(TypeOf!(a.Expand[0]), TypeOf!(a.Expand[1]));
        }
        template isCovariantMatch(alias a)
        {
            enum isCovariantMatch =
                             isSame!(NameOf!(a.Expand[0]), NameOf!(a.Expand[1]))
                 && isCovariantWith!(TypeOf!(a.Expand[0]), TypeOf!(a.Expand[1]));
        }

        template InheritsSrcFnFrom(size_t i)
        {
            alias staticCartesian!(Wrap!SrcFuns, Wrap!(TgtFuns[i])) Cartesian;

            enum int j_ = staticIndexOfIf!(isExactMatch, Cartesian);
            static if( j_ == -1 )
                enum int j = staticIndexOfIf!(isCovariantMatch, Cartesian);
            else
                enum int j = j_;

            static if( j == -1 )
                alias Sequence!() Result;
            else
                alias Sequence!(SrcFuns[j]) Result;
        }
        alias staticMap!(
            TypeOf,
            staticMap!(
                Instantiate!InheritsSrcFnFrom.Returns!"Result",
                staticIota!(0, TgtFuns.length) //workaround @@@BUG4333@@@
            )
        ) Result;
    }

    template hasRequireMethods(S)
    {
        enum hasRequireMethods =
            CovariantSignatures!S.Result.length == TgtFuns.length;
    }

    class AdaptedImpl(S) : Structural
    {
        S source;

        this(S s){ source = s; }

        final Object _getSource()
        {
            return cast(Object)source;
        }
    }
    final class Impl(S) : AdaptedImpl!S, Targets
    {
    private:
        alias CovariantSignatures!S.Result CoTypes;

        this(S s){ super(s); }

    public:
        template generateFun(size_t n)
        {
            enum N = to!string(n);
            enum generateFun = `
                mixin DeclareFunction!(
                    CoTypes[`~N~`], // covariant
                    NameOf!(TgtFuns[`~N~`]),
                    "return source." ~ NameOf!(TgtFuns[`~N~`]) ~ "(args);"
                );
            `;
        }
        mixin mixinAll!(
            staticMap!(
                generateFun,
                staticIota!(0, TgtFuns.length)));   //workaround @@@BUG4333@@@
    }
}


/**
*/
template structuralUpCast(Supers...)
{
    /**
    */
    auto structuralUpCast(D)(D s)
        if (allSatisfy!(isInterface, Supers))
    {
        static if (Supers.length == 1)
        {
            alias Supers[0] S;
            static if (is(D : S))
            {
                //strict upcast
                return cast(S)(s);
            }
            else static if (AdaptTo!Supers.hasRequireMethods!D)
            {
                // structural upcast
                return cast(S)(new AdaptTo!Supers.Impl!D(s));
            }
        }
        else static if (AdaptTo!Supers.hasRequireMethods!D)
        {
            return new AdaptTo!Supers.Impl!D(s);
        }
        else
        {
            static assert(0,
                D.stringof ~ " does not have structural conformance "
                "to " ~ Supers.stringof ~ ".");
        }
    }
}

/**
*/
template structuralDownCast(D)
{
    /**
    */
    D structuralDownCast(S)(S s)
    {
        static if (is(D : S))
        {
            //strict downcast
            return cast(D)(s);
        }
        else
        {
            // structural downcast
            Object o = cast(Object)s;
            do
            {
                if (auto a = cast(Structural)o)
                {
                    auto d = cast(D)(o = a._getSource());
                    if (d)
                        return d;
                }
                else
                {
                    auto d = cast(D)o;
                    if (d)
                        return d;
                    else
                        break;
                }
            } while (o);
            return null;
        }
    }
}

/**
*/
template structuralCast(To...)
{
    auto structuralCast(From)(From a)
    {
        static if (To.length == 1)
        {
            auto to = structuralDownCast!To(a);
            static if (allSatisfy!(isInterface, To))
            {
                if (!to)
                    return structuralUpCast!To(a);
            }
            return to;
        }
        else
        {
            static if (allSatisfy!(isInterface, To))
            {
                return structuralUpCast!To(a);
            }
        }
    }
}

//alias structuralUpCast adaptTo;
//alias structuralDownCast getAdapted;
alias structuralCast adaptTo;
alias structuralCast getAdapted;

unittest
{
    interface Quack
    {
        int quack();
        int height();
    }
    static class Duck : Quack
    {
        int quack(){return 10;}
        int height(){return 100;}
    }
    static class Human
    {
        int quack(){return 20;}
        int height(){return 0;}
    }
    interface Flyer
    {
        int height();
    }

    Quack q;
    Duck  d = new Duck(), d2;
    Human h = new Human(), h2;
    Flyer f;

    //strict upcast
    q = structuralUpCast!Quack(d);
    assert(q is d);
    assert(q.quack() == 10);

    //strict downcast
    d2 = structuralDownCast!Duck(q);
    assert(d2 is d);

    //structural upcast
    q = structuralUpCast!Quack(h);
    assert(q.quack() == 20);

    //structural downcast
    h2 = structuralDownCast!Human(q);
    assert(h2 is h);

    //structural upcast(multi-level)
    q = structuralUpCast!Quack(h);
    f = structuralUpCast!Flyer(q);
    assert(f.height() == 0);

    //strucural downcast(single level)
    q = structuralDownCast!Quack(f);
    h2 = structuralDownCast!Human(q);
    assert(h2 is h);

    //strucural downcast(multi level)
    h2 = structuralDownCast!Human(f);
    assert(h2 is h);
}

unittest
{
    //class A
    //limitation: can't use nested class
    static class A
    {
        int draw(){ return 10; }
        //Object _getSource();
        //limitation : can't contain this name
    }
    static class AA : A
    {
        override int draw(){ return 100; }
    }
    static class B
    {
        int draw(){ return 20; }
        int reflesh(){ return 20; }
    }
    static class X
    {
        void undef(){}
    }
    interface Drawable
    {
        int draw();
    }
    interface Refleshable
    {
        int reflesh();
        final int stop(){ return 0; }
        static int refleshAll(){ return 100; }
    }

    A a = new A();
    B b = new B();
    Drawable d;
    Refleshable r;
    {
        auto m = adaptTo!Drawable(a);
        d = m;
        assert(d.draw() == 10);
        assert(getAdapted!A(d) is a);
        assert(getAdapted!B(d) is null);

        d = adaptTo!Drawable(b);
        assert(d.draw() == 20);
        assert(getAdapted!A(d) is null);
        assert(getAdapted!B(d) is b);

        AA aa = new AA();
        d = adaptTo!Drawable(cast(A)aa);
        assert(d.draw() == 100);

        static assert(!__traits(compiles,
            d = adaptTo!Drawable(new X())));

    }
    {
        auto m = adaptTo!(Drawable, Refleshable)(b);
        d = m;
        r = m;
        assert(m.draw() == 20);
        assert(d.draw() == 20);
        assert(m.reflesh() == 20);
        assert(r.reflesh() == 20);

        // call final/static function in interface
        assert(m.stop() == 0);
        assert(m.refleshAll() == 100);
        assert(typeof(m).refleshAll() == 100);
    }

}

unittest
{
    static class A
    {
        int draw()              { return 10; }
        int draw(int v)         { return 11; }

        int draw() const        { return 20; }
        int draw() shared       { return 30; }
        int draw() shared const { return 40; }
        int draw() immutable    { return 50; }

    }

    interface Drawable
    {
        int draw();
        int draw() const;
        int draw() shared;
        int draw() shared const;
        int draw() immutable;
    }
    interface Drawable2
    {
        int draw(int v);
    }

    auto  a = new A();
    auto sa = new shared(A)();
    auto ia = new immutable(A)();
    {
                     Drawable   d = adaptTo!(             Drawable )(a);
        const        Drawable  cd = adaptTo!(       const(Drawable))(a);
        shared       Drawable  sd = adaptTo!(shared      (Drawable))(sa);
        shared const Drawable scd = adaptTo!(shared const(Drawable))(sa);
        immutable    Drawable  id = adaptTo!(immutable   (Drawable))(ia);
        assert(  d.draw() == 10);
        assert( cd.draw() == 20);
        assert( sd.draw() == 30);
        assert(scd.draw() == 40);
        assert( id.draw() == 50);
    }
    {
        Drawable2 d = adaptTo!Drawable2(a);
        static assert(!__traits(compiles, d.draw()));
        assert(d.draw(0) == 11);
    }
}

unittest
{
    interface Drawable
    {
        long draw();
        int reflesh();
    }
    static class A
    {
        int draw(){ return 10; }            // covariant return types
        int reflesh()const{ return 20; }    // covariant storage classes
    }

    auto a = new A();
    //auto d = adaptTo!Drawable(a); // supports return-typ/storage-class covariance
    //assert(d.draw() == 10);
    //assert(d.reflesh() == 20);
/+  static assert(isCovariantWith!(typeof(A.draw), typeof(Drawable.draw)));
    static assert(is(typeof(a.draw()) == int));
    static assert(is(typeof(d.draw()) == long));

    static assert(isCovariantWith!(typeof(A.reflesh), typeof(Drawable.reflesh)));
    static assert( is(typeof(a.reflesh) == const));
    static assert(!is(typeof(d.reflesh) == const));
+/
}
