#  Copyright (c) 2017-25, Oscar Dowson and SDDP.jl contributors, Lea Kapelevich.
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.

module TestBinaryExpansion

using SDDP: binexpand, bincontract
using Test

function runtests()
    for name in names(@__MODULE__; all = true)
        if startswith("$(name)", "test_")
            @testset "$(name)" begin
                getfield(@__MODULE__, name)()
            end
        end
    end
    return
end

function test_Binary_Expansion()
    int_len = round(Int, log(typemax(Int)) / log(2))
    @test_throws Exception binexpand(0)
    @test binexpand(1, 1) == [1]
    @test binexpand(2, 2) == [0, 1]
    @test binexpand(3, 3) == [1, 1]
    @test binexpand(4, 4) == [0, 0, 1]
    @test binexpand(5, 5) == [1, 0, 1]
    @test binexpand(6, 6) == [0, 1, 1]
    @test binexpand(7, 7) == [1, 1, 1]
    @test_throws Exception binexpand(8, 7)
    @test binexpand(typemax(Int), typemax(Int)) == ones(Int, int_len)
    @test binexpand(0.5, 0.5) == binexpand(5, 5)
    @test binexpand(0.54, 0.54) == binexpand(5, 5)
    @test binexpand(0.56, 0.56, 0.1) == binexpand(6, 6)
    @test binexpand(0.5, 0.5, 0.01) == binexpand(50, 50)
    @test binexpand(0.54, 0.54, 0.01) == binexpand(54, 54)
    @test binexpand(0.56, 0.56, 0.01) == binexpand(56, 56)
    @test_throws(
        ErrorException(
            "Cannot perform binary expansion on a negative number." *
            "Initial values of state variables must be nonnegative.",
        ),
        binexpand(-1, 5),
    )
    @test_throws(
        ErrorException(
            "Cannot perform binary expansion on zero-length " *
            "vector. Upper bounds of state variables must be positive.",
        ),
        binexpand(5, 0),
    )
    @test 0 == bincontract([0])
    @test 1 == bincontract([1])
    @test 0 == bincontract([0, 0])
    @test 1 == bincontract([1, 0])
    @test 2 == bincontract([0, 1])
    @test 3 == bincontract([1, 1])
    @test 2 == bincontract([0, 1, 0])
    @test 3 == bincontract([1, 1, 0])
    @test 4 == bincontract([0, 0, 1])
    @test 5 == bincontract([1, 0, 1])
    @test 6 == bincontract([0, 1, 1])
    @test 7 == bincontract([1, 1, 1])
    @test typemax(Int) == bincontract(ones(Int, int_len))
    @test bincontract([0], 0.1) ≈ 0.0
    @test bincontract([1], 0.1) ≈ 0.1
    @test bincontract([0, 1], 0.1) ≈ 0.2
    @test bincontract([1, 1], 0.1) ≈ 0.3
    @test bincontract([0, 1, 0], 0.1) ≈ 0.2
    @test bincontract([1, 1, 0], 0.1) ≈ 0.3
    @test bincontract([1, 0, 1], 0.1) ≈ 0.5
    return
end

end  # module

TestBinaryExpansion.runtests()
