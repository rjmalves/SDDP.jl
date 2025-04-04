#  Copyright (c) 2017-25, Oscar Dowson and SDDP.jl contributors.
#  This Source Code Form is subject to the terms of the Mozilla Public
#  License, v. 2.0. If a copy of the MPL was not distributed with this
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.

module TestAlgorithm

using SDDP
using Test
import HiGHS

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

function test_to_nodal_forms()
    model = SDDP.PolicyGraph(
        SDDP.LinearGraph(2);
        bellman_function = SDDP.BellmanFunction(; lower_bound = 0.0),
        optimizer = HiGHS.Optimizer,
    ) do node, stage
        @variable(node, x >= 0, SDDP.State, initial_value = 0.0)
        @stageobjective(node, x.out)
        SDDP.parameterize(node, stage * [1, 3], [0.5, 0.5]) do ω
            return JuMP.set_lower_bound(x.out, ω)
        end
    end
    SDDP.train(
        model;
        iteration_limit = 1,
        print_level = 0,
        risk_measure = SDDP.Expectation(),
    )
    @test SDDP.termination_status(model) == :iteration_limit
    SDDP.train(
        model;
        iteration_limit = 1,
        print_level = 0,
        risk_measure = Dict(1 => SDDP.Expectation(), 2 => SDDP.WorstCase()),
    )
    @test SDDP.termination_status(model) == :iteration_limit
    SDDP.train(
        model;
        iteration_limit = 1,
        print_level = 0,
        risk_measure = (idx) ->
            idx == 1 ? SDDP.Expectation() : SDDP.WorstCase(),
    )
    @test SDDP.termination_status(model) == :iteration_limit
end

function test_solve()
    model = SDDP.PolicyGraph(
        SDDP.LinearGraph(2);
        bellman_function = SDDP.BellmanFunction(; lower_bound = 0.0),
        optimizer = HiGHS.Optimizer,
    ) do node, stage
        @variable(node, x >= 0, SDDP.State, initial_value = 0.0)
        @stageobjective(node, x.out)
        SDDP.parameterize(node, stage * [1, 3], [0.5, 0.5]) do ω
            return JuMP.set_lower_bound(x.out, ω)
        end
    end
    SDDP.train(model; iteration_limit = 4, print_level = 0)
    @test SDDP.termination_status(model) == :iteration_limit
    simulations = SDDP.simulate(model, 11, [:x])
    @test length(simulations) == 11
    @test all(length.(simulations) .== 2)

    simulation = simulations[1][1]
    @test length(keys(simulation)) == 7
    @test sort(collect(keys(simulation))) == [
        :belief,
        :bellman_term,
        :node_index,
        :noise_term,
        :objective_state,
        :stage_objective,
        :x,
    ]
    @test typeof(simulation[:x]) == SDDP.State{Float64}
    return
end

function test_simulate()
    model = SDDP.LinearPolicyGraph(;
        stages = 2,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do sp, t
        @variable(sp, x[i = 1:2] >= i, SDDP.State, initial_value = 2i)
        @stageobjective(sp, x[1].out + x[2].out)
    end
    simulations = SDDP.simulate(model, 1, [:x])
    @test simulations[1][1][:x] == [SDDP.State(2.0, 1.0), SDDP.State(4.0, 2.0)]
    return
end

function test_simulate_incoming_state()
    model = SDDP.LinearPolicyGraph(;
        stages = 2,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do sp, t
        @variable(sp, x[i = 1:2] >= i, SDDP.State, initial_value = 2i)
        @constraint(sp, [i = 1:2], x[i].out == x[i].in)
        @stageobjective(sp, x[1].out + x[2].out)
    end
    simulations = SDDP.simulate(
        model,
        1,
        [:x];
        incoming_state = Dict("x[1]" => 3.0, "x[2]" => 3.0),
    )
    @test simulations[1][1][:x] == [SDDP.State(3.0, 3.0), SDDP.State(3.0, 3.0)]
    simulations = SDDP.simulate(model, 1, [:x])
    @test simulations[1][1][:x] == [SDDP.State(2.0, 2.0), SDDP.State(4.0, 4.0)]
    return
end

function test_simulate_missing()
    model = SDDP.LinearPolicyGraph(;
        stages = 2,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do sp, t
        @variable(sp, x[i = 1:2] >= i, SDDP.State, initial_value = 2i)
        if t == 1
            @variable(sp, y >= 0)
        end
        @stageobjective(sp, x[1].out + x[2].out)
    end
    @test_throws(
        ErrorException,
        SDDP.simulate(model, 1, [:y]; parallel_scheme = SDDP.Serial()),
    )
    sims = SDDP.simulate(model, 1, [:y]; skip_undefined_variables = true)
    @test sims[1][1][:y] == 0.0
    @test isnan(sims[1][2][:y])
    return
end

function test_infeasible_model()
    model = SDDP.LinearPolicyGraph(;
        stages = 2,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do node, stage
        @variable(node, x >= 0, SDDP.State, initial_value = 0.0)
        @constraint(node, x.out <= -1)
        @stageobjective(node, x.out)
    end
    ex = ErrorException(
        """
Unable to retrieve solution from node 1.

  Termination status : INFEASIBLE
  Primal status      : NO_SOLUTION
  Dual status        : INFEASIBILITY_CERTIFICATE.

The current subproblem was written to `subproblem_1.mof.json`.

There are two common causes of this error:
  1) you have a mistake in your formulation, or you violated
     the assumption of relatively complete recourse
  2) the solver encountered numerical issues

See https://odow.github.io/SDDP.jl/stable/tutorial/warnings/ for more information.""",
    )
    @test_throws(
        ex,
        SDDP.train(
            model;
            iteration_limit = 1,
            print_level = 0,
            parallel_scheme = SDDP.Serial(),
        ),
    )
    @test isfile("subproblem_1.mof.json")
    rm("subproblem_1.mof.json")
    return
end

function test_infeasible_direct_model()
    model = SDDP.LinearPolicyGraph(;
        stages = 2,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
        direct_mode = true,
    ) do node, stage
        @variable(node, x >= 0, SDDP.State, initial_value = 0.0)
        @constraint(node, x.out <= -1)
        @stageobjective(node, x.out)
    end
    ex = ErrorException(
        """
Unable to retrieve solution from node 1.

  Termination status : INFEASIBLE
  Primal status      : NO_SOLUTION
  Dual status        : INFEASIBILITY_CERTIFICATE.

The current subproblem was written to `subproblem_1.mof.json`.

There are two common causes of this error:
  1) you have a mistake in your formulation, or you violated
     the assumption of relatively complete recourse
  2) the solver encountered numerical issues

See https://odow.github.io/SDDP.jl/stable/tutorial/warnings/ for more information.""",
    )
    @test_throws(
        ex,
        SDDP.train(
            model;
            iteration_limit = 1,
            print_level = 0,
            parallel_scheme = SDDP.Serial(),
        ),
    )
    @test isfile("subproblem_1.mof.json")
    rm("subproblem_1.mof.json")
    return
end

function test_refine_at_similar_nodes()
    model = SDDP.MarkovianPolicyGraph(;
        transition_matrices = [[0.5 0.5], [0.2 0.8; 0.8 0.2]],
        optimizer = HiGHS.Optimizer,
        lower_bound = 0.0,
    ) do sp, index
        stage, markov_state = index
        @variable(sp, x >= 0, SDDP.State, initial_value = 0.0)
        @constraint(sp, x.out >= stage)
        @stageobjective(sp, (stage + markov_state) * x.out)
    end
    SDDP.train(
        model;
        iteration_limit = 1,
        refine_at_similar_nodes = false,
        print_level = 0,
    )
    mi1 = length(model[(1, 1)].bellman_function.global_theta.cuts)
    mi2 = length(model[(1, 2)].bellman_function.global_theta.cuts)
    @test mi1 + mi2 == length(model.most_recent_training_results.log)

    model = SDDP.MarkovianPolicyGraph(;
        transition_matrices = [[0.5 0.5], [0.2 0.8; 0.8 0.2]],
        optimizer = HiGHS.Optimizer,
        lower_bound = 0.0,
    ) do sp, index
        stage, markov_state = index
        @variable(sp, x >= 0, SDDP.State, initial_value = 0.0)
        @constraint(sp, x.out >= stage)
        @stageobjective(sp, (stage + markov_state) * x.out)
    end
    SDDP.train(
        model;
        iteration_limit = 1,
        refine_at_similar_nodes = true,
        print_level = 0,
    )
    @test length(model[(1, 1)].bellman_function.global_theta.cuts) ==
          length(model[(1, 2)].bellman_function.global_theta.cuts) ==
          length(model.most_recent_training_results.log)
    return
end

function test_optimize_hook()
    model = SDDP.LinearPolicyGraph(;
        stages = 2,
        optimizer = HiGHS.Optimizer,
        lower_bound = 0.0,
    ) do sp, t
        @variable(sp, x >= 0, SDDP.State, initial_value = 0)
        @stageobjective(sp, x.out)
    end
    pre_optimize_called = 0
    post_optimize_called = 0
    node = model[1]
    SDDP.pre_optimize_hook(
        node,
    ) do model, node, state, noise, scenario_path, duality_handler
        pre_optimize_called = 1
        return pre_optimize_called
    end
    SDDP.post_optimize_hook(node) do ret
        post_optimize_called = ret + 2
        return
    end
    SDDP.solve_subproblem(
        model,
        node,
        Dict(:x => 0.0),
        nothing,
        Tuple{Int,Any}[(1, nothing)];
        duality_handler = nothing,
    )
    @test pre_optimize_called == 1
    @test post_optimize_called == 3
    return
end

function test_write_log_to_csv()
    model = SDDP.LinearPolicyGraph(;
        stages = 2,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do node, stage
        @variable(node, x >= 0, SDDP.State, initial_value = 0.0)
        @stageobjective(node, x.out)
        SDDP.parameterize(node, [stage], [1.0]) do ω
            return JuMP.set_lower_bound(x.out, ω)
        end
    end
    @test_throws ErrorException SDDP.write_log_to_csv(model, "sddp.csv")
    SDDP.train(model; iteration_limit = 2, print_level = 0)
    SDDP.write_log_to_csv(model, "sddp.csv")
    log = read("sddp.csv", String)
    saved_log = """
    iteration, simulation, bound, time
    """
    for i in 1:length(model.most_recent_training_results.log)
        saved_log *= "$i, 3.0, 3.0, 3.0\n"
    end
    @test replace(log, r"[0-9\.]+\n" => "") ==
          replace(saved_log, r"[0-9\.]+\n" => "")
    rm("sddp.csv")
    return
end

function test_print_log()
    log = SDDP.Log(12, 1.1, -0.5, 123.4, 123, 1, "L", false)
    @test sprint(SDDP.print_iteration, log) ==
          "        12L -5.000000e-01  1.100000e+00  1.234000e+02         1 123\n"
    log = SDDP.Log(1, 1.1, -0.5, 1.0, 1, 1, "L", true)
    @test sprint(SDDP.print_iteration, log) ==
          "†        1L -5.000000e-01  1.100000e+00  1.000000e+00         1   1\n"
    return
end

function test_log_frequency_argument_error()
    model = SDDP.LinearPolicyGraph(;
        stages = 2,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do node, stage
        @variable(node, x >= 0, SDDP.State, initial_value = 0.0)
        @stageobjective(node, x.out)
    end
    @test_throws ArgumentError SDDP.train(model; log_frequency = 0)
    return
end

function test_numerical_difficulty_callback()
    model = SDDP.LinearPolicyGraph(;
        stages = 2,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do node, stage
        @variable(node, x >= 0, SDDP.State, initial_value = 0.0)
        if stage == 2
            @constraint(node, c_infeasible, x.in >= 2)
        end
        @stageobjective(node, x.out)
    end
    callback_called_from = Int[]
    function my_callback(model, node; require_dual)
        push!(callback_called_from, node.index)
        JuMP.delete(node.subproblem, node.subproblem[:c_infeasible])
        JuMP.optimize!(node.subproblem)
        return
    end
    SDDP.set_numerical_difficulty_callback(model, my_callback)
    SDDP.train(model; iteration_limit = 3)
    @test callback_called_from == [2]
    @test model.most_recent_training_results.status == :iteration_limit
    log = model.most_recent_training_results.log
    @test map(l -> l.serious_numerical_issue, log) == [1, 0, 0]
    return
end

function test_Markovian_zero_edges()
    function build_model()
        return SDDP.MarkovianPolicyGraph(;
            transition_matrices = Matrix{Float64}[
                reshape([1.0], 1, 1),
                [0.5 0.5],
                [1.0 0.0; 0.0 1.0],
            ],
            optimizer = HiGHS.Optimizer,
            sense = :Min,
            lower_bound = 0.0,
        ) do sp, node
            t, i = node
            @variable(sp, 0 <= x <= 100, SDDP.State, initial_value = 0)
            @variable(sp, 0 <= u_p <= 200)
            @variable(sp, u_o >= 0)
            @constraint(sp, x.out == x.in + u_p + u_o - (200 * i - 100))
            @stageobjective(sp, (100 + i) * u_p + 300 * u_o + 50 * x.out)
            return
        end
    end
    # refine_at_similar_nodes = true
    model = build_model()
    sp_21, sp_22 = model[(2, 1)].subproblem, model[(2, 2)].subproblem
    n_21 = num_constraints(sp_21; count_variable_in_set_constraints = false)
    n_22 = num_constraints(sp_22; count_variable_in_set_constraints = false)
    @test n_21 == n_22 == 1
    SDDP.train(model; iteration_limit = 1, print_level = 0)
    n_21 = num_constraints(sp_21; count_variable_in_set_constraints = false)
    n_22 = num_constraints(sp_22; count_variable_in_set_constraints = false)
    @test n_21 == n_22 == 2
    SDDP.train(model; print_level = 0, add_to_existing_cuts = true)
    @test isapprox(SDDP.calculate_bound(model), 6.565e4; atol = 1e-4)
    # refine_at_similar_nodes = false
    model = build_model()
    sp_21, sp_22 = model[(2, 1)].subproblem, model[(2, 2)].subproblem
    n_21 = num_constraints(sp_21; count_variable_in_set_constraints = false)
    n_22 = num_constraints(sp_22; count_variable_in_set_constraints = false)
    @test n_21 == n_22 == 1
    SDDP.train(
        model;
        iteration_limit = 1,
        print_level = 0,
        refine_at_similar_nodes = false,
    )
    n_21 = num_constraints(sp_21; count_variable_in_set_constraints = false)
    n_22 = num_constraints(sp_22; count_variable_in_set_constraints = false)
    @test 1 <= n_21 <= 2 && 1 <= n_22 <= 2 && n_21 != n_22
    SDDP.train(
        model;
        print_level = 0,
        add_to_existing_cuts = true,
        refine_at_similar_nodes = false,
    )
    @test isapprox(SDDP.calculate_bound(model), 6.565e4; atol = 1e-4)
    return
end

function test_root_node_risk_measure()
    model = SDDP.LinearPolicyGraph(;
        stages = 3,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do sp, stage
        @variable(sp, 0 <= x <= 100, SDDP.State, initial_value = 0)
        @variable(sp, 0 <= u_p <= 200)
        @variable(sp, u_o >= 0)
        @variable(sp, w)
        SDDP.parameterize(ω -> JuMP.fix(w, ω), sp, [100, 300])
        @constraint(sp, x.out == x.in + u_p + u_o - w)
        @stageobjective(sp, 100 * u_p + 300 * u_o + 50 * x.out)
    end
    SDDP.train(model; root_node_risk_measure = SDDP.WorstCase())
    @test isapprox(model.most_recent_training_results.log[end].bound, 107500.0)
    @test isapprox(
        SDDP.calculate_bound(model; risk_measure = SDDP.WorstCase()),
        107500.0,
    )
    @test isapprox(
        SDDP.calculate_bound(model; risk_measure = SDDP.Expectation()),
        85000.0,
    )
    return
end

end  # module

TestAlgorithm.runtests()
