
### Consider I want to define a operated overloading AD.

 - For every method of `rrule` taking a `Real` I want to define a overload of the primal function accepting my `TrackedReal` type.
 - For every method of `rrule` taking a `AbstractArray` I want to define a overload of the primal function accepting my `TrackedArray` type.
 - For every other method of `rrule` I want to define a overload of my `Tracked{T}` type.

This is what I made this functionality for, and Nabla.jl now uses them in more or less this way.



### Main challenge is there are a lot of edge cases

To make sure we cover them all we adopted a test driven development base approach.
Of coming up with *increasingly weird ways* of expressing things in julia
and then writing tests and source to make them pass.


 - about 590 tests
 - about 1270 lines of test code
 - about 570 lines of source code
