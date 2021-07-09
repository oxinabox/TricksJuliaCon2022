<br>
# ExprTools.jl
## Meta-programming from reflection
<br>
<br>
<br>
.row[
.col[
    **Lyndon White** <br>
    Research Software Engineering Group Lead
]
.col[
**JuliaCon 2021**
.image-60[![InveniaLabs](https://www.invenia.ca/wp-content/themes/relish_theme/img/labs-logo.png)]    
] 
]

```@setup demo
using ExprTools
using InteractiveUtils
using SparseArrays
```

---

### History

 - Was initially using `MacroTools.splitdef`, `MacroTools.combinedef` (credit Cédric St-Jean).
 - Curtis Vogt noticed some edge cases, and did most of the work writing `ExprTools.splitdef` at start of 2020.
 - At end of 2020 I added `signature` which is most of what we will talk about today.

.funfact[There are a lot of edge cases, so we needed a lot of tests.

 - about 590 tests
 - about 1270 lines of test code
 - about 570 lines of source code
]

--- 

## There are many ways to declare a function, that are (almost) the same

 - .blue[`foo(x::Set) = 1`]
 - .blue[`function foo(x::Set) 2 end`]
 - .blue[`foo(x::Set{<:Any}) = 3`]
 - .blue[`foo(x::Set{T} where T) = 4`]
 - .purple[`foo(x::Set{T}) where T = 5`]
 - .red[`(::typeof(foo))(x::Set) = 6`]
 - .green[`const foo = (x::Set) -> 7`]
 - .green[`const foo = function (x::Set) 8 end`]

---

## I want to make some decorator macros
But I don't want to have to worry about all the different ways a function could have been written.

Consider `@log_trace` that will print the name and args of the function when it is entered.

```julia
@log_trace function foo(x)
    return 2*x
end

@log_trace bar(x) = 3*x

qux = @log_trace x->4*x
```

---

## How can I write that  with splitdef/combinedef ? 

```@example demo
macro log_trace(expr)
    def = splitdef(expr)
    name = Meta.quot(get(def, :name, Symbol("<anon>")))
    def[:body] = quote
        println("entering ", $name, $(args_tuple_expr(def)))
        $(def[:body])
    end
    combinedef(def)
end
nothing # hide
```

```@setup demo
@log_trace function foo(x)
    return 2*x
end;

@log_trace bar(x) = 3*x;

qux = @log_trace x->4*x;
nothing  # hide
```

```@example demo
foo(1); bar(2); qux(3)
nothing  #hide
```

---

### What did splitdef do?

```@example demo
def = splitdef(:(f(x::T, y::Int) where T = x*sizeof(T) + y))
```
### What did combinedef do?
```@example demo
combinedef(def)
```

---
### What did splitdef do?

```@example demo
def = splitdef(:(f(x::T, y::Int) where T = x*sizeof(T) + y))
```
### What did args\_tuple\_expr do?
```@example demo
args_tuple_expr(def)
```

---

## Automating the delegation pattern

 - _"Inheritance via Composition"_ is achieved via delegating methods to one of your fields.
 - I am pretty sure there is not actually 1 delegation pattern but at least 12
 - People think they want something that just hands it off to a field, but they don't.
 - e.g. every method of that except first check this thing, then unwrap and then after rewrap if it is the right type.

.funfact[The main use I have for this in in defining a operator overloading AD based on what methods of `rrule` exist.
if `rrule(f, x)` exist then need to define `f(x::Tracked)`.
**Nabla.jl** does exactly this.
]

---

### Wrapper Array

This is my tracing array.
It is like our `@log_trace` macro from before, except it is not by decorating a function but by declaring overloads of a type.
We want to overload all functions that take a `Array` as their first argument

```julia
julia> meths = [m for m in methodswith(Array) if m.sig <:Tuple{Any, Array, Vararg}]
[1] similar(a::Array{T}, m::Int64) where T in Base at array.jl:377
[2] similar(a::Array, T::Type, dims::Tuple{Vararg{Int64, N}}) where N in Base at array.jl:378
[3] similar(a::Array{T}, dims::Tuple{Vararg{Int64, N}}) where {T, N} in Base at array.jl:379
[4] copyto!(dest::Array{T}, doffs::Integer, src::Array{T}, soffs::Integer, n::Integer) where T in Base at array.jl:321
...
```
---


### Lets make our wrapper array
```@example demo
struct TraceArray{T,N,A<:AbstractArray{T,N}} <: AbstractArray{T,N}
    data::A
end
Base.parent(x::TraceArray) = x.data


function generate_overload(m::Method)
    def = signature(m.sig; extra_hygiene=true)
    def[:body] = quote
        orig_args = $(args_tuple_expr(def))
        args = (parent(orig_args[1]), orig_args[2:end]...)
        println("entering ", op, args)
        op(args...)
    end
    def[:args][1] = _wrap_arg(def[:args][1])
    return combinedef(def)
end
_wrap_arg(ex) = :($(ex.args[1])::TraceArray{<:Any,<:Any,<:$(ex.args[2])})
nothing  # hide
```

---

### What does signature give us?

```@setup demo
meths = [m for m in methodswith(Array) if m.sig <:Tuple{Any, Array, Vararg}]
```

```@example demo
def = signature(first(meths))
```

```@example demo
def[:args]
```
---


### Lets make our wrapper array

```@example demo
generate_overload(first(meths))  |> Base.remove_linenums!
```

Lets do them all
```@example demo
for m in meths
    eval(generate_overload(m))
end
```

---


### Lets try it out

```@example demo
TraceArray([1 2; 3 4]) .+ 1
nothing  # hide
```

```@example demo
TraceArray([1 2; 3 4])[[1,2]]
nothing  # hide
```

---


## How does this work?

```@example demo
m = first(meths)
```

```@example demo
m.sig
```

```@example demo
dump(parameters(m.sig)[2])
```

---

# Issues 
 - This won't pick up new methods defined after it is run.
 - Everything works on surface syntax: you need to be good at metaprogramming
 - This make it easy to subvert any kind of reasonable API.
<br><br>
.unfunfact[
You can use `Base.package_callbacks` to trigger code to run when ever any package is loaded.
**ChainRulesOverloadGeneration.jl** uses this to generate any new methods that have been defined.
]

---

# Summary
 - ExprTools makes it easy to metaprogram method definitions.
 - You can use reflection to power your metaprogramming
 - You can define ~700 methods in ~100 lines of code.
 - Should you? idk, it's a free world
<br>
.col[
.image-80[![Invenia Heart Julia](assets/invenia_julia.png)]  

We use machine learning to optimise the electricity grids.<br>
_more Julia, less emissions_<br>
Come join us!
]


