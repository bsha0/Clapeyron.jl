struct ActivityBubblePressure{T} <: BubblePointMethod
    vol0::Union{Nothing,Tuple{T,T}}
    p0::Union{Nothing,T}
    y0::Union{Nothing,Vector{T}}
    nonvolatiles::Union{Nothing,Vector{String}}
    itmax_ss::Int64
    rtol_ss::Float64
    gas_fug::Bool
    poynting::Bool
end

function ActivityBubblePressure(;vol0 = nothing,
                                p0 = nothing,
                                y0 = nothing,
                                nonvolatiles = nothing,
                                itmax_ss = 40,
                                rtol_ss = 1e-8,
                                gas_fug = true,
                                poynting = true)

    if p0 == y0 == vol0 == nothing
        return ActivityBubblePressure{Nothing}(vol0,p0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif (p0 == y0 == nothing) && !isnothing(vol0)
        vl,vv = promote(vol0[1],vol0[2])
        return ActivityBubblePressure{typeof(vl)}(vol0,p0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif (vol0 == y0 == nothing) && !isnothing(p0)
        p0 = float(p0)
        return ActivityBubblePressure{typeof(p0)}(vol0,p0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif (p0 == vol0 == nothing) && !isnothing(y0)
        T = eltype(y0)
        return ActivityBubblePressure{T}(vol0,p0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif !isnothing(vol0) && !isnothing(p0) && !isnothing(y0)
        vl,vv,p0,_ = promote(vol0[1],vol0[2],p0,first(y0))
        T = eltype(vl)
        y0 = convert(Vector{T},y0)
        return ActivityBubblePressure{T}(vol0,p0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif !isnothing(vol0) && !isnothing(y0)
        vl,vv,_ = promote(vol0[1],vol0[2],first(y0))
        T = eltype(vl)
        y0 = convert(Vector{T},y0)
        return ActivityBubblePressure{T}(vol0,p0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif  !isnothing(p0) && !isnothing(y0)
        p0,_ = promote(p0,first(y0))
        T = eltype(p0)
        y0 = convert(Vector{T},y0)
        return ActivityBubblePressure{T}(vol0,p0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    else
        throw(error("invalid specification for bubble pressure"))
    end
end


function bubble_pressure_impl(model,T,x,method::ActivityBubblePressure)
    
    pure = split_model(model)
    sat = saturation_pressure.(pure,T)
    p_pure = first.(sat)
    vl_pure = getindex.(sat,2)
    vv_pure = last.(sat)

    if isnothing(method.vol0)
        vl = dot(vl_pure,x)
        vv = zero(vl)
    else
        vl,vv = method.vol0
    end
   
    if isnan(vl)
        return vl,vl,vl,x
    end

    if isnothing(method.p0)
        pmix = pressure(model,vl,T,x)
    else
        pmix = method.p0
    end

    μmix = VT_chemical_potential_res(model,vl,T,x)
    @show μmix
    ϕ = copy(μmix)
    y = copy(μmix)
    ϕ .= 1
    #y = x .* p_pure #raoult initialization
    #y ./= sum(y)
    #@show y
    if !isnothing(method.y0)
        y .= method.y0
        if method.gas_fug
            μv = VT_chemical_potential_res!(ϕ,model,vv,T,y)
            ϕ .= exp.(μv ./ RT .- log.(pmix .* vv ./ RT))
        end
    end

    RT = (R̄*T)
    pold = zero(pmix)
    γ = zeros(typeof(pmix),length(pure))
    #pure part
    μpure = only.(VT_chemical_potential_res.(pure,vl_pure,T))
    ϕpure = exp.(μpure ./ RT .- log.(p_pure .* vl_pure ./ RT))
    if method.poynting
        κ = VT_isothermal_compressibility.(pure,vl_pure,T)
    else
        κ = copy(ϕ)
        κ .= 0.0
    end
    for k in 1:method.itmax_ss
        for i in eachindex(γ)
            pᵢ = p_pure[i]
            vpureᵢ = vl_pure[i]
            μᵢ = μpure[i]
            ϕ̂ᵢ =  ϕpure[i]
            γ[i] = exp(log(vpureᵢ/vl) + (μmix[i] - μᵢ)/RT -  vpureᵢ*(pmix -pᵢ)/RT)
            if method.poynting
                ln𝒫 = vpureᵢ*expm1(κ[i]*(pmix-pᵢ))/(κ[i]*RT) #see end of file
                𝒫 = exp(ln𝒫)
            else
                𝒫 = one(pᵢ)
            end
            #y[i]*ϕ[i]*P = x[i]*γ[i]*pᵢ*ϕ̂ᵢ*𝒫
            y[i] = x[i]*γ[i]*pᵢ*𝒫*ϕ̂ᵢ/ϕ[i] #really yᵢ*P, we normalize later
        end
        pold = pmix
        pmix = sum(y)
        y ./= pmix
        if iszero(vv)
            vv = dot(y,vv_pure)
        end
        vl = volume(model,pmix,T,x,vol0 = vl)
        if method.gas_fug
            logϕ, vv = lnϕ(model,pmix,T,y,phase = :vapor, vol0 = vv)
            ϕ .= exp.(logϕ)
        else
            vv = volume(model,pmix,T,y,phase =:vapor,vol0 = vv)
        end
        err = abs(pold-pmix)/pmix
        μmix = VT_chemical_potential_res!(μmix,model,vl,T,x)
        if err < method.rtol_ss
            break
        end
    end
    @show pmix,vl,vv,y
    return pmix,vl,vv,y
end

struct ActivityBubbleTemperature{T} <: BubblePointMethod
    vol0::Union{Nothing,Tuple{T,T}}
    T0::Union{Nothing,T}
    y0::Union{Nothing,Vector{T}}
    nonvolatiles::Union{Nothing,Vector{String}}
    itmax_ss::Int64
    rtol_ss::Float64
    gas_fug::Bool
    poynting::Bool
end

function ActivityBubbleTemperature(;vol0 = nothing,
                                T0 = nothing,
                                y0 = nothing,
                                nonvolatiles = nothing,
                                itmax_ss = 40,
                                rtol_ss = 1e-8,
                                gas_fug = true,
                                poynting = true)

    if T0 == y0 == vol0 == nothing
        return ActivityBubbleTemperature{Nothing}(vol0,T0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif (T0 == y0 == nothing) && !isnothing(vol0)
        vl,vv = promote(vol0[1],vol0[2])
        return ActivityBubbleTemperature{typeof(vl)}(vol0,T0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif (vol0 == y0 == nothing) && !isnothing(T0)
        T0 = float(T0)
        return ActivityBubbleTemperature{typeof(T0)}(vol0,T0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif (T0 == vol0 == nothing) && !isnothing(y0)
        T = eltype(y0)
        return ActivityBubbleTemperature{T}(vol0,T0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif !isnothing(vol0) && !isnothing(T0) && !isnothing(y0)
        vl,vv,T0,_ = promote(vol0[1],vol0[2],T0,first(y0))
        T = eltype(vl)
        y0 = convert(Vector{T},y0)
        return ActivityBubbleTemperature{T}(vol0,T0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif !isnothing(vol0) && !isnothing(y0)
        vl,vv,_ = promote(vol0[1],vol0[2],first(y0))
        T = eltype(vl)
        y0 = convert(Vector{T},y0)
        return ActivityBubbleTemperature{T}(vol0,T0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    elseif  !isnothing(T0) && !isnothing(y0)
        T0,_ = promote(T0,first(y0))
        T = eltype(T0)
        y0 = convert(Vector{T},y0)
        return ActivityBubbleTemperature{T}(vol0,T0,y0,nonvolatiles,itmax_ss,rtol_ss,gas_fug,poynting)
    else
        throw(error("invalid specification for bubble temperature"))
    end
end


function bubble_temperature_impl(model,p,x,method::ActivityBubbleTemperature)
    pure = split_model(model)
    sat = saturation_temperature.(pure,p)
    vl_pure = getindex.(sat,2)
    T_pure = first.(sat)
    vv_pure = last.(sat)

    if isnothing(method.vol0)
        vl = dot(vl_pure,x)
        vv = zero(vl)
    else
        vl,vv = method.vol0
    end
   
    if isnan(vl)
        return vl,vl,vl,x
    end

    dPdTsat = VT_entropy.(pure,vv_pure,T_pure) .- VT_entropy.(pure,vl_pure,T_pure) ./ (vv_pure .- vl_pure)
    y = copy(dPdTsat)
    ##initialization for T
    if isnothing(method.T0)
        #= we solve the aproximate problem of finding T such as:
        p = sum(xi*pi(T))
        where pi ≈ p0 + dpdt(T-T0)
        then: p = sum(xi*pi) = sum(xi*(p + dpdti*(T-Ti)))
        p = sum(xi*p) + sum(xi*dpdti*(T-Ti)) # sum(xi*p) = p
        0 = sum(xi*dpdti*(T-Ti))
        0 = sum(xi*dpdti)*T - sum(xi*dpdti*Ti)
        0 = T* ∑T - ∑Ti
        T = ∑Ti/∑T
        =#
        
        ∑T = zero(p+first(dPdTsat))
        ∑Ti = zero(∑T)
        for i in eachindex(dPdTsat)
            ∑Ti += x[i]*dPdTsat[i]*(T_pure[i])
            ∑T += x[i]*dPdTsat[i]
        end        
        Tmix = ∑Ti/∑T
    else
        Tmix = method.T0
    end
    return Tmix,Tmix,Tmix,y

    #restart pure initial points, Tmix is better than the saturation_temperature approach
    sat .= saturation_pressure.(pure,Tmix)
    vl_pure = getindex.(sat,2)
    p_pure = first.(sat)
    vv_pure .= last.(sat)
    dPdTsat .= VT_entropy.(pure,vv_pure,T_pure) .- VT_entropy.(pure,vl_pure,T_pure) ./ (vv_pure .- vl_pure)
        if isnothing(method.vol0)
        vl = dot(vl_pure,x)
        vv = zero(vl)
    else
        vl,vv = method.vol0
    end
    #initialization for y
    y = copy(dPdTsat)
    if isnothing(method.y0)
        y .= x.* p_pure
        y ./= sum(y)
    else
        y .= method.y0
    end    
    return Tmix,Tmix,Tmix,y
    μmix = VT_chemical_potential_res(model,vl,Tmix,x)
    ϕ = copy(μmix)
    y = zeros(length(pure))
    RT = (R̄*Tmix)
  
   # μv = VT_chemical_potential_res!(ϕ,model,vv,Tmix,method.y0)
   # ϕ .= exp.(μv ./ RT .- log.(p .* vv ./ RT))

    

    Told = zero(Tmix)
    pold = zero(Tmix)
    pcalc = zero(Tmix)
    γ = zeros(eltype(μmix),length(pure))
    
    for k in 1:method.itmax_ss
        for i in eachindex(γ)
            pᵢ = exp((ΔHvap[i]/R̄)*(1/T_pure[i] - 1/Tmix) + log(p)) #approximation for pi = psat(pure,Tmix)
            vpureᵢ = vl_pure[i]
            #v0i = vl_pure[i]
            #βi = VT_isothermal_compressibility(pure[i],v0i,T_pure[i])
            #v1i  = v0i*exp(βi*(p - pᵢ))
            #αi = VT_isobaric_expansivity(pure[i],v1i,T_pure[i])
            #v2i = v1i*exp(αi*(Tmix - T_pure[i]))
            #vpureᵢ = v2i
            #μᵢ = VT_gibbs_free_energy_res(pure[i],vpureᵢ,Tmix)
            μᵢ = eos_res(pure[i],vpureᵢ,Tmix) + (pᵢ - RT/vpureᵢ)*vpureᵢ
            #p*vv = RTi
            #vv = RTi/p
            ##
            vvᵢ = vv_pure[i]*(Tmix/T_pure[i])*(p/pᵢ)
            μvᵢ = eos_res(pure[i],vvᵢ,Tmix) + (pᵢ - RT/vvᵢ)*vvᵢ
            ϕ̂ᵢ =  exp(μvᵢ/RT - log(pᵢ*vvᵢ/RT))
            γ[i] = exp(log(vpureᵢ/vl) + (μmix[i] - μᵢ)/RT -  vpureᵢ*(p - pᵢ)/RT)
            ln𝒫 = vpureᵢ*(p-pᵢ)/RT
            𝒫 = exp(ln𝒫)
            y[i] = pᵢ*x[i]*γ[i]*𝒫*ϕ̂ᵢ/(ϕ[i])
        end
        pold = pcalc
        zi = pold*vv/RT
        pcalc = sum(y) #pv = nRT, T = pv/R
        #@show pcalc
        y ./= pcalc
        if iszero(vv)
            vv = dot(y,vv_pure)
        end
        #actual stepping
        #on a two phase region, (H_l - H_v)/(S_l - S_v) = T
        Told = Tmix
        dA_l, A_l = ∂f(model,vl,Tmix,x)
        dA_v, A_v = ∂f(model,vv,Tmix,y)
        ∂A∂V_l, ∂A∂T_l = dA_l
        ∂A∂V_v, ∂A∂T_v = dA_v
        H_l = A_l - vl*∂A∂V_l - Tmix*∂A∂T_l
        H_v = A_v - vv*∂A∂V_v - Tmix*∂A∂T_v
        S_l = - ∂A∂T_l
        S_v = - ∂A∂T_v
        Tcalc = (H_l - H_v)/(S_l - S_v)
        #dT/dp = t - tcalc/p - calc
        #dT/dp(p-pcalc) + tcalc = t
        dTdP = Tcalc*(vl - vv)/(H_l - H_v)
        Tmm = pcalc*vv/(R̄*zi) #pv = zRT
        Tmix = Tcalc + dTdP*(p-pcalc)
        #@show Tmm,Tmix
        RT = (R̄*Tmix)
        logϕ, vv = lnϕ(model,p,Tmix,y,phase = :vapor, vol0 = vv)
        vl = volume(model,p,Tmix,x,vol0 = vl)
        ϕ .= exp.(logϕ)

        err = abs(dTdP*(p-pcalc))
        μmix = VT_chemical_potential_res!(μmix,model,vl,Tmix,x)
        if err < method.rtol_ss
            @show err
            break
        end
    end
    @show pressure(model,vl,Tmix,x)
    @show pressure(model,vv,Tmix,y)

    return Tmix,vl,vv,y
end


## Poynting factor, Clapeyron edition
## we calculate ∫vi/RT dP from Ppure to Pmix
## v(p) = v0*exp(Δ(p)) = v0*exp((p-p0)*κ) #v0, p0 = vi, pi
## v(p) = vi*exp(-pi*κ) * exp(κ*p)
## ∫v(p)/RT dp = vi*exp(-pi*κ)/RT*∫exp(κ*p) dp = vi*exp(-pi*κ)*exp(κ*p)/κ 
## vi*exp(κ*(p-pi))/κRT  |from pi to pmix

#=
Problem:
on bubble and dew temperature calculations, we need the saturation point at each Ti.
calculating each point on each iteration can be really expensive.

we start with saturation_t
=#

