<br>
# Tricks.jl
## Abusing backedges for Fun and Profit
<br>
<br>
<br>
.row[
.col[
    **Frames White** <br>
    Research Software Engineering Group Lead
]
.col[
**JuliaCon 2021**
.image-60[![InveniaLabs](https://www.invenia.ca/wp-content/themes/relish_theme/img/labs-logo.png)]    
] 
]

```@setup demo
using Tricks
using BenchmarkTools
using InteractiveUtils
```

---

### History and Credit

 - Was initially created at JuliaCon 2019 (Baltimore) Hackathon.
 - With a lot of help from Nathan Daly.
 - Since then Mason Protter has made some nice additions and good clean-up.

.funfact[It was proposed to add the key functionality `static_hasmethod` to Base.
See PR [#32732](https://github.com/JuliaLang/julia/pull/32732).

Jameson said:
 - This would be more cleanly implemented with a `tfunc`.
 - If we added this feature, people would use it, and he thinks that:
    - using this would make invalidations a way bigger problem.
    - the kind of coding style this allows for is bad.
]

--- 

### What can Tricks.jl do?

`static_hasmethod` is just like `hasmethod` but it resolves at compile-time.

```@example demo
using Tricks: static_hasmethod

struct Iterable end;
struct NonIterable end;

function iterableness_dynamic(::Type{T}) where T
    hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()
end;

function iterableness_static(::Type{T}) where T
    static_hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()
end;

nothing #hide
```

---

### This can be used for Tim Holy traits

```@example demo
my_print(x::T) where T = my_print(iterableness_static(T), x)

my_print(::Iterable, x) = println(join(x, ", ", " & "))
my_print(::Any, x) = println(x);
nothing #hide
```

```@example demo
my_print([1,2,3])
```

```@example demo
my_print(Int)
```

---

## static_hasmethod means this resolves at compile-time

```@example demo
@code_typed my_print([1,2,3])
```
---
## In-contrast normal hasmethod:

```@example demo
my_print_dyn(x::T) where T = my_print(iterableness_dynamic(T), x)
@code_typed my_print_dyn([1,2,3])
```

---

# So how does it work?


♯265

---

## Background Terminology

 - **Function:** a (generally named) callable thing that takes some arguments.
     - It can have many *methods* defined for it
 - **Method:** a particular piece of written code that takes some arguments of particular types and executes on them.
     - It will have a *method instances* generated for it, for each combination of concrete input types.
-  **Method Instance:** a particular piece of compiled code that operates on concretely typed inputs, generated during specialization.


---

## Background: what is a back-edge?
A back-edge is a link from a _method instance_ to all _method instances_ that use it. 

Consider:
```@example demo
bar(x) = 10 + x
foo(x) = 2*bar(x)

foo(3)
```
That compiled a method instance for `bar(::Int)`, and static dispatched to it from `Foo(::Int)`.

```@example demo
bar(x::Integer) = 100 + x

foo(3)
```

## Background: invalidation
A back-edge is a link from a _method instance_ to all\* _method instances_ that use it. 

When a new more specific method is defined, or when a method is redefined we need to recompile all code that has a *static* dispatch to it.

To do this we go through and invalidate everything that we have a back-edge to from our old method instance.
And then everything that has a back-edge from that, and so forth.

Invalidated method instances are recompiled before their next use.
## Background: back-edges and method errors
A back-edge is a link from a _method instance_ to all _method instances_ that use it.

When a MethodError occurs, what is actually compiled effectively has a back-edge not from a method instance, but from the spot in the Method Table where one would occur, so we can still invalidate that when we define the missing method. 

---

## Background: Backedges and generated functions

Normally back-edges are inserted automatically by the compiler.
But they are not for the part of generated function that generates the code.

However, if the generated code is lowered IR CodeInfo -- like Zygote.jl or Cassette.jl make use of -- then you are allowed to attach back-edges manually.
This feature was added so the Zygote could invalidate the derivative methods when the original methods were redefined.

---

## How `static_hasmethod` uses backedges

`static_hasmethod(iterate, Tuple{Foo})` works as follows:
1. run `methods(iterate, Tuple{Foo})`
2. If return lowered IR for the literal `false` or `true` depending on if empty or not
3. Attach backedges to the method table if `false` or to every method instance of every method if `true`
4. If a method is defined (if `false`) or deleted (if `true`), this will be invalidated


## Summary
 - Tricks.jl makes some extra information actually resolve at compile-time.
 - It does this by forcing everything that uses that information to recompile whenever it changes.
 - to do this it (ab)uses the backedge system
 - the back-edge system lists for every method-instance all places it is (statically) dispatched to
 - it is used to trigger recompilation of all callers.
 - Tricks.jl manually connects these back-edges to it's `static_` functions which return literals, and their callers
 - So they recompile to return different literals when the values have changed.

