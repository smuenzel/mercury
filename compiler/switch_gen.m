%-----------------------------------------------------------------------------%
% Copyright (C) 1994-2004 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%---------------------------------------------------------------------------%
%
% File: switch_gen.m
% Authors: conway, fjh, zs
%
% This module handles the generation of code for switches, which are
% disjunctions that do not require backtracking.  Switches are detected
% in switch_detection.m.  This is the module that determines what
% sort of indexing to use for each switch and then actually generates the
% code.
%
% Currently the following forms of indexing are used:
%
%	For switches on atomic data types (int, char, enums),
%	if the cases are not sparse, we use the value of the switch variable
%	to index into a jump table.
%
%	If all the alternative goals for a switch on an atomic data type
%	contain only construction unifications of constants, then we generate
%	a dense lookup table (an array) for each output variable of the switch,
%	rather than a dense jump table, so that executing the switch becomes
%	a matter of doing an array index for each output variable - avoiding
%	the branch overhead of the jump-table.
%
%	For switches on discriminated union types, we generate code that does
%	indexing first on the primary tag, and then on the secondary tag (if
%	the primary tag is shared between several function symbols). The
%	indexing code for switches on both primary and secondary tags can be
%	in the form of a try-me-else chain, a try chain, a dense jump table
%	or a binary search.
%
%	For switches on strings, we lookup the address to jump to in a
%	hash table, using open addressing to resolve hash collisions.
%
%	For all other cases (or if the --smart-indexing option was
%	disabled), we just generate a chain of if-then-elses.
%
%---------------------------------------------------------------------------%

:- module ll_backend__switch_gen.

:- interface.

:- import_module hlds__code_model.
:- import_module hlds__hlds_data.
:- import_module hlds__hlds_goal.
:- import_module ll_backend__code_info.
:- import_module ll_backend__llds.
:- import_module parse_tree__prog_data.

:- import_module list.

:- pred switch_gen__generate_switch(code_model::in, prog_var::in, can_fail::in,
	list(case)::in, hlds_goal_info::in, code_tree::out,
	code_info::in, code_info::out) is det.

%---------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs__switch_util.
:- import_module check_hlds__type_util.
:- import_module hlds__goal_form.
:- import_module hlds__hlds_llds.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module libs__tree.
:- import_module ll_backend__code_aux.
:- import_module ll_backend__code_gen.
:- import_module ll_backend__dense_switch.
:- import_module ll_backend__lookup_switch.
:- import_module ll_backend__string_switch.
:- import_module ll_backend__tag_switch.
:- import_module ll_backend__trace.
:- import_module ll_backend__unify_gen.

:- import_module bool, int, string, map, std_util, require.

%---------------------------------------------------------------------------%

	% Choose which method to use to generate the switch.
	% CanFail says whether the switch covers all cases.

switch_gen__generate_switch(CodeModel, CaseVar, CanFail, Cases, GoalInfo,
		Code, !CI) :-
	goal_info_get_store_map(GoalInfo, StoreMap),
	SwitchCategory = switch_gen__determine_category(!.CI, CaseVar),
	code_info__get_next_label(EndLabel, !CI),
	switch_gen__lookup_tags(!.CI, Cases, CaseVar, TaggedCases0),
	list__sort_and_remove_dups(TaggedCases0, TaggedCases),
	code_info__get_globals(!.CI, Globals),
	globals__lookup_bool_option(Globals, smart_indexing,
		Indexing),
	(
		% Check for a switch on a type whose representation
		% uses reserved addresses
		list__member(Case, TaggedCases),
		Case = case(_Priority, Tag, _ConsId, _Goal),
		(
			Tag = reserved_address(_)
		;
			Tag = shared_with_reserved_addresses(_, _)
		)
	->
		% XXX This may be be inefficient in some cases.
		switch_gen__generate_all_cases(TaggedCases, CaseVar, CodeModel,
			CanFail, GoalInfo, EndLabel, no, MaybeEnd, Code, !CI)
	;
		Indexing = yes,
		SwitchCategory = atomic_switch,
		code_info__get_maybe_trace_info(!.CI, MaybeTraceInfo),
		MaybeTraceInfo = no,
		list__length(TaggedCases, NumCases),
		globals__lookup_int_option(Globals, lookup_switch_size,
			LookupSize),
		NumCases >= LookupSize,
		globals__lookup_int_option(Globals, lookup_switch_req_density,
			ReqDensity),
		lookup_switch__is_lookup_switch(CaseVar, TaggedCases,
			GoalInfo, CanFail, ReqDensity, StoreMap, no,
			MaybeEndPrime, CodeModel, FirstVal, LastVal,
			NeedRangeCheck, NeedBitVecCheck, OutVars, CaseVals,
			MLiveness, !CI)
	->
		MaybeEnd = MaybeEndPrime,
		lookup_switch__generate(CaseVar, OutVars, CaseVals,
			FirstVal, LastVal, NeedRangeCheck, NeedBitVecCheck,
			MLiveness, StoreMap, no, Code, !CI)
	;
		Indexing = yes,
		SwitchCategory = atomic_switch,
		list__length(TaggedCases, NumCases),
		globals__lookup_int_option(Globals, dense_switch_size,
			DenseSize),
		NumCases >= DenseSize,
		globals__lookup_int_option(Globals, dense_switch_req_density,
			ReqDensity),
		dense_switch__is_dense_switch(!.CI, CaseVar, TaggedCases,
			CanFail, ReqDensity, FirstVal, LastVal, CanFail1)
	->
		dense_switch__generate(TaggedCases,
			FirstVal, LastVal, CaseVar, CodeModel, CanFail1,
			GoalInfo, EndLabel, no, MaybeEnd, Code, !CI)
	;
		Indexing = yes,
		SwitchCategory = string_switch,
		list__length(TaggedCases, NumCases),
		globals__lookup_int_option(Globals, string_switch_size,
			StringSize),
		NumCases >= StringSize
	->
		string_switch__generate(TaggedCases, CaseVar, CodeModel,
			CanFail, GoalInfo, EndLabel, no, MaybeEnd, Code, !CI)
	;
		Indexing = yes,
		SwitchCategory = tag_switch,
		list__length(TaggedCases, NumCases),
		globals__lookup_int_option(Globals, tag_switch_size,
			TagSize),
		NumCases >= TagSize
	->
		tag_switch__generate(TaggedCases, CaseVar, CodeModel, CanFail,
			GoalInfo, EndLabel, no, MaybeEnd, Code, !CI)
	;
		% To generate a switch, first we flush the
		% variable on whose tag we are going to switch, then we
		% generate the cases for the switch.

		switch_gen__generate_all_cases(TaggedCases, CaseVar,
			CodeModel, CanFail, GoalInfo, EndLabel, no, MaybeEnd,
			Code, !CI)
	),
	code_info__after_all_branches(StoreMap, MaybeEnd, !CI).

%---------------------------------------------------------------------------%

	% We categorize switches according to whether the value
	% being switched on is an atomic type, a string, or
	% something more complicated.

:- func switch_gen__determine_category(code_info, prog_var) = switch_category.

switch_gen__determine_category(CI, CaseVar) = SwitchCategory :-
	Type = code_info__variable_type(CI, CaseVar),
	code_info__get_module_info(CI, ModuleInfo),
	classify_type(ModuleInfo, Type) = TypeCategory,
	SwitchCategory = switch_util__type_cat_to_switch_cat(TypeCategory).

%---------------------------------------------------------------------------%

:- pred switch_gen__lookup_tags(code_info::in, list(case)::in, prog_var::in,
	cases_list::out) is det.

switch_gen__lookup_tags(_, [], _, []).
switch_gen__lookup_tags(CI, [Case | Cases], Var, [TaggedCase | TaggedCases]) :-
	Case = case(ConsId, Goal),
	Tag = code_info__cons_id_to_tag(CI, Var, ConsId),
	Priority = switch_util__switch_priority(Tag),
	TaggedCase = case(Priority, Tag, ConsId, Goal),
	switch_gen__lookup_tags(CI, Cases, Var, TaggedCases).

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

	% Generate a switch as a chain of if-then-elses.
	%
	% To generate a case for a switch we generate
	% code to do a tag-test and fall through to the next case in
	% the event of failure.
	%
	% Each case except the last consists of
	%
	%	a tag test, jumping to the next case if it fails
	%	the goal for that case
	%	code to move variables to where the store map says they
	%		ought to be
	%	a branch to the end of the switch.
	%
	% For the last case, if the switch covers all cases that can occur,
	% we don't need to generate the tag test, and we never need to
	% generate the branch to the end of the switch.
	%
	% After the last case, we put the end-of-switch label which other
	% cases branch to after their case goals.
	%
	% In the important special case of a det switch with two cases,
	% we try to find out which case will be executed more frequently,
	% and put that one first. This minimizes the number of pipeline
	% breaks caused by taken branches.

:- pred switch_gen__generate_all_cases(list(extended_case)::in, prog_var::in,
	code_model::in, can_fail::in, hlds_goal_info::in, label::in,
	branch_end::in, branch_end::out, code_tree::out,
	code_info::in, code_info::out) is det.

switch_gen__generate_all_cases(Cases0, Var, CodeModel, CanFail, GoalInfo,
		EndLabel, !MaybeEnd, Code, !CI) :-
	code_info__produce_variable(Var, VarCode, _Rval, !CI),
	(
		CodeModel = model_det,
		CanFail = cannot_fail,
		Cases0 = [Case1, Case2],
		Case1 = case(_, _, _, Goal1),
		Case2 = case(_, _, _, Goal2)
	->
		code_info__get_pred_id(!.CI, PredId),
		code_info__get_proc_id(!.CI, ProcId),
		count_recursive_calls(Goal1, PredId, ProcId, Min1, Max1),
		count_recursive_calls(Goal2, PredId, ProcId, Min2, Max2),
		(
			Max1 = 0,	% Goal1 is a base case
			Min2 = 1	% Goal2 is probably singly recursive
		->
			Cases = [Case2, Case1]
		;
			Max2 = 0,	% Goal2 is a base case
			Min1 > 1	% Goal1 is at least doubly recursive
		->
			Cases = [Case2, Case1]
		;
			Cases = Cases0
		)
	;
		Cases = Cases0
	),
	switch_gen__generate_cases(Cases, Var, CodeModel, CanFail,
		GoalInfo, EndLabel, !MaybeEnd, CasesCode, !CI),
	Code = tree(VarCode, CasesCode).

:- pred switch_gen__generate_cases(list(extended_case)::in, prog_var::in,
	code_model::in, can_fail::in, hlds_goal_info::in, label::in,
	branch_end::in, branch_end::out, code_tree::out,
	code_info::in, code_info::out) is det.

	% At the end of a locally semidet switch, we fail because we
	% came across a tag which was not covered by one of the cases.
	% It is followed by the end of switch label to which the cases
	% branch.
switch_gen__generate_cases([], _Var, _CodeModel, CanFail, _GoalInfo,
		EndLabel, !MaybeEnd, Code, !CI) :-
	( CanFail = can_fail ->
		code_info__generate_failure(FailCode, !CI)
	;
		FailCode = empty
	),
	EndCode = node([
		label(EndLabel) -
			"end of switch"
	]),
	Code = tree(FailCode, EndCode).

switch_gen__generate_cases([case(_, _, Cons, Goal) | Cases], Var, CodeModel,
		CanFail, SwitchGoalInfo, EndLabel, !MaybeEnd, CasesCode,
		!CI) :-
	code_info__remember_position(!.CI, BranchStart),
	goal_info_get_store_map(SwitchGoalInfo, StoreMap),
	(
		( Cases = [_|_] ; CanFail = can_fail )
	->
		unify_gen__generate_tag_test(Var, Cons, branch_on_failure,
			NextLabel, TestCode, !CI),
		trace__maybe_generate_internal_event_code(Goal, SwitchGoalInfo,
			TraceCode, !CI),
		code_gen__generate_goal(CodeModel, Goal, GoalCode, !CI),
		code_info__generate_branch_end(StoreMap, !MaybeEnd, SaveCode,
			!CI),
		ElseCode = node([
			goto(label(EndLabel)) -
				"skip to the end of the switch",
			label(NextLabel) -
				"next case"
		]),
		ThisCaseCode =
			tree(TestCode,
			tree(TraceCode,
			tree(GoalCode,
			tree(SaveCode,
			     ElseCode))))
	;
		trace__maybe_generate_internal_event_code(Goal, SwitchGoalInfo,
			TraceCode, !CI),
		code_gen__generate_goal(CodeModel, Goal, GoalCode, !CI),
		code_info__generate_branch_end(StoreMap, !MaybeEnd, SaveCode,
			!CI),
		ThisCaseCode =
			tree(TraceCode,
			tree(GoalCode,
			     SaveCode))
	),
	code_info__reset_to_position(BranchStart, !CI),
		% generate the rest of the cases.
	switch_gen__generate_cases(Cases, Var, CodeModel, CanFail,
		SwitchGoalInfo, EndLabel, !MaybeEnd, OtherCasesCode, !CI),
	CasesCode = tree(ThisCaseCode, OtherCasesCode).

%------------------------------------------------------------------------------%
