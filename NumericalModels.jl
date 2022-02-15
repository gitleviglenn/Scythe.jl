module NumericalModels

using SpectralGrid
using Parameters

export ModelParameters

#Define some convenient aliases
const real = Float64
const int = Int64
const uint = UInt64

@with_kw struct ModelParameters
    ts::Float64 = 0.0
    integration_time::Float64 = 1.0
    output_interval::Float64 = 1.0
    equation_set = "LinearAdvection1D"
    initial_conditions = "ic.csv"
    output_dir = "./output/"
    grid_params::GridParameters
end

function LinearAdvection1D(physical::Array{real}, 
            gridpoints::Array{real},
            vardot::Array{real},
            F::Array{real},
            model::ModelParameters)
   
    #1D Linear advection to test
    c_0 = 1.0
    K = 0.003

    vardot[:,1] .= -c_0 .* physical[:,1,2] .+ (K .* physical[:,1,3])        
    # F = 0
end

function LinearAdvectionRZ(physical::Array{real}, 
            gridpoints::Array{real},
            vardot::Array{real},
            F::Array{real},
            model::ModelParameters)
   
    #1D Linear advection to test
    c_0 = 5.0
    K = 0.003

    vardot[:,1] .= -c_0 .* physical[:,1,2] .+ (K .* physical[:,1,3])        
    # F = 0
end

function LinearAdvectionRL(grid::RL_Grid, 
            gridpoints::Array{real},
            vardot::Array{real},
            F::Array{real},
            model::ModelParameters)
   
    #1D Linear advection to test
    c_0 = 5.0
    #K = 0.003
    K = 0.0

    vardot[:,1] .= -c_0 .* grid.physical[:,1,4] .+ (K .* grid.physical[:,1,5])        
    # F = 0
end

function Williams2013_slabTCBL(grid::R_Grid, 
            gridpoints::Array{real},
            vardot::Array{real},
            F::Array{real},
            model::ModelParameters)

    # Need to figure out how to assign these with symbols
    K = 1500.0
    Cd = 2.4e-3
    h = 1000.0
    f = 5.0e-5

    vgr = grid.physical[:,1,1]
    vardot[:,1] .= 0.0
    F[:,1] .= 0.0
    
    u = grid.physical[:,2,1]
    ur = grid.physical[:,2,2]
    urr = grid.physical[:,2,3]
    v = grid.physical[:,3,1]
    vr = grid.physical[:,3,2]
    vrr = grid.physical[:,3,3]
    r = gridpoints

    U = 0.78 * sqrt.((u .* u) .+ (v .* v))

    w = -h .* ((u ./ r) .+ ur)
    w_ = 0.5 .* abs.(w) .- w
    # W is diagnostic
    grid.physical[:,4,1] .= w
    vardot[:,4] .= 0.0
    F[:,4] .= 0.0

    UADV = -(u .* ur)
    UDRAG = -(Cd .* U .* u ./ h)
    UCOR = ((f .* v) .+ ((v .* v) ./ r))
    UPGF = -((f .* vgr) .+ ((vgr .* vgr) ./ r))
    UW = -(w_ .* (u ./ h))
    UKDIFF = K .* ((u ./ r) .+ ur)
    vardot[:,2] .= UADV .+ UDRAG .+ UCOR .+ UPGF .+ UW
    F[:,2] .= UKDIFF

    VADV = -u .* (f .+ (v ./ r) .+ vr)
    VDRAG = -(Cd .* U .* v ./ h)
    VW = w_ .* (vgr - v) ./ h
    VKDIFF = K .* ((v ./ r) .+ vr)
    vardot[:,3] .= VADV .+ VDRAG .+ UW
    F[:,3] .= VKDIFF

end

function Kepert2017_TCBL(grid::RZ_Grid, 
            gridpoints::Array{real},
            udot::Array{real},
            F::Array{real},
            model::ModelParameters)

    # Need to figure out how to assign these with symbols
    K = 1500.0
    Cd = 2.4e-3
    f = 5.0e-5

    # No delayed diffusion
    #F = 0
    
    # Gradient wind doesn't change
    vgr = grid.physical[:,1,1]
    udot[:,1] .= 0.0
    
    u = grid.physical[:,2,1]
    ur = grid.physical[:,2,2]
    urr = grid.physical[:,2,3]
    uz = grid.physical[:,2,4]
    uzz = grid.physical[:,2,5]
    
    v = grid.physical[:,3,1]
    vr = grid.physical[:,3,2]
    vrr = grid.physical[:,3,3]
    vz = grid.physical[:,3,4]
    vzz = grid.physical[:,3,5]
    
    r = gridpoints[:,1]
    z = gridpoints[:,2]

    # Get the 10 meter wind (assuming 10 m @ z == 2)
    r1 = grid.params.rDim+1
    r2 = 2*grid.params.rDim
    u10 = grid.physical[r1:r2,2,1]
    v10 = grid.physical[r1:r2,3,1]
    U10 = sqrt.((u10 .* u10) .+ (v10 .* v10))
    
    # Calculate the vertical diffusivity and vertical velocity
    Kv = zeros(Float64, size(grid.physical))
    Kvspectral = zeros(Float64, size(grid.spectral))
    w = zeros(Float64, size(grid.physical[:,4,1]))
    
    S = sqrt.((uz .* uz) .+ (vz .* vz))

    # Surface drag
    r1 = 1
    r2 = grid.params.rDim
    Kv[r1:r2,1,1] = Cd .* U10 .* u10
    Kv[r1:r2,2,1] = Cd .* U10 .* v10
    
    # Go through each vertical level
    for z = 2:grid.params.zDim
        # Calculate Kv
        l = 1.0 / ((1.0 / (0.4 * gridpoints[z])) + (1.0 / 80.0))
        r1 = ((z-1)*grid.params.rDim)+1
        r2 = z*grid.params.rDim
        Kv[r1:r2,1,1] = (l * l) .* S[r1:r2] .* uz[r1:r2]
        Kv[r1:r2,2,1] = (l * l) .* S[r1:r2] .* vz[r1:r2]
    end
    
    # Use Kv[3] for convergence
    Kv[:,3,1] .= -((u ./ r) .+ ur)
    
    # Differentiate Ku and Kv
    spectralTransform(grid, Kv, Kvspectral)
    gridTransform_noBCs(grid, Kv, Kvspectral)

    # Integrate divergence to get W    
    w = integrateUp(grid, Kv[:,3,1], Kvspectral[:,3])
    grid.physical[:,4,1] .= w
    udot[:,4] .= 0.0

    UADV = -(u .* ur) 
    UCOR = ((f .* v) .+ ((v .* v) ./ r))
    UPGF = -((f .* vgr) .+ ((vgr .* vgr) ./ r))
    UW = -(w .* uz)
    UHDIFF = K .* ((ur ./ r) .+ urr .- (u ./ (r .* r)))
    UVDIFF = Kv[:,1,4]
    udot[:,2] .= UADV .+ UCOR .+ UPGF .+ UW .+ UHDIFF .+ UVDIFF

    VADV = -u .* (f .+ (v ./ r) .+ vr)
    VW = -(w .* vz)
    VHDIFF = K .* ((vr ./ r) .+ vrr .- (v ./ (r .* r)))
    VVDIFF = Kv[:,2,4]
    udot[:,3] .= VADV .+ UW .+ VHDIFF .+ VVDIFF

end



function Williams2013_old(model,x,var,varx,varxx)

        K = 1500.0
        Cd = 2.4e-3
        h = 1000.0
        f = 5.0e-5

        vgrdot = zeros(real,length(x))
        vardot = zeros(real,length(x),4)
        F = zeros(real,length(x),4)

        vgr = var[:,1]
        u = var[:,2]
        v = var[:,3]
        r = x
        U = 0.78 * sqrt.((u .* u) .+ (v .* v))

        ur = varx[:,2]
        vr = varx[:,3]

        urr = varxx[:,2]
        vrr = varxx[:,3]

        w = -h .* ((u ./ r) .+ ur)
        w_ = 0.5 .* abs.(w) .- w

        vardot[:,1] .= vgrdot

        UADV = -(u .* ur)
        UDRAG = -(Cd .* U .* u ./ h)
        UCOR = ((f .* v) .+ ((v .* v) ./ r))
        UPGF = -((f .* vgr) .+ ((vgr .* vgr) ./ r))
        UW = -(w_ .* (u ./ h))
        UKDIFF = K .* ((u ./ r) .+ ur)
        vardot[:,2] .= UADV .+ UDRAG .+ UCOR .+ UPGF .+ UW
        F[:,2] .= UKDIFF

        VADV = -u .* (f .+ (v ./ r) .+ vr)
        VDRAG = -(Cd .* U .* v ./ h)
        VW = w_ .* (vgr - v) ./ h
        VKDIFF = K .* ((v ./ r) .+ vr)
        vardot[:,3] .= VADV .+ VDRAG .+ UW
        F[:,3] .= VKDIFF

        vardot[:,4] .= w

        return vardot, F
end

# Module end
end