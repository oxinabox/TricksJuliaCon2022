using Pkg: Pkg
cd(@__DIR__)
Pkg.activate(pwd())
using Remark: Remark

function build()
    dir = Remark.slideshow(@__DIR__, title="Tricks.jl")
end

slideshow_dir = build()

#Remark.open(slideshow_dir)
#exit()

###

using FileWatching
while true
    build()
    @info "Rebuilt"
    FileWatching.watch_folder("src/")
end

