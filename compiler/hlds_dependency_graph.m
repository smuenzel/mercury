%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1995-2012 The University of Melbourne.
% Copyright (C) 2017 The Mercury Team.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: hlds_dependency_graph.m.
% Main authors: bromage, conway, stayl.
%
% The HLDS dependency graph is an instance of dependency_graph in which
% the entities are the HLDS procedures in the module being compiled.
% The criterion for inclusion in the dependency graph is "do we have access
% to the body of this procedure?", which means that imported procedures
% are *not* included, but opt_imported procedures *are*.
%
% The reason why we build the dependency graph is because from it,
% dependency_graph.m can compute the list of the SCCs (strongly-connected
% components) of this graph. This is very handy for doing fixpoint iterations.
%
%-----------------------------------------------------------------------------%

:- module hlds.hlds_dependency_graph.
:- interface.

:- import_module hlds.hlds_module.
:- import_module hlds.hlds_pred.
:- import_module libs.
:- import_module libs.dependency_graph.

:- import_module io.
:- import_module list.

%---------------------------------------------------------------------------%

:- type hlds_dependency_info        == dependency_info(pred_proc_id).

:- type hlds_dependency_graph       == dependency_graph(pred_proc_id).
:- type hlds_dependency_graph_key   == dependency_graph_key(pred_proc_id).

:- type hlds_dependency_ordering    == dependency_ordering(pred_proc_id).

%-----------------------------------------------------------------------------%

    % Ensure that the module_info contains a version of the dependency_info
    % which only contains arcs between procedures for which there are clauses
    % defined (everything that is not imported, plus opt_imported). There is
    % no guarantee that the dependency_info is current.
    %
:- pred module_info_ensure_dependency_info(module_info::in, module_info::out)
    is det.

    % Ensure that the module_info contains a version of the dependency_info
    % which only contains arcs between procedures for which there are clauses
    % defined (everything that is not imported, plus opt_imported). The
    % dependency_info will be up-to-date.
    %
:- pred module_info_rebuild_dependency_info(module_info::in, module_info::out,
    hlds_dependency_info::out) is det.

:- type include_imported
    --->    include_imported
    ;       do_not_include_imported.

    % Build the dependency graph of predicates.
    %
:- func build_pred_dependency_graph(module_info, list(pred_id),
    include_imported) = dependency_info(pred_id).

    % Build the dependency graph of procedures.
    %
:- func build_proc_dependency_graph(module_info, list(pred_id),
    include_imported) = dependency_info(pred_proc_id).

    % Output a form of the static call graph to a file, in a format suitable
    % for use in .dependency_info files. After the heading, the format of
    % each line is
    %
    %   CallerModeDecl \t CalleeModeDecl
    %
:- pred write_dependency_graph(module_info::in, module_info::out,
    io::di, io::uo) is det.

    % Output a form of the static call graph to a file for use by the profiler.
    % There is no heading, and the format of each line is
    %
    %   CallerLabel \t CalleeLabel
    %
:- pred write_prof_dependency_graph(module_info::in, module_info::out,
    io::di, io::uo) is det.

    % Given the list of predicates in a strongly connected component
    % of the dependency graph, a list of the higher SCCs in the module
    % and a module_info, find out which members of the SCC can be
    % called from outside the SCC.
    %
:- pred get_scc_entry_points(list(pred_proc_id)::in,
    hlds_dependency_ordering::in, module_info::in,
    list(pred_proc_id)::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs.
:- import_module backend_libs.name_mangle.
:- import_module backend_libs.proc_label.
:- import_module hlds.hlds_clauses.
:- import_module hlds.hlds_goal.
:- import_module hlds.status.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.
:- import_module parse_tree.parse_tree_out_info.
:- import_module parse_tree.parse_tree_out_pred_decl.
:- import_module parse_tree.prog_data.

:- import_module bool.
:- import_module digraph.
:- import_module int.
:- import_module map.
:- import_module maybe.
:- import_module multi_map.
:- import_module set.
:- import_module std_util.
:- import_module term.
:- import_module varset.

%-----------------------------------------------------------------------------%

module_info_ensure_dependency_info(!ModuleInfo) :-
    module_info_get_maybe_dependency_info(!.ModuleInfo, MaybeDepInfo),
    (
        MaybeDepInfo = yes(_)
    ;
        MaybeDepInfo = no,
        module_info_get_valid_pred_ids(!.ModuleInfo, PredIds),
        DepInfo = build_dependency_graph(!.ModuleInfo, PredIds,
            do_not_include_imported),
        module_info_set_dependency_info(DepInfo, !ModuleInfo)
    ).

module_info_rebuild_dependency_info(!ModuleInfo, DepInfo) :-
    module_info_get_valid_pred_ids(!.ModuleInfo, PredIds),
    DepInfo = build_dependency_graph(!.ModuleInfo, PredIds,
        do_not_include_imported),
    module_info_set_dependency_info(DepInfo, !ModuleInfo).

build_proc_dependency_graph(ModuleInfo, PredIds, Imported) =
    build_dependency_graph(ModuleInfo, PredIds, Imported).

build_pred_dependency_graph(ModuleInfo, PredIds, Imported) =
    build_dependency_graph(ModuleInfo, PredIds, Imported).

    % Traverse the module structure, calling `add_dependency_arcs'
    % for each procedure body.
    %
:- func build_dependency_graph(module_info, list(pred_id),
    include_imported) = dependency_info(T) <= dependency_node(T).

build_dependency_graph(ModuleInfo, PredIds, Imported) = DepInfo :-
    digraph.init(DepGraph0),
    add_dependency_nodes(PredIds, ModuleInfo, Imported, DepGraph0, DepGraph1),
    add_dependency_arcs(PredIds, ModuleInfo, Imported, DepGraph1, DepGraph),
    DepInfo = make_dependency_info(DepGraph).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- typeclass dependency_node(T) where [
    pred add_dependency_nodes(list(pred_id)::in, module_info::in,
        include_imported::in,
        dependency_graph(T)::in, dependency_graph(T)::out) is det,

    pred add_dependency_arcs(list(pred_id)::in, module_info::in,
        include_imported::in,
        dependency_graph(T)::in, dependency_graph(T)::out) is det,

    func dependency_node(pred_proc_id) = T
].

:- instance dependency_node(pred_proc_id) where [
    pred(add_dependency_nodes/5) is add_pred_proc_nodes,
    pred(add_dependency_arcs/5) is add_pred_proc_arcs,
    func(dependency_node/1) is id
].

:- instance dependency_node(pred_id) where [
    pred(add_dependency_nodes/5) is add_pred_nodes,
    pred(add_dependency_arcs/5) is add_pred_arcs,
    func(dependency_node/1) is pred_proc_id_get_pred_id
].

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred add_pred_proc_nodes(list(pred_id)::in, module_info::in,
    include_imported::in,
    dependency_graph(pred_proc_id)::in, dependency_graph(pred_proc_id)::out)
    is det.

add_pred_proc_nodes([], _ModuleInfo, _, !DepGraph).
add_pred_proc_nodes([PredId | PredIds], ModuleInfo, Imported, !DepGraph) :-
    module_info_get_preds(ModuleInfo, PredTable),
    map.lookup(PredTable, PredId, PredInfo),
    (
        % Don't bother adding nodes (or arcs) for procedures which are imported
        % (i.e. which we don't have any `clauses' for).
        Imported = do_not_include_imported,
        ProcIds = pred_info_non_imported_procids(PredInfo)
    ;
        Imported = include_imported,
        ProcIds = pred_info_procids(PredInfo)
    ),
    add_proc_nodes(ProcIds, PredId, ModuleInfo, !DepGraph),
    add_pred_proc_nodes(PredIds, ModuleInfo, Imported, !DepGraph).

:- pred add_proc_nodes(list(proc_id)::in, pred_id::in, module_info::in,
    dependency_graph(pred_proc_id)::in, dependency_graph(pred_proc_id)::out)
    is det.

add_proc_nodes([], _PredId, _ModuleInfo, !DepGraph).
add_proc_nodes([ProcId | ProcIds], PredId, ModuleInfo, !DepGraph) :-
    digraph.add_vertex(proc(PredId, ProcId), _, !DepGraph),
    add_proc_nodes(ProcIds, PredId, ModuleInfo, !DepGraph).

%-----------------------------------------------------------------------------%

:- pred add_pred_nodes(list(pred_id)::in, module_info::in,
    include_imported::in,
    dependency_graph(pred_id)::in, dependency_graph(pred_id)::out) is det.

add_pred_nodes([], _ModuleInfo, _, DepGraph, DepGraph).
add_pred_nodes([PredId | PredIds], ModuleInfo, IncludeImported, !DepGraph) :-
    module_info_get_preds(ModuleInfo, PredTable),
    map.lookup(PredTable, PredId, PredInfo),
    % Don't bother adding nodes (or arcs) for predicates
    % which are imported (i.e. which we don't have any `clauses' for).
    ( if
        IncludeImported = do_not_include_imported,
        pred_info_is_imported(PredInfo)
    then
        true
    else
        digraph.add_vertex(PredId, _, !DepGraph)
    ),
    add_pred_nodes(PredIds, ModuleInfo, IncludeImported, !DepGraph).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred add_pred_proc_arcs(list(pred_id)::in, module_info::in,
    include_imported::in,
    dependency_graph(pred_proc_id)::in, dependency_graph(pred_proc_id)::out)
    is det.

add_pred_proc_arcs([], _ModuleInfo, _, !DepGraph).
add_pred_proc_arcs([PredId | PredIds], ModuleInfo, Imported, !DepGraph) :-
    module_info_get_preds(ModuleInfo, PredTable),
    map.lookup(PredTable, PredId, PredInfo),
    (
        % Don't bother adding nodes (or arcs) for procedures which are imported
        % (i.e. which we don't have any `clauses' for).
        Imported = do_not_include_imported,
        ProcIds = pred_info_non_imported_procids(PredInfo)
    ;
        Imported = include_imported,
        ProcIds = pred_info_procids(PredInfo)
    ),
    add_proc_arcs(ProcIds, PredId, ModuleInfo, Imported, !DepGraph),
    add_pred_proc_arcs(PredIds, ModuleInfo, Imported, !DepGraph).

:- pred add_proc_arcs(list(proc_id)::in, pred_id::in, module_info::in,
    include_imported::in,
    dependency_graph(pred_proc_id)::in, dependency_graph(pred_proc_id)::out)
    is det.

add_proc_arcs([], _PredId, _ModuleInfo, _, !DepGraph).
add_proc_arcs([ProcId | ProcIds], PredId, ModuleInfo, IncludeImported,
        !DepGraph) :-
    module_info_get_preds(ModuleInfo, PredTable0),
    map.lookup(PredTable0, PredId, PredInfo0),
    pred_info_get_proc_table(PredInfo0, ProcTable0),
    map.lookup(ProcTable0, ProcId, ProcInfo0),
    (
        IncludeImported = do_not_include_imported,
        proc_info_get_goal(ProcInfo0, Goal),

        digraph.lookup_key(!.DepGraph, proc(PredId, ProcId), Caller),
        add_dependency_arcs_in_goal(Caller, Goal, !DepGraph)
    ;
        IncludeImported = include_imported,
        pred_info_get_status(PredInfo0, PredStatus),
        Imported = pred_status_is_imported(PredStatus),
        (
            Imported = yes
        ;
            Imported = no,
            proc_info_get_goal(ProcInfo0, Goal),
            digraph.lookup_key(!.DepGraph, proc(PredId, ProcId), Caller),
            add_dependency_arcs_in_goal(Caller, Goal, !DepGraph)
        )
    ),
    add_proc_arcs(ProcIds, PredId, ModuleInfo, IncludeImported, !DepGraph).

%-----------------------------------------------------------------------------%

:- pred add_pred_arcs(list(pred_id)::in, module_info::in, include_imported::in,
    dependency_graph(pred_id)::in, dependency_graph(pred_id)::out) is det.

add_pred_arcs([], _ModuleInfo, _, !DepGraph).
add_pred_arcs([PredId | PredIds], ModuleInfo, IncludeImported, !DepGraph) :-
    module_info_get_preds(ModuleInfo, PredTable),
    map.lookup(PredTable, PredId, PredInfo),
    ( if
        IncludeImported = do_not_include_imported,
        pred_info_is_imported(PredInfo)
    then
        true
    else
        pred_info_get_clauses_info(PredInfo, ClausesInfo),
        clauses_info_get_clauses_rep(ClausesInfo, ClausesRep, _ItemNumbers),
        get_clause_list_maybe_repeated(ClausesRep, Clauses),
        Goals = list.map(clause_body, Clauses),
        digraph.lookup_key(!.DepGraph, PredId, Caller),
        add_dependency_arcs_in_goals(Caller, Goals, !DepGraph)
    ),
    add_pred_arcs(PredIds, ModuleInfo, IncludeImported, !DepGraph).

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- func pred_proc_id_get_pred_id(pred_proc_id) = pred_id.

pred_proc_id_get_pred_id(proc(PredId, _)) = PredId.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- pred add_dependency_arcs_in_goal(digraph_key(T)::in, hlds_goal::in,
    dependency_graph(T)::in, dependency_graph(T)::out) is det
    <= dependency_node(T).

add_dependency_arcs_in_goal(Caller, Goal, !DepGraph) :-
    Goal = hlds_goal(GoalExpr, _),
    (
        ( GoalExpr = conj(_, Goals)
        ; GoalExpr = disj(Goals)
        ),
        add_dependency_arcs_in_goals(Caller, Goals, !DepGraph)
    ;
        GoalExpr = switch(_Var, _Det, Cases),
        add_dependency_arcs_in_cases(Caller, Cases, !DepGraph)
    ;
        GoalExpr = if_then_else(_Vars, Cond, Then, Else),
        add_dependency_arcs_in_goal(Caller, Cond, !DepGraph),
        add_dependency_arcs_in_goal(Caller, Then, !DepGraph),
        add_dependency_arcs_in_goal(Caller, Else, !DepGraph)
    ;
        GoalExpr = negation(SubGoal),
        add_dependency_arcs_in_goal(Caller, SubGoal, !DepGraph)
    ;
        GoalExpr = scope(Reason, SubGoal),
        ( if
            Reason = from_ground_term(_, FGT),
            ( FGT = from_ground_term_construct
            ; FGT = from_ground_term_deconstruct
            )
        then
            % The scope references no predicates or procedures.
            true
        else
            add_dependency_arcs_in_goal(Caller, SubGoal, !DepGraph)
        )
    ;
        GoalExpr = generic_call(_, _, _, _, _)
    ;
        GoalExpr = plain_call(PredId, ProcId, _, Builtin, _, _),
        (
            Builtin = inline_builtin
        ;
            ( Builtin = out_of_line_builtin
            ; Builtin = not_builtin
            ),
            ( if
                % If the node isn't in the graph, then we didn't insert it
                % because is was imported, and we don't consider it.
                digraph.search_key(!.DepGraph,
                    dependency_node(proc(PredId, ProcId)), Callee)
            then
                digraph.add_edge(Caller, Callee, !DepGraph)
            else
                true
            )
        )
    ;
        GoalExpr = unify(_,_,_,Unify,_),
        (
            Unify = assign(_, _)
        ;
            Unify = simple_test(_, _)
        ;
            Unify = construct(_, ConsId, _, _, _, _, _),
            add_dependency_arcs_in_cons(Caller, ConsId, !DepGraph)
        ;
            Unify = deconstruct(_, ConsId, _, _, _, _),
            add_dependency_arcs_in_cons(Caller, ConsId, !DepGraph)
        ;
            Unify = complicated_unify(_, _, _)
        )
    ;
        GoalExpr = call_foreign_proc(_, _, _, _, _, _, _)
    ;
        GoalExpr = shorthand(ShortHand),
        (
            ShortHand = atomic_goal(_GoalType, _Outer, _Inner, _Vars,
                MainGoal, OrElseGoals, _OrElseInners),
            add_dependency_arcs_in_goal(Caller, MainGoal, !DepGraph),
            add_dependency_arcs_in_goals(Caller, OrElseGoals, !DepGraph)
        ;
            ShortHand = try_goal(_, _, SubGoal),
            add_dependency_arcs_in_goal(Caller, SubGoal, !DepGraph)
        ;
            ShortHand = bi_implication(LHS, RHS),
            add_dependency_arcs_in_goal(Caller, LHS, !DepGraph),
            add_dependency_arcs_in_goal(Caller, RHS, !DepGraph)
        )
    ).

%-----------------------------------------------------------------------------%

:- pred add_dependency_arcs_in_goals(digraph_key(T)::in, list(hlds_goal)::in,
    dependency_graph(T)::in, dependency_graph(T)::out) is det
    <= dependency_node(T).

add_dependency_arcs_in_goals(_Caller, [], !DepGraph).
add_dependency_arcs_in_goals(Caller, [Goal | Goals], !DepGraph) :-
    add_dependency_arcs_in_goal(Caller, Goal, !DepGraph),
    add_dependency_arcs_in_goals(Caller, Goals, !DepGraph).

%-----------------------------------------------------------------------------%

:- pred add_dependency_arcs_in_cases(digraph_key(T)::in, list(case)::in,
    dependency_graph(T)::in, dependency_graph(T)::out) is det
    <= dependency_node(T).

add_dependency_arcs_in_cases(_Caller, [], !DepGraph).
add_dependency_arcs_in_cases(Caller, [Case | Cases], !DepGraph) :-
    Case = case(MainConsId, OtherConsIds, Goal),
    add_dependency_arcs_in_cons(Caller, MainConsId, !DepGraph),
    list.foldl(add_dependency_arcs_in_cons(Caller), OtherConsIds, !DepGraph),
    add_dependency_arcs_in_goal(Caller, Goal, !DepGraph),
    add_dependency_arcs_in_cases(Caller, Cases, !DepGraph).

%-----------------------------------------------------------------------------%

:- pred add_dependency_arcs_in_cons(digraph_key(T)::in, cons_id::in,
    dependency_graph(T)::in, dependency_graph(T)::out) is det
    <= dependency_node(T).

add_dependency_arcs_in_cons(Caller, ConsId, !DepGraph) :-
    (
        ConsId = closure_cons(ShroudedPredProcId, _),
        PredProcId = unshroud_pred_proc_id(ShroudedPredProcId),
        ( if
            % If the node isn't in the graph, then we didn't insert it
            % because it was imported, and we don't consider it.
            digraph.search_key(!.DepGraph, dependency_node(PredProcId), Callee)
        then
            digraph.add_edge(Caller, Callee, !DepGraph)
        else
            true
        )
    ;
        ( ConsId = cons(_, _, _)
        ; ConsId = tuple_cons(_)
        ; ConsId = int_const(_)
        ; ConsId = uint_const(_)
        ; ConsId = float_const(_)
        ; ConsId = char_const(_)
        ; ConsId = string_const(_)
        ; ConsId = impl_defined_const(_)
        ; ConsId = type_ctor_info_const(_, _, _)
        ; ConsId = base_typeclass_info_const(_, _, _, _)
        ; ConsId = type_info_cell_constructor(_)
        ; ConsId = typeclass_info_cell_constructor
        ; ConsId = type_info_const(_)
        ; ConsId = typeclass_info_const(_)
        ; ConsId = ground_term_const(_, _)
        ; ConsId = tabling_info_const(_)
        ; ConsId = table_io_entry_desc(_)
        ; ConsId = deep_profiling_proc_layout(_)
        )
    ).

%-----------------------------------------------------------------------------%

:- pred write_dependency_ordering(module_info::in, int::in,
    list(list(pred_proc_id))::in, io::di, io::uo) is det.
:- pragma consider_used(write_dependency_ordering/5).

write_dependency_ordering(_ModuleInfo, _CurSCCNum, [], !IO) :-
    io.write_string("\n", !IO).
write_dependency_ordering(ModuleInfo, CurSCCNum, [SCC | SCCs], !IO) :-
    io.write_string("% SCC ", !IO),
    io.write_int(CurSCCNum, !IO),
    io.write_string("\n", !IO),
    write_scc(ModuleInfo, SCC, !IO),
    write_dependency_ordering(ModuleInfo, CurSCCNum + 1, SCCs, !IO).

:- pred write_scc(module_info::in, list(pred_proc_id)::in, io::di, io::uo)
    is det.

write_scc(_ModuleInfo, [], !IO).
write_scc(ModuleInfo, [PredProcId | PredProcIds], !IO) :-
    PredProcId = proc(PredId, ProcId),
    module_info_pred_proc_info(ModuleInfo, PredId, ProcId, PredInfo, ProcInfo),
    Name = pred_info_name(PredInfo),
    proc_info_get_declared_determinism(ProcInfo, Det),
    proc_info_get_argmodes(ProcInfo, Modes),
    varset.init(ModeVarSet),

    io.write_string("% ", !IO),
    mercury_output_pred_mode_subdecl(output_mercury,ModeVarSet,
        unqualified(Name), Modes, Det, !IO),
    io.write_string("\n", !IO),
    write_scc(ModuleInfo, PredProcIds, !IO).

%-----------------------------------------------------------------------------%

write_prof_dependency_graph(!ModuleInfo, !IO) :-
    module_info_ensure_dependency_info(!ModuleInfo),
    module_info_dependency_info(!.ModuleInfo, DepInfo),
    digraph.traverse(dependency_info_get_graph(DepInfo),
        write_empty_node, write_prof_dep_graph_link(!.ModuleInfo), !IO).

write_dependency_graph(!ModuleInfo, !IO) :-
    module_info_ensure_dependency_info(!ModuleInfo),
    module_info_dependency_info(!.ModuleInfo, DepInfo),
    io.write_string("% Dependency graph\n", !IO),
    io.write_string("\n\n% Dependency ordering\n", !IO),
    digraph.traverse(dependency_info_get_graph(DepInfo),
        write_empty_node, write_dep_graph_link(!.ModuleInfo), !IO).

:- pred write_empty_node(pred_proc_id::in, io::di, io::uo) is det.

write_empty_node(_, !IO).

:- pred write_prof_dep_graph_link(module_info::in,
    pred_proc_id::in, pred_proc_id::in, io::di, io::uo) is det.

write_prof_dep_graph_link(ModuleInfo, Parent, Child, !IO) :-
    Parent = proc(PPredId, PProcId),    % Caller
    Child = proc(CPredId, CProcId),     % Callee
    output_label_dependency(ModuleInfo, PPredId, PProcId, !IO),
    io.write_string("\t", !IO),
    output_label_dependency(ModuleInfo, CPredId, CProcId, !IO),
    io.write_string("\n", !IO).

:- pred write_dep_graph_link(module_info::in,
    pred_proc_id::in, pred_proc_id::in, io::di, io::uo) is det.

write_dep_graph_link(ModuleInfo, Parent, Child, !IO) :-
    Parent = proc(PPredId, PProcId),    % Caller
    Child = proc(CPredId, CProcId),     % Callee
    module_info_pred_proc_info(ModuleInfo, PPredId, PProcId,
        PPredInfo, PProcInfo),
    module_info_pred_proc_info(ModuleInfo, CPredId, CProcId,
        CPredInfo, CProcInfo),
    PName = pred_info_name(PPredInfo),
    proc_info_get_declared_determinism(PProcInfo, PDet),
    proc_info_get_argmodes(PProcInfo, PModes),
    CName = pred_info_name(CPredInfo),
    proc_info_get_declared_determinism(CProcInfo, CDet),
    proc_info_get_argmodes(CProcInfo, CModes),
    varset.init(ModeVarSet),
    mercury_output_pred_mode_subdecl(output_mercury, ModeVarSet,
        unqualified(PName), PModes, PDet, !IO),
    io.write_string(" -> ", !IO),
    mercury_output_pred_mode_subdecl(output_mercury, ModeVarSet,
        unqualified(CName), CModes, CDet, !IO),
    io.write_string("\n", !IO).

%-----------------------------------------------------------------------------%

    % Print out the label corresponding to the given pred_id and proc_id.
    %
:- pred output_label_dependency(module_info::in, pred_id::in, proc_id::in,
    io::di, io::uo) is det.

output_label_dependency(ModuleInfo, PredId, ProcId, !IO) :-
    ProcLabel = make_proc_label(ModuleInfo, PredId, ProcId),
    output_proc_label(ProcLabel, !IO).

%-----------------------------------------------------------------------------%

get_scc_entry_points(SCC, HigherSCCs, ModuleInfo, EntryPoints) :-
    list.filter(is_entry_point(HigherSCCs, ModuleInfo), SCC, EntryPoints).

:- pred is_entry_point(list(list(pred_proc_id))::in, module_info::in,
    pred_proc_id::in) is semidet.

is_entry_point(HigherSCCs, ModuleInfo, PredProcId) :-
    (
        % Is the predicate exported?
        PredProcId = proc(PredId, _ProcId),
        module_info_pred_info(ModuleInfo, PredId, PredInfo),
        pred_info_is_exported(PredInfo)
    ;
        % Is the predicate called from a higher SCC?
        module_info_dependency_info(ModuleInfo, DepInfo),
        DepGraph = dependency_info_get_graph(DepInfo),

        digraph.lookup_key(DepGraph, PredProcId, PredProcIdKey),
        digraph.lookup_to(DepGraph, PredProcIdKey, CallingKeys),
        set.member(CallingKey, CallingKeys),
        digraph.lookup_vertex(DepGraph, CallingKey, CallingPred),
        list.member(HigherSCC, HigherSCCs),
        list.member(CallingPred, HigherSCC)
    ).

%-----------------------------------------------------------------------------%

:- type scc_id == int.

    % An SCC cannot be merged into its parents if one of its procedures
    % is called as an aggregate query.
    %
    % XXX This predicate is not called from anywhere. Maybe it should be;
    % maybe not.
    %
:- pred handle_higher_order_args(list(prog_var)::in, bool::in, scc_id::in,
    multi_map(prog_var, pred_proc_id)::in, map(pred_proc_id, scc_id)::in,
    digraph(scc_id)::in, digraph(scc_id)::out,
    set(scc_id)::in, set(scc_id)::out) is det.
:- pragma consider_used(handle_higher_order_args/9).

handle_higher_order_args([], _, _, _, _, !SCCRel, !NoMerge).
handle_higher_order_args([Arg | Args], IsAgg, SCCid, Map, PredSCC,
        !SCCGraph, !NoMerge) :-
    ( if multi_map.search(Map, Arg, PredProcIds) then
        list.foldl2(handle_higher_order_arg(PredSCC, IsAgg, SCCid),
            PredProcIds, !SCCGraph, !NoMerge)
    else
        true
    ),
    handle_higher_order_args(Args, IsAgg, SCCid, Map, PredSCC,
        !SCCGraph, !NoMerge).

:- pred handle_higher_order_arg(map(pred_proc_id, scc_id)::in, bool::in,
    scc_id::in, pred_proc_id::in,
    digraph(scc_id)::in, digraph(scc_id)::out,
    set(scc_id)::in, set(scc_id)::out) is det.

handle_higher_order_arg(PredSCC, IsAgg, SCCid, PredProcId,
        !SCCGraph, !NoMerge) :-
    ( if map.search(PredSCC, PredProcId, CalledSCCid) then
        % Make sure anything called through an aggregate
        % is not merged into the current sub-module.
        (
            IsAgg = yes,
            set.insert(CalledSCCid, !NoMerge)
        ;
            IsAgg = no
        ),
        ( if CalledSCCid = SCCid then
            true
        else
            digraph.add_vertices_and_edge(SCCid, CalledSCCid, !SCCGraph)
        )
    else
        true
    ).

%-----------------------------------------------------------------------------%
:- end_module hlds.hlds_dependency_graph.
%-----------------------------------------------------------------------------%