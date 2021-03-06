# create type MatrixNetwork
type MatrixNetwork{T}
    n::Int64 # number of columns/rows
    rp::Vector{Int64} # row pointers
    ci::Vector{Int64} # column indices
    vals::Vector{T} # corresponding values
end

function MatrixNetwork{T}(A::SparseMatrixCSC{T,Int64})
    At = A'
    return MatrixNetwork(size(At,2),At.colptr,At.rowval,At.nzval)
end

function _second(x)
    return x[2]
end    

MatrixNetwork(edges::Vector{Tuple{Int,Int}}, n::Int) =
    MatrixNetwork(map(first,edges),map(_second,edges), n)
   

MatrixNetwork(ei::Vector{Int64},ej::Vector{Int64}) = 
    MatrixNetwork(ei,ej,max(maximum(ei),maximum(ej)))

function MatrixNetwork(ei::Vector{Int64},ej::Vector{Int64},n::Int64)
    At = sparse(ej,ei,true,n,n);
    return MatrixNetwork(size(At,2),At.colptr,At.rowval,At.nzval)
end


function _matrix_network_direct{T}(A::SparseMatrixCSC{T,Int64})
    return MatrixNetwork(size(A,2),A.colptr,A.rowval,A.nzval)
end

function _matrix_network_direct{T}(A::SparseMatrixCSC{T,Int64},v)
    nzval = ones(typeof(v),length(A.nzval))
    return MatrixNetwork(size(A,2),A.colptr,A.rowval,nzval)
end


import Base.sparse, Base.size, Base.*, Base.A_mul_B!, Base.At_mul_B, Base.At_mul_B!

"""
Return back an adjacency matrix representation
of the transpose. This requires no work. 
"""
function sparse_transpose{T}(A::MatrixNetwork{T})
    return SparseMatrixCSC(A.n,A.n,A.rp,A.ci,A.vals)
end

"""
Return back an adjacency matrix representation
of the current MatrixNetwork
"""
function sparse{T}(A::MatrixNetwork{T})
    return sparse_transpose(A)'
end

function size(A::MatrixNetwork)
    return (A.n,A.n)
end

import Base.ndims 
ndims(op::MatrixNetwork) = 2

function size(A::MatrixNetwork, dim::Integer)
    if dim == 1 || dim == 2
        return A.n
    elseif dim > 2
        return 1
    else
        throw(DomainError())
    end
end

*(M::MatrixNetwork, b) = A_mul_B(M, b)
A_mul_B{T,S}(M::MatrixNetwork{T}, b::AbstractVector{S}) = 
    A_mul_B!(Array(promote_type(T,S), size(M,2)), M, b) 
function A_mul_B!(output, M::MatrixNetwork, b)
    At_mul_B!(output, sparse_transpose(M), b) 
end

At_mul_B{S}(M::MatrixNetwork, b::AbstractVector{S}) = 
    At_mul_B!(Array(promote_type(Float64,S), size(M,1)), M, b)
function At_mul_B!(output, M::MatrixNetwork, b)
    A_mul_B!(output, sparse_transpose(M), b) 
end

    

"""
`is_empty`
==========

Return true if the graph is the empty graph and 
false otherwise. 

Functions
---------
-`is_empty(A::MatrixNetwork)`

Example
-------
~~~~
is_empty(MatrixNetwork(Int[],Int[],0))
is_empty(erdos_renyi_undirected(0,0))
~~~~
"""
is_empty(A::MatrixNetwork) = size(A,1) == 0 

"""
`is_undirected`
===============

Check the matrix associated with a matrix network
for symmetry. 

Input
-----
- `A`: a matrix network

Returns
-------
- `bool` with true indicating the network is undirected
    and the matrix is symmetric
"""    
function is_undirected end
    
function is_undirected(A::MatrixNetwork)
   M = sparse_transpose(A)
   return issymmetric(M) 
end

function is_undirected(A::SparseMatrixCSC)
   return issymmetric(A) 
end

"""
`is_connected`
==============

Check the matrix associated with a matrix network
for (strong) connectivity  

Usage
-----
- `is_connected(A)`

Input
-----
- `A`: a `MatrixNetwork` or `SparseMatrixCSC` class

Returns
-------
- `bool` with true indicating the matrix is strongly connected
and false indicating 
"""    
function is_connected end

function is_connected(A::Union{MatrixNetwork,SparseMatrixCSC})
    # this is equivalent to maximum with a default value of 0
    return mapreduce(identity, max, 0, strong_components_map(A)) == 1
end

"""
`empty_graph`
================

Returns an empty graph with n vertices and zero edges

Functions
---------
* `A = empty_graph(n)` generates an empty graph on n edges.

Example
-------
~~~~
is_connected(empty_graph(0))
is_connected(empty_graph(1))
~~~~
"""

function empty_graph end

function empty_graph(n::Integer=0)
    return MatrixNetwork(n,ones(Int64,n+1),Array{Int64}(0),Array{Float64}(0))
end

"""
`random_edge`
=============
Identify a random edge of a matrix network or sparse matrix.

Functions
---------
* `random_edge(A::MatrixNetwork) -> (ei,ej,ind)` 
   gets a random edge/non-zero from the matrix
   
* `random_edge(A::SparseMatrixCSC) -> (ei,ej,ind)` 
   gets a random non-zero from the matrix
   
Example
-------
~~~~
G = lollipop_graph(5,3)
# count the number of edges we randomly see between the regions
C = Dict{Symbol,Int}()
M = zeros(8,8)
for i=1:1000000
  ei,ej = MatrixNetwork.random_edge(G)
  M[ei,ej] += 1
  if 1 <= ei <= 5 && 1 <= ej <= 5
    C[:Stem] = get(C, :Stem, 0) + 1
  elseif 6 <= ei <= 10 && 6 <= ej <= 10
    C[:Pop] = get(C, :Pop, 0) + 1  
  else
    C[:Bridge] = get(C, :Bridge, 0) + 1  
  end
end
# 4 edges in stem, 3 edges in pop, 1 edge in bridge 
@show C
@show M
~~~~
"""
function random_edge(A::MatrixNetwork)
    ind = rand(1:length(A.ci)) # the index
    ej = A.ci[ind]
    ei = searchsortedlast(A.rp, ind) # uses binary search for efficiency
    assert(ei <= A.n)
    return (ei,ej,ind)
end
function random_edge(A::SparseMatrixCSC)
    ind = rand(1:length(A.rowval)) # the index
    ei = A.rowval[ind]
    ej = searchsortedlast(A.colptr, ind) # uses binary search for efficiency
    assert(ej <= A.n)
    return (ei,ej,ind)
end

"""
    undirected_edges(A) -> srcs,dsts

Produce lists just for the undirected edges. This assumes you want only
those edges where (target >= source). 
"""
function undirected_edges(A::MatrixNetwork)
    ei = Vector{Int64}()
    ej = Vector{Int64}()
    sizehint!(ei, div(A.rp[A.n+1],2))
    sizehint!(ej, div(A.rp[A.n+1],2))    
    for i=1:A.n
        for nzi=A.rp[i]:A.rp[i+1]-1 
            j = A.ci[nzi]
            if j >= i
                push!(ei, i)
                push!(ej, j)
            end
        end
    end
    return ei,ej
end

"""
    directed_edges(A) -> srcs,dsts

Produce lists just for all edges of the graph, including both sides for
undirected edges. This is essentially the same as findnz for a sparse matrix,
optimized not to return the values. 
"""
function directed_edges(A::MatrixNetwork)
    ei = Vector{Int64}()
    ej = Vector{Int64}()
    sizehint!(ei, A.rp[A.n+1])
    sizehint!(ej, A.rp[A.n+1])        
    for i=1:A.n
        for nzi=A.rp[i]:A.rp[i+1]-1 
            j = A.ci[nzi]   
            push!(ei, i)
            push!(ej, j)
        end
    end
    return ei,ej
end

