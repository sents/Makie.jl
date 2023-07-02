################################################################################
#                             Projection utilities                             #
################################################################################

"""
    cairo_project(plot, pos[; yflip = true, kwargs...])

Calls `Makie.project(plot, pos; kwargs...)` but returns 2D Points and optionally
flips the y axis.
"""
function cairo_project(plot, pos; yflip = true, type = Point2f, kwargs...)
    w, h = widths(Makie.pixelarea(Makie.get_scene(plot))[])
    ps = Makie.project(plot, pos; type = type, kwargs...)
    return yflip ? _yflip(ps, h) : ps
end

_yflip(p::VT, h) where {T <: Real, VT <: VecTypes{2, T}} = VT(p[1], h - p[2])
_yflip(p::VT, h) where {T <: Real, VT <: VecTypes{3, T}} = VT(p[1], h - p[2], p[3])
_yflip(ps::AbstractArray, h) = _yflip.(ps, h)

function project_scale(scene::Scene, space, s::Number, model = Mat4f(I))
    project_scale(scene, space, Vec2f(s), model)
end

function project_scale(scene::Scene, space, s, model = Mat4f(I))
    p4d = model * to_ndim(Vec4f, s, 0f0)
    if is_data_space(space)
        @inbounds p = (scene.camera.projectionview[] * p4d)[Vec(1, 2)]
        return p .* scene.camera.resolution[] .* 0.5
    elseif is_pixel_space(space)
        return p4d[Vec(1, 2)]
    elseif is_relative_space(space)
        return p4d[Vec(1, 2)] .* scene.camera.resolution[]
    else # clip
        return p4d[Vec(1, 2)] .* scene.camera.resolution[] .* 0.5f0
    end
end

function cairo_project(plot, rect::Rect; kwargs...)
    mini = cairo_project(plot, minimum(rect); kwargs...)
    maxi = cairo_project(plot, maximum(rect); kwargs...)
    return Rect(Vec(mini), Vec(maxi .- mini))
end

function cairo_project(plot, poly::P; type = Point2f, kwargs...) where P <: Polygon
    ext = decompose(Point2f, poly.exterior)
    interiors = decompose.(Point2f, poly.interiors)
    Polygon(
        cairo_project(plot, ext; type = type, kwargs...),
        Vector{type}[cairo_project(plot, interior; type = type, kwargs...) for interior in interiors]
    )
end

function cairo_project(plot, multipoly::MP; kwargs...) where MP <: MultiPolygon
    return MultiPolygon(cairo_project.((plot, ), multipoly.polygons; kwargs...))
end

scale_matrix(x, y) = Cairo.CairoMatrix(x, 0.0, 0.0, y, 0.0, 0.0)

########################################
#          Rotation handling           #
########################################

function to_2d_rotation(x)
    quat = to_rotation(x)
    return -Makie.quaternion_to_2d_angle(quat)
end

function to_2d_rotation(::Makie.Billboard)
    @warn "This should not be reachable!"
    0
end

remove_billboard(x) = x
remove_billboard(b::Makie.Billboard) = b.rotation

to_2d_rotation(quat::Makie.Quaternion) = -Makie.quaternion_to_2d_angle(quat)

# TODO: this is a hack around a hack.
# Makie encodes the transformation from a 2-vector
# to a quaternion as a rotation around the Y-axis,
# when it should be a rotation around the X-axis.
# Since I don't know how to fix this in GLMakie,
# I've reversed the order of arguments to atan,
# such that our behaviour is consistent with GLMakie's.
to_2d_rotation(vec::Vec2f) = atan(vec[1], vec[2])

to_2d_rotation(n::Real) = n


################################################################################
#                                Color handling                                #
################################################################################

function rgbatuple(c::Colorant)
    rgba = RGBA(c)
    red(rgba), green(rgba), blue(rgba), alpha(rgba)
end

function rgbatuple(c)
    colorant = to_color(c)
    if !(colorant isa Colorant)
        error("Can't convert $(c) to a colorant")
    end
    return rgbatuple(colorant)
end

to_uint32_color(c) = reinterpret(UInt32, convert(ARGB32, premultiplied_rgba(c)))

########################################
#        Common color utilities        #
########################################

function to_cairo_color(colors::Union{AbstractVector{<: Number},Number}, plot_object)
    return numbers_to_colors(colors, plot_object)
end

function to_cairo_color(color::Makie.AbstractPattern, plot_object)
    cairopattern = Cairo.CairoPattern(color)
    Cairo.pattern_set_extend(cairopattern, Cairo.EXTEND_REPEAT);
    return cairopattern
end

function to_cairo_color(color, plot_object)
    return to_color(color)
end

function set_source(ctx::Cairo.CairoContext, pattern::Cairo.CairoPattern)
    return Cairo.set_source(ctx, pattern)
end

function set_source(ctx::Cairo.CairoContext, color::Colorant)
    return Cairo.set_source_rgba(ctx, rgbatuple(color)...)
end

########################################
#     Image/heatmap -> ARGBSurface     #
########################################

function to_cairo_image(img::AbstractMatrix{<: AbstractFloat}, attributes)
    to_cairo_image(to_rgba_image(img, attributes), attributes)
end

function to_rgba_image(img::AbstractMatrix{<: AbstractFloat}, attributes)
    Makie.@get_attribute attributes (colormap, colorrange, nan_color, lowclip, highclip)

    nan_color = Makie.to_color(nan_color)
    lowclip = isnothing(lowclip) ? lowclip : Makie.to_color(lowclip)
    highclip = isnothing(highclip) ? highclip : Makie.to_color(highclip)

    [get_rgba_pixel(pixel, colormap, colorrange, nan_color, lowclip, highclip) for pixel in img]
end

to_rgba_image(img::AbstractMatrix{<: Colorant}, attributes) = RGBAf.(img)

function get_rgba_pixel(pixel, colormap, colorrange, nan_color, lowclip, highclip)
    vmin, vmax = colorrange
    if isnan(pixel)
        RGBAf(nan_color)
    elseif pixel < vmin && !isnothing(lowclip)
        RGBAf(lowclip)
    elseif pixel > vmax && !isnothing(highclip)
        RGBAf(highclip)
    else
        RGBAf(Makie.interpolated_getindex(colormap, pixel, colorrange))
    end
end

function to_cairo_image(img::AbstractMatrix{<: Colorant}, attributes)
    to_cairo_image(to_uint32_color.(img), attributes)
end

function to_cairo_image(img::Matrix{UInt32}, attributes)
    # we need to convert from column-major to row-major storage,
    # therefore we permute x and y
    return Cairo.CairoARGBSurface(permutedims(img))
end


################################################################################
#                                Mesh handling                                 #
################################################################################

struct FaceIterator{Iteration, T, F, ET} <: AbstractVector{ET}
    data::T
    faces::F
end

function (::Type{FaceIterator{Typ}})(data::T, faces::F) where {Typ, T, F}
    FaceIterator{Typ, T, F}(data, faces)
end
function (::Type{FaceIterator{Typ, T, F}})(data::AbstractVector, faces::F) where {Typ, F, T}
    FaceIterator{Typ, T, F, NTuple{3, eltype(data)}}(data, faces)
end
function (::Type{FaceIterator{Typ, T, F}})(data::T, faces::F) where {Typ, T, F}
    FaceIterator{Typ, T, F, NTuple{3, T}}(data, faces)
end
function FaceIterator(data::AbstractVector, faces)
    if length(data) == length(faces)
        FaceIterator{:PerFace}(data, faces)
    else
        FaceIterator{:PerVert}(data, faces)
    end
end

Base.size(fi::FaceIterator) = size(fi.faces)
Base.getindex(fi::FaceIterator{:PerFace}, i::Integer) = fi.data[i]
Base.getindex(fi::FaceIterator{:PerVert}, i::Integer) = fi.data[fi.faces[i]]
Base.getindex(fi::FaceIterator{:Const}, i::Integer) = ntuple(i-> fi.data, 3)

color_or_nothing(c) = isnothing(c) ? nothing : to_color(c)
function get_color_attr(attributes, attribute)::Union{Nothing, RGBAf}
    return color_or_nothing(to_value(get(attributes, attribute, nothing)))
end

function per_face_colors(
        color, colormap, colorrange, matcap, faces, normals, uv,
        lowclip=nothing, highclip=nothing, nan_color=nothing
    )
    if matcap !== nothing
        wsize = reverse(size(matcap))
        wh = wsize .- 1
        cvec = map(normals) do n
            muv = 0.5n[Vec(1,2)] .+ Vec2f(0.5)
            x, y = clamp.(round.(Int, Tuple(muv) .* wh) .+ 1, 1, wh)
            return matcap[end - (y - 1), x]
        end
        return FaceIterator(cvec, faces)
    elseif color isa Colorant
        return FaceIterator{:Const}(color, faces)
    elseif color isa AbstractArray
        if color isa AbstractVector{<: Colorant}
            return FaceIterator(color, faces)
        elseif color isa AbstractArray{<: Number}
            low, high = extrema(colorrange)
            cvec = map(color[:]) do c
                if isnan(c) && nan_color !== nothing
                    return nan_color
                elseif c < low && lowclip !== nothing
                    return lowclip
                elseif c > high && highclip !== nothing
                    return highclip
                else
                    Makie.interpolated_getindex(colormap, c, colorrange)
                end
            end
            return FaceIterator(cvec, faces)
        elseif color isa Makie.AbstractPattern
            # let next level extend and fill with CairoPattern
            return color
        elseif color isa AbstractMatrix{<: Colorant} && uv !== nothing
            wsize = reverse(size(color))
            wh = wsize .- 1
            cvec = map(uv) do uv
                x, y = clamp.(round.(Int, Tuple(uv) .* wh) .+ 1, 1, wh)
                return color[end - (y - 1), x]
            end
            # TODO This is wrong and doesn't actually interpolate
            # Inside the triangle sampling the color image
            return FaceIterator(cvec, faces)
        end
    end
    error("Unsupported Color type: $(typeof(color))")
end

function mesh_pattern_set_corner_color(pattern, id, c::Colorant)
    Cairo.mesh_pattern_set_corner_color_rgba(pattern, id, rgbatuple(c)...)
end

# not piracy
function Cairo.CairoPattern(color::Makie.AbstractPattern)
    # the Cairo y-coordinate are fliped
    bitmappattern = reverse!(ARGB32.(Makie.to_image(color)); dims=2)
    cairoimage = Cairo.CairoImageSurface(bitmappattern)
    cairopattern = Cairo.CairoPattern(cairoimage)
    return cairopattern
end

"""
Finds a font that can represent the unicode character!
Returns Makie.defaultfont() if not representable!
"""
function best_font(c::Char, font = Makie.defaultfont())
    if Makie.FreeType.FT_Get_Char_Index(font, c) == 0
        for afont in Makie.alternativefonts()
            if Makie.FreeType.FT_Get_Char_Index(afont, c) != 0
                return afont
            end
        end
        return Makie.defaultfont()
    end
    return font
end
