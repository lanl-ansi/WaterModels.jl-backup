# Define common LRD (linear relaxation- and direction-based) implementations of water
# distribution network constraints, which use directed flow variables.


########################################## PIPES ##########################################

function constraint_pipe_head_loss(
    wm::AbstractLRDModel, n::Int, a::Int, node_fr::Int, node_to::Int, exponent::Float64,
    L::Float64, r::Float64, q_max_reverse::Float64, q_min_forward::Float64)
    # Get the variable for flow directionality.
    y = var(wm, n, :y_pipe, a)

    # Get variables for positive flow and head difference.
    qp, dhp = var(wm, n, :qp_pipe, a), var(wm, n, :dhp_pipe, a)

    # Get the corresponding set of positive flow breakpoints.
    breakpoints_p = get_pipe_flow_breakpoints_positive(ref(wm, n, :pipe, a))

    # Loop over consequential points (i.e., those that have nonzero head loss).
    for flow_breakpoint in filter(x -> x > 0.0, breakpoints_p)
        # Add a linear outer approximation of the convex relaxation at `flow_breakpoint`.
        lhs = _calc_head_loss_oa(qp, y, flow_breakpoint, exponent)

        # Add outer-approximation of the head loss constraint.
        c = JuMP.@constraint(wm.model, r * lhs <= dhp / L)

        # Append the :pipe_head_loss constraint array.
        append!(con(wm, n, :pipe_head_loss)[a], [c])
    end

    # Get the corresponding min/max positive directed flows (when active).
    qp_min_forward, qp_max = max(0.0, q_min_forward), maximum(breakpoints_p)

    if qp_min_forward != qp_max
        # Compute scaled version of the head loss overapproximation.
        f_1, f_2 = r * qp_min_forward^exponent, r * qp_max^exponent
        f_slope = (f_2 - f_1) / (qp_max - qp_min_forward)
        f_lb_line = f_slope * (qp - qp_min_forward * y) + f_1 * y

        # Add upper-bounding line of the head loss constraint.
        c = JuMP.@constraint(wm.model, dhp / L <= f_lb_line)

        # Append the :pipe_head_loss constraint array.
        append!(con(wm, n, :pipe_head_loss)[a], [c])
    end

    # Get variables for negative flow and head difference.
    qn, dhn = var(wm, n, :qn_pipe, a), var(wm, n, :dhn_pipe, a)

    # Get the corresponding set of negative flow breakpoints (negated).
    breakpoints_n = -get_pipe_flow_breakpoints_negative(ref(wm, n, :pipe, a))

    # Loop over consequential points (i.e., those that have nonzero head loss).
    for flow_breakpoint in filter(x -> x > 0.0, breakpoints_n)
        # Add a linear outer approximation of the convex relaxation at `flow_breakpoint`.
        lhs = _calc_head_loss_oa(qn, 1.0 - y, flow_breakpoint, exponent)

        # Add outer-approximation of the head loss constraint.
        c = JuMP.@constraint(wm.model, r * lhs <= dhn / L)

        # Append the :pipe_head_loss constraint array.
        append!(con(wm, n, :pipe_head_loss)[a], [c])
    end

    # Get the corresponding maximum negative directed flow (when active).
    qn_min_forward, qn_max = max(0.0, -q_max_reverse), maximum(breakpoints_n)

    if qn_min_forward != qn_max
        # Compute scaled version of the head loss overapproximation.
        f_1, f_2 = r * qn_min_forward^exponent, r * qn_max^exponent
        f_slope = (f_2 - f_1) / (qn_max - qn_min_forward)
        f_lb_line = f_slope * (qn - qn_min_forward * (1.0 - y)) + f_1 * (1.0 - y)

        # Add upper-bounding line of the head loss constraint.
        c = JuMP.@constraint(wm.model, dhn / L <= f_lb_line)

        # Append the :pipe_head_loss constraint array.
        append!(con(wm, n, :pipe_head_loss)[a], [c])
    end
end


function constraint_on_off_des_pipe_head_loss(
    wm::AbstractLRDModel, n::Int, a::Int, node_fr::Int, node_to::Int, exponent::Float64,
    L::Float64, r::Float64, q_max_reverse::Float64, q_min_forward::Float64)
    # Get the number of breakpoints for the pipe.
    num_breakpoints = get(wm.ext, :pipe_breakpoints, 1)

    # Get the variable for flow directionality.
    y, z = var(wm, n, :y_des_pipe, a), var(wm, n, :z_des_pipe, a)

    # Get variables for positive flow and head difference.
    qp, dhp = var(wm, n, :qp_des_pipe, a), var(wm, n, :dhp_des_pipe, a)
    qp_min_forward, qp_ub = max(0.0, q_min_forward), JuMP.upper_bound(qp)

    # Loop over breakpoints strictly between the lower and upper variable bounds.
    for pt in range(qp_min_forward, stop = JuMP.upper_bound(qp), length = num_breakpoints+2)[2:end-1]
        # Get a linear outer approximation of the convex relaxation at `pt`.
        lhs = _calc_head_loss_oa(qp, z, pt, exponent)

        # Add outer-approximation of the head loss constraint.
        c = JuMP.@constraint(wm.model, r * lhs <= dhp / L)

        # Append the :on_off_des_pipe_head_loss constraint array.
        append!(con(wm, n, :on_off_des_pipe_head_loss)[a], [c])
    end

    # Get the upper-bounding line for the qp curve.
    if qp_min_forward < qp_ub
        dhp_1, dhp_2 = r * qp_min_forward^exponent, r * qp_ub^exponent
        dhp_slope = (dhp_2 - dhp_1) * inv(qp_ub - qp_min_forward)
        dhp_ub_line_y = dhp_slope * (qp - qp_min_forward * y) + dhp_1 * y
        dhp_ub_line_z = dhp_slope * (qp - qp_min_forward * z) + dhp_1 * z

        # Add upper-bounding lines of the head loss constraint.
        c_1 = JuMP.@constraint(wm.model, dhp / L <= dhp_ub_line_y)
        c_2 = JuMP.@constraint(wm.model, dhp / L <= dhp_ub_line_z)

        # Append the :on_off_des_pipe_head_loss constraint array.
        append!(con(wm, n, :on_off_des_pipe_head_loss)[a], [c_1, c_2])
    end

    # Get variables for negative flow and head difference.
    qn, dhn = var(wm, n, :qn_des_pipe, a), var(wm, n, :dhn_des_pipe, a)
    qn_min_forward, qn_ub = max(0.0, -q_max_reverse), JuMP.upper_bound(qn)

    # Loop over breakpoints strictly between the lower and upper variable bounds.
    for pt in range(qn_min_forward, stop = JuMP.upper_bound(qn), length = num_breakpoints+2)[2:end-1]
        # Get a linear outer approximation of the convex relaxation at `pt`.
        lhs = _calc_head_loss_oa(qn, z, pt, exponent)

        # Add lower-bounding line of the head loss constraint.
        c = JuMP.@constraint(wm.model, r * lhs <= dhn / L)

        # Append the :on_off_des_pipe_head_loss constraint array.
        append!(con(wm, n, :on_off_des_pipe_head_loss)[a], [c])
    end

    # Get the lower-bounding line for the qn curve.
    if qn_min_forward < qn_ub
        dhn_1, dhn_2 = r * qn_min_forward^exponent, r * qn_ub^exponent
        dhn_slope = (dhn_2 - dhn_1) * inv(qn_ub - qn_min_forward)
        dhn_ub_line_y = dhn_slope * (qn - qn_min_forward * (1.0 - y)) + dhn_1 * (1.0 - y)
        dhn_ub_line_z = dhn_slope * (qn - qn_min_forward * z) + dhn_1 * z

        # Add upper-bounding line of the head loss constraint.
        c_1 = JuMP.@constraint(wm.model, dhn / L <= dhn_ub_line_y)
        c_2 = JuMP.@constraint(wm.model, dhn / L <= dhn_ub_line_z)

        # Append the :on_off_des_pipe_head_loss constraint array.
        append!(con(wm, n, :on_off_des_pipe_head_loss)[a], [c_1, c_2])
    end
end


########################################## PUMPS ##########################################

"Add constraints associated with modeling a pump's head gain."
function constraint_on_off_pump_head_gain(
    wm::AbstractLRDModel, n::Int, a::Int, node_fr::Int,
    node_to::Int, q_min_forward::Float64)
    # Get variables for positive flow, head difference, and pump status.
    qp, g, z = var(wm, n, :qp_pump, a), var(wm, n, :g_pump, a), var(wm, n, :z_pump, a)

    # Calculate the head curve function and its derivative.
    head_curve_func = _calc_head_curve_function(ref(wm, n, :pump, a))
    head_curve_deriv = _calc_head_curve_derivative(ref(wm, n, :pump, a))
    breakpoints = get_pump_flow_breakpoints(ref(wm, n, :pump, a))
    qp_min, qp_max = minimum(breakpoints), maximum(breakpoints)

    # Loop over breakpoints strictly between the lower and upper variable bounds.
    for flow_breakpoint in breakpoints
        # Compute head gain and derivative at the point.
        f, df = head_curve_func(flow_breakpoint), head_curve_deriv(flow_breakpoint)

        # Add the outer-approximation constraint for the pump.
        c_1 = JuMP.@constraint(wm.model, g <= f * z + df * (qp - flow_breakpoint * z))

        # Append the :on_off_pump_head_gain constraint array.
        append!(con(wm, n, :on_off_pump_head_gain)[a], [c_1])
    end

    if qp_min < qp_max
        # Collect relevant expressions for the lower-bounding line.
        g_1, g_2 = head_curve_func(qp_min), head_curve_func(qp_max)
        g_slope = (g_2 - g_1) / (qp_max - qp_min)
        g_lb_line = g_slope * (qp - qp_min * z) + g_1 * z

        # Add the lower-bounding line for the head gain curve.
        c_2 = JuMP.@constraint(wm.model, g_lb_line <= g)

        # Append the :on_off_pump_head_gain constraint array.
        append!(con(wm, n, :on_off_pump_head_gain)[a], [c_2])
    end
end