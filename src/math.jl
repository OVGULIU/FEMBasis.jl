# This file is a part of JuliaFEM.
# License is MIT: see https://github.com/JuliaFEM/FEMBasis.jl/blob/master/LICENSE

import Base: length, size

function length(B::T) where T<:AbstractBasis
    return length(T)
end

function size(B::T) where T<:AbstractBasis
    return size(T)
end

function eval_basis!(B::T, N, xi) where T<:AbstractBasis
    return eval_basis!(T, N, xi)
end

function eval_dbasis!(B::T, dN, xi) where T<:AbstractBasis
    return eval_dbasis!(T, dN, xi)
end

function eval_basis(B, xi)
    N = zeros(1, length(B))
    eval_basis!(B, N, xi)
    return N
end

function eval_dbasis(B, xi)
    dN = zeros(size(B)...)
    eval_dbasis!(B, dN, xi)
    return dN
end

"""
    interpolate(B, T, xi)

Given basis B, interpolate T at xi.

# Example
```jldoctest
B = Quad4()
X = ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))
T = (1.0, 2.0, 3.0, 4.0)
interpolate(B, T, (0.0, 0.0))

# output

2.5

```
"""
function interpolate(B, T, xi)
    Ti = sum(b*t for (b, t) in zip(eval_basis(B, xi), T))
    return Ti
end

"""
    jacobian(B, X, xi)

Given basis B, calculate jacobian at xi.

# Example
```jldoctest
B = Quad4()
X = ([0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0])
jacobian(B, X, (0.0, 0.0))

# output

2×2 Array{Float64,2}:
 0.5  0.0
 0.0  0.5

```
"""
function jacobian(B, X, xi)
    dB = eval_dbasis(B, xi)
    dim1, nbasis = size(B)
    dim2 = length(first(X))
    J = zeros(dim1, dim2)
    for i=1:dim1
        for j=1:dim2
            for k=1:nbasis
                J[i,j] += dB[i,k]*X[k][j]
            end
        end
    end
    return J
end

"""
    grad(B, X, xi)

Given basis B, calculate gradient dB/dX at xi.

# Example
```jldoctest
B = Quad4()
X = ([0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0])
grad(B, X, (0.0, 0.0))

# output

2×4 Array{Float64,2}:
 -0.5   0.5  0.5  -0.5
 -0.5  -0.5  0.5   0.5

```
"""
function grad(B, X, xi)
    J = jacobian(B, X, xi)
    dB = eval_dbasis(B, xi)
    G = inv(J) * dB
    return G
end

"""
    grad(B, T, X, xi)

Calculate gradient of `T` with respect to `X` in point `xi` using basis `B`.

# Example
```jldoctest
B = Quad4()
X = ([0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0])
u = ([0.0, 0.0], [1.0, -1.0], [2.0, 3.0], [0.0, 0.0])
grad(B, u, X, (0.0, 0.0))

# output

2×2 Array{Float64,2}:
 1.5  0.5
 1.0  2.0

```
"""
function grad(B, T, X, xi)
    G = grad(B, X, xi)
    nbasis = length(B)
    dTdX = sum(kron(G[:,i], T[i]') for i=1:nbasis)
    return dTdX'
end


"""
Data type for fast FEM.
"""
mutable struct BasisInfo{B<:AbstractBasis,T}
    N::Matrix{T}
    dN::Matrix{T}
    grad::Matrix{T}
    J::Matrix{T}
    invJ::Matrix{T}
    detJ::T
end

function length(B::BasisInfo{T}) where T<:AbstractBasis
    return length(T)
end

function size(B::BasisInfo{T}) where T<:AbstractBasis
    return size(T)
end

"""
Initialization of data type `BasisInfo`.

# Examples

```jldoctest

BasisInfo(Tri3)

# output

FEMBasis.BasisInfo{FEMBasis.Tri3,Float64}([0.0 0.0 0.0], [0.0 0.0 0.0; 0.0 0.0 0.0], [0.0 0.0 0.0; 0.0 0.0 0.0], [0.0 0.0; 0.0 0.0], [0.0 0.0; 0.0 0.0], 0.0)

```

"""
function BasisInfo(::Type{B}, T=Float64) where B<:AbstractBasis
    dim, nbasis = size(B)
    N = zeros(T, 1, nbasis)
    dN = zeros(T, dim, nbasis)
    grad = zeros(T, dim, nbasis)
    J = zeros(T, dim, dim)
    invJ = zeros(T, dim, dim)
    detJ = zero(T)
    return BasisInfo{B,T}(N, dN, grad, J, invJ, detJ)
end

"""
Evaluate basis, gradient and so on for some point `xi`.

# Examples

```jldoctest

b = BasisInfo(Quad4)
X = ((0.0,0.0), (1.0,0.0), (1.0,1.0), (0.0,1.0))
xi = (0.0, 0.0)
eval_basis!(b, X, xi)

# output

FEMBasis.BasisInfo{FEMBasis.Quad4,Float64}([0.25 0.25 0.25 0.25], [-0.25 0.25 0.25 -0.25; -0.25 -0.25 0.25 0.25], [-0.5 0.5 0.5 -0.5; -0.5 -0.5 0.5 0.5], [0.5 0.0; 0.0 0.5], [2.0 -0.0; -0.0 2.0], 0.25)

```
"""
function eval_basis!(bi::BasisInfo{B}, X, xi) where B

    # evaluate basis and derivatives
    eval_basis!(B, bi.N, xi)
    eval_dbasis!(B, bi.dN, xi)

    dim1, nbasis = size(B)
    dim2 = length(first(X))
    dims = (dim1, dim2)
    if size(bi.J) != dims
        bi.J = zeros(dim1, dim2)
    else
        fill!(bi.J, 0.0)
    end

    # calculate Jacobian

    for i=1:dim1
        for j=1:dim2
            for k=1:nbasis
                bi.J[i,j] += bi.dN[i,k]*X[k][j]
            end
        end
    end

    # calculate determinant of Jacobian + gradient operator

    if dims == (3, 3)
        a, b, c, d, e, f, g, h, i = bi.J
        bi.detJ = a*(e*i-f*h) + b*(f*g-d*i) + c*(d*h-e*g)
        bi.invJ[1] = 1.0 / bi.detJ * (e*i - f*h)
        bi.invJ[2] = 1.0 / bi.detJ * (c*h - b*i)
        bi.invJ[3] = 1.0 / bi.detJ * (b*f - c*e)
        bi.invJ[4] = 1.0 / bi.detJ * (f*g - d*i)
        bi.invJ[5] = 1.0 / bi.detJ * (a*i - c*g)
        bi.invJ[6] = 1.0 / bi.detJ * (c*d - a*f)
        bi.invJ[7] = 1.0 / bi.detJ * (d*h - e*g)
        bi.invJ[8] = 1.0 / bi.detJ * (b*g - a*h)
        bi.invJ[9] = 1.0 / bi.detJ * (a*e - b*d)
        mul!(bi.grad, bi.invJ, bi.dN)
    elseif dims == (2, 2)
        a, b, c, d = bi.J
        bi.detJ = a*d - b*c
        bi.invJ[1] = 1.0 / bi.detJ * d
        bi.invJ[2] = 1.0 / bi.detJ * -b
        bi.invJ[3] = 1.0 / bi.detJ * -c
        bi.invJ[4] = 1.0 / bi.detJ * a
        mul!(bi.grad, bi.invJ, bi.dN)
    elseif dims == (1, 1)
        bi.detJ = bi.J[1]
        bi.invJ[1] = 1.0 / bi.detJ
        bi.grad = bi.invJ * bi.dN
    elseif dim1 == 1 # curve
        bi.detJ = norm(bi.J)
    elseif dim1 == 2 # manifold
        bi.detJ = norm(cross(bi.J[1,:], bi.J[2,:]))
    end

    return bi
end

"""
    grad!(bi, gradu, u)

Evalute gradient ∂u/∂X and store result to matrix `gradu`. It is assumed
that `eval_basis!` has been already run to `bi` so it already contains
all necessary matrices evaluated with some `X` and `xi`.

# Example

First setup and evaluate basis using `eval_basis!`:
```jldoctest ex1
B = BasisInfo(Quad4)
X = ((0.0,0.0), (1.0,0.0), (1.0,1.0), (0.0,1.0))
xi = (0.0, 0.0)
eval_basis!(B, X, xi)

# output

FEMBasis.BasisInfo{FEMBasis.Quad4,Float64}([0.25 0.25 0.25 0.25], [-0.25 0.25 0.25 -0.25; -0.25 -0.25 0.25 0.25], [-0.5 0.5 0.5 -0.5; -0.5 -0.5 0.5 0.5], [0.5 0.0; 0.0 0.5], [2.0 -0.0; -0.0 2.0], 0.25)

```

Next, calculate gradient of `u`:
```jldoctest ex1
u = ((0.0, 0.0), (1.0, -1.0), (2.0, 3.0), (0.0, 0.0))
gradu = zeros(2, 2)
grad!(B, gradu, u)

# output

2×2 Array{Float64,2}:
 1.5  0.5
 1.0  2.0
```
"""
function grad!(bi::BasisInfo{B}, gradu, u) where B
    dim, nbasis = size(B)
    fill!(gradu, 0.0)
    for i=1:dim
        for j=1:dim
            for k=1:nbasis
                gradu[i,j] += bi.grad[j,k]*u[k][i]
            end
        end
    end
    return gradu
end
