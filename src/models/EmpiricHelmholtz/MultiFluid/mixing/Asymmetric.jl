struct AsymmetricMixingParam <: EoSParam
    gamma_T::PairParam{Float64}
    gamma_v::PairParam{Float64}
    beta_T::PairParam{Float64}
    beta_v::PairParam{Float64}
end

@newmodelsimple AsymmetricMixing MixingRule AsymmetricMixingParam

function AsymmetricMixing(components;userlocations = String[],verbose = false)
    params = getparams(components,["Empiric/mixing/AsymmetricMixing/AsymmetricMixing_unlike.csv"]; asymmetricparams = ["beta_v","beta_T"],userlocations=userlocations, verbose=verbose)
    beta_v = params["beta_v"]
    gamma_v = params["gamma_v"]
    beta_T = params["beta_T"]
    gamma_T = params["gamma_T"]
    mirror_pair!(beta_T,inv)
    mirror_pair!(beta_v,inv)
    pkgparams = AsymmetricMixingParam(gamma_T,gamma_v,beta_T,beta_v)
    return AsymmetricMixing(pkgparams,verbose = verbose)
end

function calculate_missing_mixing!(params,mixing::AsymmetricMixing)
    Vc = params.Vc.values
    Tc = params.Tc.values
    #TODO
end

function v_scale(model::EmpiricMultiFluid,z,mixing::AsymmetricMixing,∑z)
    vc = model.params.Vc.values
    res = mixing_rule_asymetric(
        mix_mean3,
        _gerg_asymetric_mix_rule,
        z,
        vc,
        mixing.params.gamma_v.values,
        mixing.params.beta_v.values,
    )
    return res/(∑z*∑z)
end

function T_scale(model::EmpiricMultiFluid,z,mixing::AsymmetricMixing,∑z)
    Tc = model.params.Tc.values
    #isone(length(z)) && return only(Tc)
    return mixing_rule_asymetric(
        mix_geomean,
        _gerg_asymetric_mix_rule,
        z,
        Tc,
        mixing.params.gamma_T.values,
        mixing.params.beta_T.values,
    )/(∑z*∑z)
end

export AsymmetricMixing