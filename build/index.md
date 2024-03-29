
<br>






# Tricks.jl






## Abusing backedges for Fun and Profit


<br> <br> <br> .row[ .col[     **Frames White** <br>     Research Software Engineering Group Lead ] .col[ **JuliaCon 2022** .image-60[![InveniaLabs](https://www.invenia.ca/wp-content/themes/relish_theme/img/labs-logo.png)]     ]  ]




---






### History and Credit


  * Was initially created at JuliaCon 2019 (Baltimore) Hackathon.
  * With a lot of help from Nathan Daly.
  * Since then Mason Protter has made some nice additions and good clean-up.


---






### What can Tricks.jl do?


`static_hasmethod` is just like `hasmethod` but it resolves at compile-time.


```julia
using Tricks: static_hasmethod

struct Iterable end;
struct NonIterable end;

function iterableness_dynamic(::Type{T}) where T
    hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()
end;

function iterableness_static(::Type{T}) where T
    static_hasmethod(iterate, Tuple{T}) ? Iterable() : NonIterable()
end;
```


---






### This can be used for Tim Holy traits


```julia
my_print(x::T) where T = my_print(iterableness_static(T), x)

my_print(::Iterable, x) = println(join(x, ", ", " & "))
my_print(::Any, x) = println(x);
```


```julia
my_print([1,2,3])
```


```
1, 2 & 3
```


```julia
my_print(Int)
```


```
Int64
```


---






## static_hasmethod means this resolves at compile-time


```julia
@code_typed my_print([1,2,3])
```


```
CodeInfo(
1 ─ %1 = invoke Base.:(var"#sprint#426")(nothing::Nothing, 0::Int64, sprint::typeof(sprint), join::Function, x::Vector{Int64}, ", "::Vararg{Any}, " & ")::String
│   %2 = invoke Main.ex-demo.println(%1::String)::Nothing
└──      return %2
) => Nothing
```


---






## In-contrast normal hasmethod:


```julia
my_print_dyn(x::T) where T = my_print(iterableness_dynamic(T), x)
@code_typed my_print_dyn([1,2,3])
```


```
CodeInfo(
1 ─       invoke Base.to_tuple_type(Tuple{Vector{Int64}}::Any)::Type{Tuple{Vector{Int64}}}
│   %2  = $(Expr(:foreigncall, :(:jl_gf_invoke_lookup), Any, svec(Any, UInt64), 0, :(:ccall), Tuple{typeof(iterate), Vector{Int64}}, 0xffffffffffffffff, 0xffffffffffffffff))::Any
│   %3  = (%2 === Base.nothing)::Bool
│   %4  = Core.Intrinsics.not_int(%3)::Bool
└──       goto #3 if not %4
2 ─       goto #4
3 ─       goto #4
4 ┄ %8  = φ (#2 => $(QuoteNode(Main.ex-demo.Iterable())), #3 => $(QuoteNode(Main.ex-demo.NonIterable())))::Union{Main.ex-demo.Iterable, Main.ex-demo.NonIterable}
│   %9  = (isa)(%8, Main.ex-demo.Iterable)::Bool
└──       goto #6 if not %9
5 ─ %11 = invoke Base.:(var"#sprint#426")(nothing::Nothing, 0::Int64, sprint::typeof(sprint), join::Function, x::Vector{Int64}, ", "::Vararg{Any}, " & ")::String
│   %12 = invoke Main.ex-demo.println(%11::String)::Nothing
└──       goto #9
6 ─ %14 = (isa)(%8, Main.ex-demo.NonIterable)::Bool
└──       goto #8 if not %14
7 ─ %16 = invoke Main.ex-demo.println(x::Vector{Int64})::Nothing
└──       goto #9
8 ─       Core.throw(ErrorException("fatal error in type inference (type bound)"))::Union{}
└──       unreachable
9 ┄ %20 = φ (#5 => %12, #7 => %16)::Nothing
└──       return %20
) => Nothing
```


---






# So how does it work?


♯265


---






## Background Terminology


  * **Function:** a (generally named) callable thing that takes some arguments.

      * It can have many *methods* defined for it
  * **Method:** a particular piece of written code that takes some arguments of particular types and executes on them.

      * It will have a *method instances* generated for it, for each combination of concrete input types.
  * **Method Instance:** a particular piece of compiled code that operates on concretely typed inputs, generated during specialization.


---






## Background: what is a back-edge?


.funfact[A back-edge is a link from a *method instance* to all *method instances* that use it via *static dispatch*.]


```julia
bar(x) = 10 + x
foo(x) = 2*bar(x)

foo(3)
```


```
26
```


That compiled a method instance for `bar(::Int)`, and static dispatched to it from `foo(::Int)`.


```julia
bar(x::Integer) = 100 + x

foo(3)
```


```
206
```


---






## Background: invalidation


.funfact[A back-edge is a link from a *method instance* to all *method instances* that use it via *static dispatch*.] 


When a new more specific method is defined, or when a method is redefined we need to recompile all code that has a *static* dispatch to it.


To do this we go through and invalidate everything that we have a back-edge to from our old method instance. And then everything that has a back-edge from that, and so forth.


Invalidated method instances are recompiled before their next use.


---






## Background: back-edges and method errors


.funfact[A back-edge is a link from a *method instance* to all *method instances* that use it via *static dispatch*.]


When a MethodError occurs, what is actually compiled effectively has a back-edge not from a method instance, but from the spot in the Method Table where one would occur, so we can still invalidate that when we define the missing method. 


---






## Background: Manually adding backedges


Normally back-edges are inserted automatically by the compiler.


However, if the generated code is lowered IR CodeInfo – like Zygote.jl or Cassette.jl make use of – then you are allowed to attach back-edges manually.


This feature was added so the Zygote could invalidate the derivative methods when the original methods were redefined.


---






## How `static_hasmethod` uses backedges


<br> .image-80[![](assets/static_hasmethod.drawio.svg)]


---






## Summary


  * Tricks.jl makes some extra information actually resolve at compile-time.
  * It does this by forcing everything that uses that information to recompile whenever it changes.
  * to do this it (ab)uses the backedge system
  * the back-edge system lists for every method-instance all places it is (statically) dispatched to
  * it is used to trigger recompilation of all callers.
  * Tricks.jl manually connects these back-edges to it's `static_` functions which return literals, and their callers
  * So they recompile to return different literals when the values have changed.

