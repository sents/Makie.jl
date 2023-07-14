# This file was generated, do not modify it. # hide
__result = begin # hide
    category_labels, data_array = mockup_categories_and_data_array(6)
rainclouds(category_labels, data_array;
    xlabel = "Categories of Distributions",
    ylabel = "Samples", title = "My Title",
    plot_boxplots = true, cloud_width=0.5,
    color = colors[indexin(category_labels, unique(category_labels))])
end # hide
save(joinpath(@OUTPUT, "example_4858774243463866941.png"), __result; ) # hide

nothing # hide