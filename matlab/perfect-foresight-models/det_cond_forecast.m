function data_set = det_cond_forecast(varargin)
% Computes conditional forecasts using the extended path method.
%
% INPUTS
%  o plan                 [structure]   A structure describing the different shocks and the endogenous varibales, the date of the shocks and the path of the shock.
%                                       The plan structure is created by the functions init_plan, basic_plan and flip_plan
%  o [dataset]            [dseries]     A dserie containing the initial values of the shocks and the endogenous variables (usually the dseries generated by the smoother).
%  o [starting_date]      [dates]       The first date of the forecast.
%
%
% OUTPUTS
%  dataset                [dseries]     Returns a dseries containing the forecasted endgenous variables and shocks
%
%
% Copyright (C) 2013-2016 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.

global options_ oo_ M_
pp = 2;
initial_conditions = oo_.steady_state;
verbosity = options_.verbosity;
if options_.periods == 0
	options_.periods = 25;
end;
%We have to get an initial guess for the conditional forecast 
% and terminal conditions for the non-stationary variables, we
% use the first order approximation of the rational expectation solution.
if ~isfield(oo_,'dr') || (isempty(oo_.dr))
    fprintf('computing the first order solution of the model as initial guess...');
    dr = struct();
    oo_.dr=set_state_space(dr,M_,options_);
    options_.order = 1;
    [dr,Info,M_,options_,oo_] = resol(0,M_,options_,oo_);
    fprintf('done\n');
end
b_surprise = 0;
b_pf = 0;
surprise = 0;
pf = 0;
is_shock = [];
is_constraint = [];
if length(varargin) > 3
    % regular way to call
    constrained_paths = varargin{1};
    max_periods_simulation = size(constrained_paths, 2);
    constrained_vars = varargin{2};
    options_cond_fcst = varargin{3};
    constrained_perfect_foresight = varargin{4};
    constraint_index = cell(max_periods_simulation,1);
    nvars = length(constrained_vars);
    for i = 1:max_periods_simulation
        constraint_index{i} = 1:nvars;
    end;
    direct_mode = 0;
    shocks_present = 0;
    controlled_varexo = options_cond_fcst.controlled_varexo;
    nvarexo = size(controlled_varexo, 1);
    options_cond_fcst.controlled_varexo = zeros(nvarexo,1);
    exo_names = cell(M_.exo_nbr,1);
    for i = 1:M_.exo_nbr
        exo_names{i} = deblank(M_.exo_names(i,:));
    end
    for i = 1:nvarexo
        j = find(strcmp(controlled_varexo(i,:), exo_names));
        if ~isempty(j)
            options_cond_fcst.controlled_varexo(i) = j;
        else
            error(['Unknown exogenous variable ' controlled_varexo(i,:)]);
        end
    end
        
else
    % alternative way to call: plan, dset, dates_of_frcst
    plan = varargin{1};
    if length(varargin) >= 2
        dset = varargin{2};
        if ~isa(dset,'dseries')
            error('the second argmuent should be a dseries');
        end
        if length(varargin) >= 3
            range = varargin{3};
            if ~isa(range,'dates')
                error('the third argmuent should be a dates');
            end
            %if (range(range.ndat) > dset.time(dset.nobs) )
            if (range(range.ndat) > dset.dates(dset.nobs)+1 )
                s1 = strings(dset.dates(dset.nobs));
                s2 = strings(range(range.ndat));
                error(['the dseries ' inputname(2) ' finish at time ' s1{1} ' before the last period of forecast ' s2{1}]);
            end
            
            sym_dset = dset(dates(-range(1)):dates(range(range.ndat)));
            periods = options_.periods + M_.maximum_lag + M_.maximum_lead;
			total_periods = periods + range.ndat;
            if isfield(oo_, 'exo_simul')
                if size(oo_.exo_simul, 1) ~= total_periods
                    oo_.exo_simul = repmat(oo_.exo_steady_state',total_periods,1);
                end
            else
                oo_.exo_simul = repmat(oo_.exo_steady_state',total_periods,1);
            end
            
            oo_.endo_simul = repmat(oo_.steady_state, 1, total_periods);
            
            for i = 1:sym_dset.vobs
                iy = find(strcmp(strtrim(sym_dset.name{i}), strtrim(plan.endo_names)));
                if ~isempty(iy)
                    oo_.endo_simul(iy,1:sym_dset.nobs) = sym_dset.data(:, i);
                    initial_conditions(iy) = sym_dset.data(1, i);
                 else
                     ix = find(strcmp(strtrim(sym_dset.name{i}), strtrim(plan.exo_names)));
                     if ~isempty(ix) 
                         oo_.exo_simul(1, ix) = sym_dset.data(1, i)';
                    else
                        %warning(['The variable ' sym_dset.name{i} ' in the dataset ' inputname(2) ' is not a endogenous neither an exogenous variable!!']);
                    end
                 end
            end
            for i = 1:length(M_.aux_vars)
                if M_.aux_vars(i).type == 1 %lag variable
                    iy = find(strcmp(deblank(M_.endo_names(M_.aux_vars(i).orig_index,:)), sym_dset.name));
                    if ~isempty(iy)
                        oo_.endo_simul(M_.aux_vars(i).endo_index, 1:sym_dset.nobs) = dset(dates(range(1) + (M_.aux_vars(i).orig_lead_lag - 1))).data(:,iy);
                        initial_conditions(M_.aux_vars(i).endo_index) = dset(dates(range(1) + (M_.aux_vars(i).orig_lead_lag - 1))).data(:,iy);
                    else
                        warning(['The variable auxiliary ' M_.endo_names(M_.aux_vars(i).endo_index, :) ' associated to the variable ' M_.endo_names(M_.aux_vars(i).orig_index,:) ' do not appear in the dataset']);
                    end
                else
                    oo_.endo_simul(M_.aux_vars(i).endo_index, 1:sym_dset.nobs) = repmat(oo_.steady_state(M_.aux_vars(i).endo_index), 1, range.ndat + 1);
                end
            end
            %Compute the initial path using the the steady-state
            % steady-state
            %for jj = 2 : (options_.periods + 2)
			for jj = 2 : (range.ndat + 2)
              oo_.endo_simul(:, jj) = oo_.steady_state;  
            end
            missings = isnan(oo_.endo_simul(:,1));
            if any(missings)
                for jj = 1:M_.endo_nbr
                    if missings(jj)
                        oo_.endo_simul(jj,1) = oo_.steady_state(jj,1);
                    end
                end
            end

            if options_.bytecode
                save_options_dynatol_f = options_.dynatol.f;
                options_.dynatol.f = 1e-7;
                [Info, endo, exo] = bytecode('extended_path', plan, oo_.endo_simul, oo_.exo_simul, M_.params, oo_.steady_state, options_.periods);
                options_.dynatol.f = save_options_dynatol_f;

                if Info == 0
                  oo_.endo_simul = endo;
                  oo_.exo_simul = exo;
                end
                endo = endo';
                endo_l = size(endo(1+M_.maximum_lag:end,:),1);	
                jrng = dates(plan.date(1)):dates(plan.date(1)+endo_l);
                data_set = dseries(nan(endo_l, dset.vobs), plan.date(1), dset.name);
                for i = 1:length(dset.name)
                    pos = find(strcmp(dset.name{i},plan.endo_names));
                    if ~isempty(pos)
                        data_set.(dset.name{i}) = dseries(endo(1+M_.maximum_lag:end,pos), plan.date(1), dset.name{i});
                    else
                        pos = find(strcmp(dset.name{i},plan.exo_names));
                        if ~isempty(pos)
                           data_set{dset.name{i}} = dseries(exo(1+M_.maximum_lag:end,pos), plan.date(1),dset.name{i});
                        end
                    end
                end
                data_set = [dset(dset.dates(1):(plan.date(1)-1)) ; data_set];
                for i=1:M_.exo_nbr
                    pos = find(strcmp(strtrim(M_.exo_names(i,:)),dset.name));
                    if isempty(pos)
                        data_set{strtrim(M_.exo_names(i,:))} = dseries(exo(1+M_.maximum_lag:end,i), plan.date(1), strtrim(M_.exo_names(i,:)));
                    else
                        data_set{strtrim(M_.exo_names(i,:))}(plan.date(1):plan.date(1)+ (size(exo, 1) - M_.maximum_lag)) = exo(1+M_.maximum_lag:end,i);
                    end
                end
                data_set = merge(dset(dset.dates(1):(plan.date(1)-1)), data_set);
                return;
                union_names = union(data_set.name, dset.name);
                dif = setdiff(union_names, data_set.name);
                data_set_nobs = data_set.nobs;
                for i = 1:length(dif)
                    data_set{dif{i}} = dseries(nan(data_set_nobs,1),plan.date(1), dif(i), dif(i));
                end;
                dif = setdiff(union_names, dset.name);
                dset_nobs = dset.nobs;
                for i = 1:length(dif)
                    dset{dif{i}} = dseries(nan(dset_nobs,1),dset.dates(1), dif(i), dif(i));
                end;
                data_set = [dset(dset.dates(1):(plan.date(1)-1)) ; data_set];
                return;
            end;
        else
           error('impossible case'); 
        end;
            
    else
        oo_.exo_simul = repmat(oo_.exo_steady_state',options_.periods+2,1);
        oo_.endo_simul = repmat(oo_.steady_state, 1, options_.periods+2);
    end
    
    direct_mode = 1;
    constrained_paths = plan.constrained_paths_;
    constrained_vars = plan.constrained_vars_;
    options_cond_fcst = plan.options_cond_fcst_;
    constrained_perfect_foresight = plan.constrained_perfect_foresight_;
    constrained_periods = plan.constrained_date_;
    if ~isempty(plan.shock_paths_)
        shock_paths = plan.shock_paths_;
        shock_vars = plan.shock_vars_;
        shock_perfect_foresight = plan.shock_perfect_foresight_;
        shock_periods = plan.shock_date_;
        shocks_present = 1;
    else
        shocks_present = 0;
    end
    
    total_periods = plan.date;
    
end;

if ~isfield(options_cond_fcst,'periods') || isempty(options_cond_fcst.periods)
    options_cond_fcst.periods = 100;
end

options_.periods = 10;   

if direct_mode == 1
    n_periods = length(constrained_periods);
    is_constraint = zeros(length(total_periods), n_periods);
    constrained_paths_cell = constrained_paths;
    clear constrained_paths;
    constrained_paths = zeros(n_periods, length(total_periods));
    max_periods_simulation = 0;
    for i = 1:n_periods
        period_i = constrained_periods{i};
        %period_i
        tp = total_periods(1);
        if size(period_i) > 1
            init_periods = period_i(1);
            tp_end = period_i(end);
        else
            init_periods = period_i;
            tp_end = period_i;
        end;
        tp0 = tp;
        while tp < init_periods
            tp = tp + 1;
        end
        j = 0;
        while tp <= tp_end
            is_constraint(tp - tp0 + 1, i) = 1;
            constrained_paths(i, tp - tp0 + 1) = constrained_paths_cell{i}(j + 1);
            tp = tp + 1;
            j = j + 1;
        end;
        if tp - tp0 > max_periods_simulation 
            max_periods_simulation = tp - tp0;
        end;
    end
    n_nnz = length(sum(is_constraint,2));
    if n_nnz > 0
        constraint_index = cell(n_nnz,1);
        for i= 1:n_nnz
            constraint_index{i} = find(is_constraint(i,:));
        end;
    end;
    if shocks_present
        n_periods = length(shock_periods);
        shock_paths_cell = shock_paths;
        clear shock_paths;
        shock_paths = zeros(n_periods, length(total_periods));
        is_shock = zeros(length(total_periods), n_periods);
        for i = 1:n_periods
            period_i = shock_periods{i};
            %period_i
            tp = total_periods(1);
            if size(period_i) > 1
                init_periods = period_i(1);
                tp_end = period_i(end);
            else
                init_periods = period_i;
                tp_end = period_i;
            end;
            tp0 = tp;
            while tp < init_periods
                tp = tp + 1;
            end
            j = 0;
            while tp <= tp_end
                is_shock(tp - tp0 + 1, i) = 1;
                shock_paths(i, tp - tp0 + 1) = shock_paths_cell{i}(j + 1);
                tp = tp + 1;
                j = j + 1;
            end;
            if tp - tp0 > max_periods_simulation 
                max_periods_simulation = tp - tp0;
            end;
        end;
        n_nnz = length(sum(is_shock,2));
        if n_nnz > 0
            shock_index = cell(n_nnz, 1);
            for i= 1:n_nnz
                shock_index{i} = find(is_shock(i,:));
            end;
        end
    end
else
    is_constraint = ones(size(constrained_paths));
end



maximum_lag = M_.maximum_lag;

ys = oo_.steady_state;
ny = size(ys,1);
xs = [oo_.exo_steady_state ; oo_.exo_det_steady_state];
nx = size(xs,1);

constrained_periods = max_periods_simulation;   
n_endo_constrained = size(constrained_vars,1);
if isfield(options_cond_fcst,'controlled_varexo')
    n_control_exo = size(options_cond_fcst.controlled_varexo, 1);
    if n_control_exo ~= n_endo_constrained
        error(['det_cond_forecast: the number of exogenous controlled variables (' int2str(n_control_exo) ') has to be equal to the number of constrained endogenous variabes (' int2str(n_endo_constrained) ')'])
    end;
else
    error('det_cond_forecast: to run a deterministic conditional forecast you have to specified the exogenous variables controlled using the option controlled_varexo in forecast command');
end;

% if n_endo_constrained == 0
%     options_.ep.use_bytecode = options_.bytecode;
%     data_set = extended_path(initial_conditions, max_periods_simulation);
% end

if length(varargin) >= 1
    controlled_varexo = options_cond_fcst.controlled_varexo;
else
    exo_names = M_.exo_names;
    controlled_varexo = zeros(1,n_control_exo);
    for i = 1:nx
        for j=1:n_control_exo
            if strcmp(deblank(exo_names(i,:)), deblank(options_cond_fcst.controlled_varexo(j,:)))
                controlled_varexo(j) = i;
            end
        end
    end
end

%todo check if zero => error message

save_options_initval_file = options_.initval_file;
options_.initval_file = '__';

[pos_constrained_pf, junk] = find(constrained_perfect_foresight);
indx_endo_solve_pf = constrained_vars(pos_constrained_pf);
if isempty(indx_endo_solve_pf)
    pf = 0;
else
    pf = length(indx_endo_solve_pf);
end;
indx_endo_solve_surprise = setdiff(constrained_vars, indx_endo_solve_pf);

if isempty(indx_endo_solve_surprise)
    surprise = 0;
else
    surprise = length(indx_endo_solve_surprise);
end;


eps = options_.solve_tolf;
maxit = options_.simul.maxit;


past_val = 0;
save_options_periods = options_.periods;
options_.periods = options_cond_fcst.periods;
save_options_dynatol_f = options_.dynatol.f;
options_.dynatol.f = 1e-8;
eps1  = 1e-7;%1e-4;
exo = zeros(maximum_lag + options_cond_fcst.periods, nx);
endo = zeros(maximum_lag + options_cond_fcst.periods, ny);
endo(1,:) = oo_.steady_state';


% if all the endogenous paths are perfectly anticipated we do not need to
% implement the extended path
if pf && ~surprise
    time_index_constraint = maximum_lag + 1:maximum_lag + constrained_periods;
    second_system_size = pf * constrained_periods;
    J = zeros(second_system_size,second_system_size);
    r = zeros(second_system_size,1);
    indx_endo = zeros(second_system_size,1);
    col_count = 1;
    for j = 1:length(constrained_vars)
        indx_endo(col_count : col_count + constrained_periods - 1) = constrained_vars(j) + (time_index_constraint - 1) * ny;
        col_count = col_count + constrained_periods;
    end;
    oo_=make_ex_(M_,options_,oo_);
    oo_=make_y_(M_,options_,oo_);
    it = 1;
    convg = 0;
    normra = 1e+50;
    while ~convg && it <= maxit
        disp('---------------------------------------------------------------------------------------------');
        disp(['iteration ' int2str(it)]);
        not_achieved = 1;
        alpha = 1;
        while not_achieved
            simul();
            result = sum(sum(isfinite(oo_.endo_simul(:,time_index_constraint)))) == ny * constrained_periods;
            if result
                y = oo_.endo_simul(constrained_vars, time_index_constraint);
                ys = oo_.endo_simul(indx_endo);
                col_count = 1;
                for j = 1:length(constrained_vars)
                    y = oo_.endo_simul(constrained_vars(j), time_index_constraint);
                    r(col_count:col_count+constrained_periods - 1) = (y - constrained_paths(j,1:constrained_periods))';
                    col_count = col_count + constrained_periods;
                end;
                normr = norm(r, 1);
            end;
            if (~oo_.deterministic_simulation.status || ~result || normr > normra) && it > 1
                not_achieved = 1;
                alpha = alpha / 2;
                col_count = 1;
                for j = controlled_varexo'
                    oo_.exo_simul(time_index_constraint,j) = (old_exo(:,j) + alpha * D_exo(col_count: (col_count + constrained_periods - 1)));
                    col_count = col_count + constrained_periods;
                end;
                disp(['Divergence in  Newton: reducing the path length alpha=' num2str(alpha)]);
                oo_.endo_simul = repmat(oo_.steady_state, 1, options_cond_fcst.periods + 2);
            else
                not_achieved = 0;
            end;
        end;
        
        per = 30;
        z = oo_.endo_simul(:, 1 : per + 2 );
        zx = oo_.exo_simul(1: per + 2,:);
        g1 = spalloc(M_.endo_nbr * (per ), M_.endo_nbr * (per ), 3* M_.endo_nbr * per );
        g1_x = spalloc(M_.endo_nbr * (per ), M_.exo_nbr, M_.endo_nbr * (per )* M_.exo_nbr );
        lag_indx = find(M_.lead_lag_incidence(1,:));
        cur_indx = M_.endo_nbr + find(M_.lead_lag_incidence(2,:));
        lead_indx = 2 * M_.endo_nbr + find(M_.lead_lag_incidence(3,:));
        cum_l1 = 0;
        cum_index_d_y_x = [];
        indx_x = [];
        for k = 1 : per
            if k == 1
                if (isfield(M_,'block_structure'))
                    data1 = M_.block_structure.block;
                    Size = length(M_.block_structure.block);
                else
                    data1 = M_;
                    Size = 1;
                end;
                data1 = M_;
                if (options_.bytecode)
                    [chck, zz, data1]= bytecode('dynamic','evaluate', z, zx, M_.params, oo_.steady_state, k, data1);
                else
                    [zz, g1b] = feval([M_.fname '_dynamic'], z', zx, M_.params, oo_.steady_state, k);
                    data1.g1_x = g1b(:,end - M_.exo_nbr + 1:end);
                    data1.g1 = g1b(:,1 : end - M_.exo_nbr);
                    chck = 0;
                end;
                mexErrCheck('bytecode', chck);
            end;
            if k == 1 
                g1(1:M_.endo_nbr,-M_.endo_nbr + [cur_indx lead_indx]) = data1.g1(:,M_.nspred + 1:end);
            elseif k == per
                g1(M_.endo_nbr * (k - 1) + 1 :M_.endo_nbr * k,M_.endo_nbr * (k -2) + [lag_indx cur_indx]) = data1.g1(:,1:M_.nspred + M_.endo_nbr);
            else
                g1(M_.endo_nbr * (k - 1) + 1 :M_.endo_nbr * k, M_.endo_nbr * (k -2) + [lag_indx cur_indx lead_indx]) = data1.g1;
            end;
            l2 = 1;
            pf_c = 1;
            if k <= constrained_periods
                for l = constraint_index{k}
                    l1 = controlled_varexo(l);
                    g1_x(M_.endo_nbr * (k - 1) + 1:M_.endo_nbr * k,1 + cum_l1) = data1.g1_x(:,l1);
                    if k == 1
                        indx_x(l2) = l ;
                        l2 = l2 + 1;
                        for ii = 2:constrained_periods
                            indx_x(l2) = length(controlled_varexo) + pf * (ii - 2) + constraint_index{k + ii - 1}(pf_c);
                            l2 = l2 + 1;
                        end;
                        pf_c = pf_c + 1;
                        cum_index_d_y_x = [cum_index_d_y_x; constrained_vars(l)];
                    else
                        cum_index_d_y_x = [cum_index_d_y_x; constrained_vars(l) + (k - 1) * M_.endo_nbr];
                    end
                    cum_l1 = cum_l1 + length(l1);
                end;
            end;
        end;
        
        d_y_x = - g1 \ g1_x;

        cum_l1 = 0;
        count_col = 1;
        cum_index_J  = 1:length(cum_index_d_y_x(indx_x));
        J= zeros(length(cum_index_J));
        for j1 = 1:length(controlled_varexo)
            cum_l1 = 0;
            for k = 1:(constrained_periods)
                l1 = constraint_index{k};
                l1 = find(constrained_perfect_foresight(l1) | (k == 1));
                if constraint_index{k}( j1)
                    J(cum_index_J,count_col) = d_y_x(cum_index_d_y_x(indx_x),indx_x(count_col));
                    count_col = count_col + 1;
                end
                cum_l1 = cum_l1 + length(l1);
            end
            cum_l1 = cum_l1 + length(constrained_vars(j1));
        end;
        
        
%         col_count = 1;
%         for j = controlled_varexo'
%             for time = time_index_constraint
%                 saved = oo_.exo_simul(time,j);
%                 oo_.exo_simul(time,j) = oo_.exo_simul(time,j) + eps1;
%                 simul();
%                 J1(:,col_count) = (oo_.endo_simul(indx_endo) - ys) / eps1;
%                 oo_.exo_simul(time,j) = saved;
%                 col_count = col_count + 1;
%             end;
%         end;
%         J1
%         sdfmlksdf;
        
        disp(['iteration ' int2str(it) ' error = ' num2str(normr)]);
        
        if normr <= eps
            convg = 1;
            disp('convergence achieved');
        else
            % Newton update on exogenous shocks
            old_exo = oo_.exo_simul(time_index_constraint,:);
            D_exo = - J \ r;
            col_count = 1;
            %constrained_periods
            for j = controlled_varexo'
                oo_.exo_simul(time_index_constraint,j) = oo_.exo_simul(time_index_constraint,j) + D_exo(col_count: (col_count + constrained_periods - 1));
                col_count = col_count + constrained_periods - 1;
            end;
        end;
        it = it + 1;
        normra = normr;
    end;
    endo = oo_.endo_simul';
    exo = oo_.exo_simul;
else
    for t = 1:constrained_periods
        
        if direct_mode && ~isempty(is_constraint) 
            [pos_constrained_pf, junk] = find(constrained_perfect_foresight .* is_constraint(t, :)');
            indx_endo_solve_pf = constrained_vars(pos_constrained_pf);
            if isempty(indx_endo_solve_pf)
                pf = 0;
            else
                pf = length(indx_endo_solve_pf);
            end;
        
            [pos_constrained_surprise, junk] = find((1-constrained_perfect_foresight) .* is_constraint(t, :)');
            indx_endo_solve_surprise = constrained_vars(pos_constrained_surprise);

            if isempty(indx_endo_solve_surprise)
                surprise = 0;
            else
                surprise = length(indx_endo_solve_surprise);
            end;
        end;
        
        if direct_mode && ~isempty(is_shock) 
            [pos_shock_pf, junk] = find(shock_perfect_foresight .* is_shock(t, :)');
            indx_endo_solve_pf = shock_vars(pos_shock_pf);
            if isempty(indx_endo_solve_pf)
                b_pf = 0;
            else
                b_pf = length(indx_endo_solve_pf);
            end;
        
            [pos_shock_surprise, junk] = find((1-shock_perfect_foresight) .* is_shock(t, :)');
            indx_endo_solve_surprise = shock_vars(pos_shock_surprise);

            if isempty(indx_endo_solve_surprise)
                b_surprise = 0;
            else
                b_surprise = length(indx_endo_solve_surprise);
            end;
        end;
        
        disp('===============================================================================================');
        disp(['t=' int2str(t) ' conditional (surprise=' int2str(surprise) ' perfect foresight=' int2str(pf) ') unconditional (surprise=' int2str(b_surprise) ' perfect foresight=' int2str(b_pf) ')']);
        disp('===============================================================================================');
        if t == 1
            oo_=make_ex_(M_,options_,oo_);
            if maximum_lag > 0
                exo_init = oo_.exo_simul;
            else
                exo_init = zeros(size(oo_.exo_simul));
            end
            oo_=make_y_(M_,options_,oo_);
        end;
        %exo_init
        oo_.exo_simul = exo_init;
        oo_.endo_simul(:,1) = initial_conditions;
        
        time_index_constraint = maximum_lag + 1:maximum_lag + constrained_periods - t + 1;
        
        if direct_mode
            nb_shocks = length(plan.shock_vars_);
            if nb_shocks > 0
                shock_index_t = shock_index{t};
                shock_vars_t = shock_vars(shock_index_t);
                for shock_indx = shock_index_t
                    if shock_perfect_foresight(shock_indx) 
                        oo_.exo_simul(time_index_constraint,shock_vars_t(shock_indx)) = shock_paths(shock_indx,t:constrained_periods);
                    else
                        oo_.exo_simul(maximum_lag + 1,shock_vars_t(shock_indx)) = shock_paths(shock_indx,t);
                    end
                end
            end
        end
        %Compute the initial path using the first order solution around the
        % steady-state
        oo_.endo_simul(:, 1) = oo_.endo_simul(:, 1) - oo_.steady_state;
        for jj = 2 : (options_.periods + 2)
            oo_.endo_simul(:,jj) = oo_.dr.ghx(oo_.dr.inv_order_var,:) * oo_.endo_simul(oo_.dr.state_var, jj-1) + oo_.dr.ghu * oo_.exo_simul(jj,:)';
        end
        for jj = 1 : (options_.periods + 2)
            oo_.endo_simul(:,jj) = oo_.steady_state + oo_.endo_simul(:,jj);
        end
        
        constraint_index_t = constraint_index{t};
        controlled_varexo_t = controlled_varexo(constraint_index_t);
        constrained_vars_t = constrained_vars(constraint_index_t);
        
        second_system_size = surprise + pf * (constrained_periods - t + 1);
        indx_endo = zeros(second_system_size,1);
        col_count = 1;
        for j = 1:length(constrained_vars_t)
            if constrained_perfect_foresight(j)
                indx_endo(col_count : col_count + constrained_periods - t) = constrained_vars(j) + (time_index_constraint - 1) * ny;
                col_count = col_count + constrained_periods - t + 1;
            else
                indx_endo(col_count) = constrained_vars(j) + maximum_lag * ny;
                col_count = col_count + 1;
            end;
        end;
        
        r = zeros(second_system_size,1);
        
        convg = 0;
        it = 1;
        while ~convg && it <= maxit
            disp('-----------------------------------------------------------------------------------------------');
            disp(['iteration ' int2str(it) ' time ' int2str(t)]);
            not_achieved = 1;
            alpha = 1;
            while not_achieved
                perfect_foresight_setup;
                perfect_foresight_solver;
                result = sum(sum(isfinite(oo_.endo_simul(:,time_index_constraint)))) == ny * length(time_index_constraint);
                if (~oo_.deterministic_simulation.status || ~result) && it > 1
                    not_achieved = 1;
                    alpha = alpha / 2;
                    col_count = 1;
                    for j1 = constraint_index_t
                        j = controlled_varexo(j1);
                        if constrained_perfect_foresight(j1)
                            oo_.exo_simul(time_index_constraint,j) = (old_exo(time_index_constraint,j) + alpha * D_exo(col_count: col_count + constrained_periods - t));
                            col_count = col_count + constrained_periods - t + 1;
                        else
                            oo_.exo_simul(maximum_lag + 1,j) = old_exo(maximum_lag + 1,j) + alpha * D_exo(col_count);
                            col_count = col_count + 1;
                        end;
                    end;
                    disp(['Divergence in  Newton: reducing the path length alpha=' num2str(alpha) ' result=' num2str(result) ' sum(sum)=' num2str(sum(sum(isfinite(oo_.endo_simul(:,time_index_constraint))))) ' ny * length(time_index_constraint)=' num2str(ny * length(time_index_constraint)) ' oo_.deterministic_simulation.status=' num2str(oo_.deterministic_simulation.status)]);
                    oo_.endo_simul = [initial_conditions repmat(oo_.steady_state, 1, options_cond_fcst.periods + 1)];
                else
                    not_achieved = 0;
                end;
            end;
            if t==constrained_periods
                ycc = oo_.endo_simul;
            end;
            yc = oo_.endo_simul(:,maximum_lag + 1);
            ys = oo_.endo_simul(indx_endo);
            
            col_count = 1;
            for j = constraint_index_t
                if constrained_perfect_foresight(j)
                    y = oo_.endo_simul(constrained_vars(j), time_index_constraint);
                    r(col_count:col_count+constrained_periods - t) = (y - constrained_paths(j,t:constrained_periods))';
                    col_count = col_count + constrained_periods - t + 1;
                else
                    y = yc(constrained_vars(j));
                    r(col_count) = y - constrained_paths(j,t);
                    col_count = col_count + 1;
                end;
            end
            
            disp('computation of derivatives w.r. to exogenous shocks');

            per = 30;
            z = oo_.endo_simul(:, 1 : per + 2 );
            zx = oo_.exo_simul(1: per + 2,:);
            g1 = spalloc(M_.endo_nbr * (per ), M_.endo_nbr * (per ), 3* M_.endo_nbr * per );
            g1_x = spalloc(M_.endo_nbr * (per ), M_.exo_nbr, M_.endo_nbr * (per )* M_.exo_nbr );
            lag_indx = find(M_.lead_lag_incidence(1,:));
            cur_indx = M_.endo_nbr + find(M_.lead_lag_incidence(2,:));
            lead_indx = 2 * M_.endo_nbr + find(M_.lead_lag_incidence(3,:));
            cum_l1 = 0;
            %indx_x = zeros(length(constraint_index_t)* constrained_periods, 1);
            cum_index_d_y_x = [];
            indx_x = [];
            for k = 1 : per
                if k == 1
                    if (isfield(M_,'block_structure'))
                        data1 = M_.block_structure.block;
                        Size = length(M_.block_structure.block);
                    else
                        data1 = M_;
                        Size = 1;
                    end;
                    data1 = M_;
                    if (options_.bytecode)
                        [chck, zz, data1]= bytecode('dynamic','evaluate', z, zx, M_.params, oo_.steady_state, k, data1);
                    else
                        [zz, g1b] = feval([M_.fname '_dynamic'], z', zx, M_.params, oo_.steady_state, k);
                        data1.g1_x = g1b(:,end - M_.exo_nbr + 1:end);
                        data1.g1 = g1b(:,1 : end - M_.exo_nbr);
                        chck = 0;
                    end;
                    mexErrCheck('bytecode', chck);
                end;
                if k == 1 
                    g1(1:M_.endo_nbr,-M_.endo_nbr + [cur_indx lead_indx]) = data1.g1(:,M_.nspred + 1:end);
                elseif k == per
                    g1(M_.endo_nbr * (k - 1) + 1 :M_.endo_nbr * k,M_.endo_nbr * (k -2) + [lag_indx cur_indx]) = data1.g1(:,1:M_.nspred + M_.endo_nbr);
                else
                    g1(M_.endo_nbr * (k - 1) + 1 :M_.endo_nbr * k, M_.endo_nbr * (k -2) + [lag_indx cur_indx lead_indx]) = data1.g1;
                end;
                
                l2 = 1;
                pf_c = 1;
                if t + k - 1 <= constrained_periods
                    for l = constraint_index{t + k - 1}
                        l1 = controlled_varexo(l);
                        if (k == 1) || ((k > 1) && constrained_perfect_foresight(l))
                            g1_x(M_.endo_nbr * (k - 1) + 1:M_.endo_nbr * k,1 + cum_l1) = data1.g1_x(:,l1);
                            if k == 1
                                if constrained_perfect_foresight(l)
                                    indx_x(l2) = l ;
                                    l2 = l2 + 1;
                                    for ii = 2:constrained_periods - t + 1
                                        indx_x(l2) = length(controlled_varexo) + pf * (ii - 2) + constraint_index{k + ii - 1}(pf_c);
                                        l2 = l2 + 1;
                                    end;
                                    pf_c = pf_c + 1;
                                else
                                    indx_x(l2) = l;
                                    l2 = l2 + 1;
                                end;
                                cum_index_d_y_x = [cum_index_d_y_x; constrained_vars_t(l)];
                            else
                                cum_index_d_y_x = [cum_index_d_y_x; constrained_vars_t(l) + (k - 1) * M_.endo_nbr];
                            end
                            cum_l1 = cum_l1 + length(l1);
                        end;
                    end;
                end;
            end;
            
            d_y_x = - g1 \ g1_x;

            
            cum_l1 = 0;
            count_col = 1;
            cum_index_J  = 1:length(cum_index_d_y_x(indx_x));
            J= zeros(length(cum_index_J));
            for j1 = constraint_index_t
                if constrained_perfect_foresight(j1)
                    cum_l1 = 0;
                    for k = 1:(constrained_periods - t + 1)
                        l1 = constraint_index{k};
                        l1 = find(constrained_perfect_foresight(l1) | (k == 1));
                        if constraint_index{k}( j1)
                            J(cum_index_J,count_col) = d_y_x(cum_index_d_y_x(indx_x),indx_x(count_col));
                            count_col = count_col + 1;
                        end
                        cum_l1 = cum_l1 + length(l1);
                    end
                else
                    J(cum_index_J,count_col) = d_y_x(cum_index_d_y_x(indx_x),indx_x(count_col));
                    count_col = count_col + 1;
                end
                cum_l1 = cum_l1 + length(constrained_vars_t(j1));
            end;

            
%             % Numerical computation of the derivatives in the second systme        
%             J1 = [];
%             col_count = 1;
%             for j = constraint_index_t
%                 j_pos = controlled_varexo(j);
%                 if constrained_perfect_foresight(j)
%                     for time = time_index_constraint
%                         saved = oo_.exo_simul(time,j_pos);
%                         oo_.exo_simul(time,j_pos) = oo_.exo_simul(time,j_pos) + eps1;
%                         simul();
%                         J1(:,col_count) = (oo_.endo_simul(indx_endo) - ys) / eps1;
%                         oo_.exo_simul(time,j_pos) = saved;
%                         col_count = col_count + 1;
%                     end;
%                 else
%                     saved = oo_.exo_simul(maximum_lag+1,j_pos);
%                     oo_.exo_simul(maximum_lag+1,j_pos) = oo_.exo_simul(maximum_lag+1,j_pos) + eps1;
%                     simul();
% %                    indx_endo
%                     J1(:,col_count) = (oo_.endo_simul(indx_endo) - ys) / eps1;
% %                    J(:,col_count) = (oo_.endo_simul((pp - 1) * M_.endo_nbr + 1: pp * M_.endo_nbr) - ys) / eps1;
%                     oo_.exo_simul(maximum_lag+1,j_pos) = saved;
%                     col_count = col_count + 1;
%                 end;
%             end;
%             disp('J1');
%             disp(full(J1));
%             sdfmlk;
            

            normr = norm(r, 1);
            
            disp(['iteration ' int2str(it) ' error = ' num2str(normr) ' at time ' int2str(t)]);

            if normr <= eps
                convg = 1;
                disp('convergence achieved');
            else
                % Newton update on exogenous shocks
                try
                   D_exo = - J \ r;
                catch
                    [V, D] = eig(full(J));
                    ev = diag(D);
                    [ev abs(ev)]
                    z_root = find(abs(ev) < 1e-4);
                    z_root
                    disp(V(:,z_root));
                end;
                old_exo = oo_.exo_simul;
                col_count = 1;
                for j = constraint_index_t
                    j_pos=controlled_varexo(j);
                    if constrained_perfect_foresight(j)
                        oo_.exo_simul(time_index_constraint,j_pos) = (oo_.exo_simul(time_index_constraint,j_pos) + D_exo(col_count:(col_count + constrained_periods - t) ));
                        col_count = col_count + constrained_periods - t + 1;
                    else
                        oo_.exo_simul(maximum_lag + 1,j_pos) = oo_.exo_simul(maximum_lag + 1,j_pos) + D_exo(col_count);
                        col_count = col_count + 1;
                    end;
                end;
            end;
            it = it + 1;
        end;
        if ~convg
            error(['convergence not achived at time ' int2str(t) ' after ' int2str(it) ' iterations']);
        end;
        for j = constraint_index_t
            j_pos=controlled_varexo(j);
            if constrained_perfect_foresight(j)
                % in case of mixed surprise and perfect foresight on the
                % endogenous path, at each date all the exogenous paths have to be
                % stored. The paths are stacked in exo.
                for time = time_index_constraint;
                    exo(past_val + time,j_pos) = oo_.exo_simul(time,j_pos);
                end
            else
                exo(maximum_lag + t,j_pos) = oo_.exo_simul(maximum_lag + 1,j_pos);
            end;
        end;
        past_val = past_val + length(time_index_constraint);
        if t < constrained_periods
            endo(maximum_lag + t,:) = yc;
        else
            endo(maximum_lag + t :maximum_lag + options_cond_fcst.periods ,:) = ycc(:,maximum_lag + 1:maximum_lag + options_cond_fcst.periods - constrained_periods + 1)';
        end;
        initial_conditions = yc;
        if maximum_lag > 0
            exo_init(1,:) = exo(maximum_lag + t,:);
        end;
    end;
end;
options_.periods = save_options_periods;
options_.dynatol.f = save_options_dynatol_f;
options_.initval_file = save_options_initval_file;
options_.verbosity = verbosity;
oo_.endo_simul = endo';
oo_.exo_simul = exo;
if direct_mode
    data_set = dseries([endo(2:end,1:M_.orig_endo_nbr) exo(2:end,:)], total_periods(1), {plan.endo_names{:} plan.exo_names{:}}, {plan.endo_names{:} plan.exo_names{:}});
end;
