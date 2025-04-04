#  Copyright (c) 2017-25, Oscar Dowson and SDDP.jl contributors         #src
#  This Source Code Form is subject to the terms of the Mozilla Public  #src
#  License, v. 2.0. If a copy of the MPL was not distributed with this  #src
#  file, You can obtain one at http://mozilla.org/MPL/2.0/.             #src

# # Vehicle location

# This problem is a version of the Ambulance dispatch problem. A hospital is
# located at 0 on the number line that stretches from 0 to 100. Ambulance bases
# are located at points 20, 40, 60, 80, and 100. When not responding to a call,
# Ambulances must be located at a base, or the hospital. In this example there
# are three ambulances.

# Example location:
#
#     H       B       B       B       B       B
#     0 ---- 20 ---- 40 ---- 60 ---- 80 ---- 100

# Each stage, a call comes in from somewhere on the number line. The agent must
# decide which ambulance to dispatch. They pay the cost of twice the driving
# distance. If an ambulance is not dispatched in a stage, the ambulance can be
# relocated to a different base in preparation for future calls. This incurs a
# cost of the driving distance.

using SDDP
import HiGHS
import Test

function vehicle_location_model(duality_handler)
    hospital_location = 0
    bases = vcat(hospital_location, [20, 40, 60, 80, 100])
    vehicles = [1, 2, 3]
    requests = 0:10:100
    shift_cost(src, dest) = abs(src - dest)
    function dispatch_cost(base, request)
        return 2 * (abs(request - hospital_location) + abs(request - base))
    end
    ## Initial state of emergency vehicles at bases. All ambulances start at the
    ## hospital.
    initial_state(b, v) = b == hospital_location ? 1.0 : 0.0
    model = SDDP.LinearPolicyGraph(;
        stages = 10,
        lower_bound = 0.0,
        optimizer = HiGHS.Optimizer,
    ) do sp, t
        ## Current location of each vehicle at each base.
        @variable(
            sp,
            0 <= location[b = bases, v = vehicles] <= 1,
            SDDP.State,
            initial_value = initial_state(b, v)
        )
        @variables(sp, begin
            ## Which vehicle is dispatched?
            0 <= dispatch[bases, vehicles] <= 1, Bin
            ## Shifting vehicles between bases: [src, dest, vehicle]
            0 <= shift[bases, bases, vehicles] <= 1, Bin
        end)
        ## Flow of vehicles in and out of bases:
        @expression(
            sp,
            base_balance[b in bases, v in vehicles],
            location[b, v].in - dispatch[b, v] - sum(shift[b, :, v]) +
            sum(shift[:, b, v])
        )
        @constraints(
            sp,
            begin
                ## Only one vehicle dispatched to call.
                sum(dispatch) == 1
                ## Can only dispatch vehicle from base if vehicle is at that base.
                [b in bases, v in vehicles],
                dispatch[b, v] <= location[b, v].in
                ## Can only shift vehicle if vehicle is at that src base.
                [b in bases, v in vehicles],
                sum(shift[b, :, v]) <= location[b, v].in
                ## Can only shift vehicle if vehicle is not being dispatched.
                [b in bases, v in vehicles],
                sum(shift[b, :, v]) + dispatch[b, v] <= 1
                ## Can't shift to same base.
                [b in bases, v in vehicles], shift[b, b, v] == 0
                ## Update states for non-home/non-hospital bases.
                [b in bases[2:end], v in vehicles],
                location[b, v].out == base_balance[b, v]
                ## Update states for home/hospital bases.
                [v in vehicles],
                location[hospital_location, v].out ==
                base_balance[hospital_location, v] + sum(dispatch[:, v])
            end
        )
        SDDP.parameterize(sp, requests) do request
            @stageobjective(
                sp,
                sum(
                    ## Distance to travel from base to emergency and then to hospital.
                    dispatch[b, v] * dispatch_cost(b, request) +
                    ## Distance travelled by vehicles relocating bases.
                    sum(
                        shift_cost(b, dest) * shift[b, dest, v] for
                        dest in bases
                    ) for b in bases, v in vehicles
                )
            )
        end
    end
    if get(ARGS, 1, "") == "--write"
        ## Run `$ julia vehicle_location.jl --write` to update the benchmark
        ## model directory
        model_dir = joinpath(@__DIR__, "..", "..", "..", "benchmarks", "models")
        SDDP.write_to_file(
            model,
            joinpath(model_dir, "vehicle_location.sof.json.gz");
            test_scenarios = 100,
        )
        exit(0)
    end
    SDDP.train(
        model;
        iteration_limit = 20,
        log_frequency = 10,
        cut_deletion_minimum = 100,
        duality_handler = duality_handler,
    )
    Test.@test SDDP.calculate_bound(model) >= 1000
    return
end

## TODO(odow): find out why this fails
## vehicle_location_model(SDDP.ContinuousConicDuality())
