# This file was generated, do not modify it. # hide
__result = begin # hide
    f = Figure(resolution = (600, 600), backgroundcolor = :black)
ax = PolarAxis(
    f[1, 1], 
    backgroundcolor = :black,
    # r minor grid
    rminorgridvisible = true, rminorgridcolor = :red, 
    rminorgridwidth = 1.0, rminorgridstyle = :dash,
    # theta minor grid
    thetaminorgridvisible = true, thetaminorgridcolor = :lightblue,
    thetaminorgridwidth = 1.0, thetaminorgridstyle = :dash,
    # major grid
    rgridwidth = 2, rgridcolor = :red,
    thetagridwidth = 2, thetagridcolor = :lightblue,
    # r labels
    rticklabelsize = 18, rticklabelcolor = :red,
    rticklabelstrokewidth = 1.0, rticklabelstrokecolor = :white,
    # theta labels
    thetaticklabelsize = 18, thetaticklabelcolor = :lightblue
)

f
end # hide
save(joinpath(@OUTPUT, "example_9717902126039813769.png"), __result; ) # hide
save(joinpath(@OUTPUT, "example_9717902126039813769.svg"), __result; ) # hide
nothing # hide