%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2004 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%

% File: ml_code_util.m
% Main author: fjh

% This module is part of the MLDS code generator.
% It defines the ml_gen_info type and its access routines.

%-----------------------------------------------------------------------------%

:- module ml_backend__ml_code_util.
:- interface.

:- import_module backend_libs__builtin_ops.
:- import_module hlds__code_model.
:- import_module hlds__hlds_module.
:- import_module hlds__hlds_pred.
:- import_module libs__globals.
:- import_module ml_backend__mlds.
:- import_module parse_tree__prog_data.

:- import_module bool, int, list, map, std_util.

%-----------------------------------------------------------------------------%
%
% Various utility routines used for MLDS code generation.
%

	% Generate an MLDS assignment statement.
:- func ml_gen_assign(mlds__lval, mlds__rval, prog_context) = mlds__statement.

	%
	% Append an appropriate `return' statement for the given code_model
	% and returning the given lvals, if needed.
	%
:- pred ml_append_return_statement(ml_gen_info::in, code_model::in,
	list(mlds__lval)::in, prog_context::in, mlds__statements::in,
	mlds__statements::out) is det.

	% Generate a block statement, i.e. `{ <Decls>; <Statements>; }'.
	% But if the block consists only of a single statement with no
	% declarations, then just return that statement.
	%
:- func ml_gen_block(mlds__defns, mlds__statements, prog_context)
	= mlds__statement.

	% ml_join_decls:
	% 	Join two statement lists and their corresponding
	% 	declaration lists in sequence.
	%
	% 	If the statements have no declarations in common,
	% 	then their corresponding declaration lists will be
	% 	concatenated together into a single list of declarations.
	% 	But if they have any declarations in common, then we
	% 	put each statement list and its declarations into
	% 	a block, so that the declarations remain local to
	% 	each statement list.
	%
:- pred ml_join_decls(mlds__defns::in, mlds__statements::in,
	mlds__defns::in, mlds__statements::in, prog_context::in,
	mlds__defns::out, mlds__statements::out) is det.

	% ml_combine_conj:
	%	Given closures to generate code for two conjuncts,
	%	generate code for their conjunction.

:- type gen_pred == pred(mlds__defns, mlds__statements,
		ml_gen_info, ml_gen_info).
:- inst gen_pred = (pred(out, out, in, out) is det).

:- pred ml_combine_conj(code_model::in, prog_context::in,
	gen_pred::in(gen_pred), gen_pred::in(gen_pred),
	mlds__defns::out, mlds__statements::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Given a function label and the statement which will comprise
	% the function body for that function, generate an mlds__defn
	% which defines that function.
	%
:- pred ml_gen_nondet_label_func(ml_gen_info::in, ml_label_func::in,
	prog_context::in, mlds__statement::in, mlds__defn::out) is det.

	% Given a function label, the function parameters, and the statement
	% which will comprise the function body for that function,
	% generate an mlds__defn which defines that function.
	%
:- pred ml_gen_label_func(ml_gen_info::in, ml_label_func::in,
	mlds__func_params::in, prog_context::in, mlds__statement::in,
	mlds__defn::out) is det.

	%
	% Test to see if the procedure is
	% a model_det function whose function result has an output mode
	% (whose type is not a dummy argument type like io__state),
	% and if so, bind RetVar to the procedure's return value.
	% These procedures need to handled specially: for such functions,
	% we map the Mercury function result to an MLDS return value.
	%
:- pred ml_is_output_det_function(module_info::in, pred_id::in, proc_id::in,
	prog_var::out) is semidet.

%-----------------------------------------------------------------------------%
%
% Routines for generating expressions.
%

	% conjunction: ml_gen_and(X,Y) = binop((and), X, Y),
	% except that it does some constant folding on the result.
:- func ml_gen_and(mlds__rval, mlds__rval) = mlds__rval.

	% negation: ml_gen_not(X) = unop(std_unop(not), X),
:- func ml_gen_not(mlds__rval) = mlds__rval.

%-----------------------------------------------------------------------------%
%
% Routines for generating types.
%

	% A convenient abbreviation.
	%
:- type prog_type == prog_data__type.

	% Convert a Mercury type to an MLDS type.
	%
:- pred ml_gen_type(ml_gen_info::in, prog_type::in, mlds__type::out) is det.

	% Convert the element type for an array_index operator
	% to an MLDS type.
	%
:- func ml_gen_array_elem_type(builtin_ops__array_elem_type) = mlds__type.

	% Return the MLDS type corresponding to a Mercury string type.
	%
:- func ml_string_type = mlds__type.

	% Allocate some fresh type variables to use as the Mercury types
	% of boxed objects (e.g. to get the argument types for tuple
	% constructors or closure constructors).  Note that this should
	% only be used in cases where the tvarset doesn't matter.
:- func ml_make_boxed_types(arity) = list(prog_type).

%-----------------------------------------------------------------------------%
%
% Routines for generating function declarations (i.e. mlds__func_params).
%

% Note that when generating function *definitions*,
% the versions that take an ml_gen_info pair should be used,
% since those are the only ones that will generate the
% correct GC tracing code for the parameters.

	% Generate the function prototype for a given procedure.
	%
:- func ml_gen_proc_params(module_info, pred_id, proc_id) = mlds__func_params.

:- pred ml_gen_proc_params(pred_id::in, proc_id::in, mlds__func_params::out,
	ml_gen_info::in, ml_gen_info::out) is det.

:- func ml_gen_proc_params_from_rtti(module_info, rtti_proc_label) =
	mlds__func_params.

	% Generate the function prototype for a procedure with the
	% given argument types, modes, and code model.
	%
:- func ml_gen_params(module_info, list(mlds__var_name), list(prog_type),
	list(mode), pred_or_func, code_model) = mlds__func_params.

:- pred ml_gen_params(list(mlds__var_name)::in, list(prog_type)::in,
	list(mode)::in, pred_or_func::in, code_model::in,
	mlds__func_params::out, ml_gen_info::in, ml_gen_info::out) is det.

	% Given a list of variables and their corresponding modes,
	% return a list containing only those variables which have
	% an output mode.
	%
:- func select_output_vars(module_info, list(Var), list(mode),
	map(Var, prog_type)) = list(Var).

%-----------------------------------------------------------------------------%
%
% Routines for generating labels and entity names.
%

	% Generate the mlds__entity_name and module name for the entry point
	% function corresponding to a given procedure.
	%
:- pred ml_gen_proc_label(module_info::in, pred_id::in, proc_id::in,
	mlds__entity_name::out, mlds_module_name::out) is det.

	% Generate an mlds__entity_name for a continuation function
	% with the given sequence number.  The pred_id and proc_id
	% specify the procedure that this continuation function
	% is part of.
	%
:- func ml_gen_nondet_label(module_info, pred_id, proc_id, ml_label_func)
	= mlds__entity_name.

	% Allocate a new function label and return an rval containing
	% the function's address.  If parameters are not given, we
	% assume it's a continuation function, and give it the
	% appropriate arguments (depending on whether we are doing
	% nested functions or not).
	%
:- pred ml_gen_new_func_label(maybe(mlds__func_params)::in, ml_label_func::out,
	mlds__rval::out, ml_gen_info::in, ml_gen_info::out) is det.

	% Generate the mlds__pred_label and module name
	% for a given procedure.
	%
:- pred ml_gen_pred_label(module_info::in, pred_id::in, proc_id::in,
	mlds__pred_label::out, mlds_module_name::out) is det.

:- pred ml_gen_pred_label_from_rtti(module_info::in, rtti_proc_label::in,
	mlds__pred_label::out, mlds_module_name::out) is det.

	% Allocate a new label name, for use in label statements.
	%
:- pred ml_gen_new_label(mlds__label::out,
	ml_gen_info::in, ml_gen_info::out) is det.

%-----------------------------------------------------------------------------%
%
% Routines for dealing with variables
%

	% Generate a list of the mlds__lvals corresponding to a
	% given list of prog_vars.
	%
:- pred ml_gen_var_list(ml_gen_info::in, list(prog_var)::in,
	list(mlds__lval)::out) is det.

	% Generate the mlds__lval corresponding to a given prog_var.
	%
:- pred ml_gen_var(ml_gen_info::in, prog_var::in, mlds__lval::out) is det.

	% Generate the mlds__lval corresponding to a given prog_var,
	% with a given type.
	%
:- pred ml_gen_var_with_type(ml_gen_info::in, prog_var::in, prog_type::in,
	mlds__lval::out) is det.

	% Lookup the types of a list of variables.
	%
:- pred ml_variable_types(ml_gen_info::in, list(prog_var)::in,
	list(prog_type)::out) is det.

	% Lookup the type of a variable.
	%
:- pred ml_variable_type(ml_gen_info::in, prog_var::in, prog_type::out) is det.

	% Generate the MLDS variable names for a list of variables.
	%
:- func ml_gen_var_names(prog_varset, list(prog_var)) = list(mlds__var_name).

	% Generate the MLDS variable name for a variable.
	%
:- func ml_gen_var_name(prog_varset, prog_var) = mlds__var_name.

	% Generate an lval from the variable name and type. The variable
	% name will be qualified with the current module name.
	%
:- pred ml_gen_var_lval(ml_gen_info::in, mlds__var_name::in, mlds__type::in,
	mlds__lval::out) is det.

	% Generate a declaration for an MLDS variable, given its HLDS type.
	%
:- pred ml_gen_var_decl(var_name::in, prog_type::in, prog_context::in,
	mlds__defn::out, ml_gen_info::in, ml_gen_info::out) is det.

	% Generate a declaration for an MLDS variable, given its MLDS type
	% and the code to trace it for accurate GC (if needed).
	%
:- func ml_gen_mlds_var_decl(mlds__data_name, mlds__type,
	maybe(mlds__statement), mlds__context) = mlds__defn.

	% Generate a declaration for an MLDS variable, given its MLDS type
	% and initializer, and given the code to trace it for accurate GC
	% (if needed).
	%
:- func ml_gen_mlds_var_decl(mlds__data_name, mlds__type, mlds__initializer,
	maybe(mlds__statement), mlds__context) = mlds__defn.

	% Generate declaration flags for a local variable
	%
:- func ml_gen_local_var_decl_flags = mlds__decl_flags.

	% Generate declaration flags for a public field
	% of a class.
	%
:- func ml_gen_public_field_decl_flags = mlds__decl_flags.

	% Apply the usual %s_%d formatting to a MLDS variable name.
:- func ml_var_name_to_string(mlds__var_name) = string.

%-----------------------------------------------------------------------------%
%
% Routines for dealing with static constants
%

	% ml_format_reserved_object_name(CtorName, CtorArity, ReservedObjName):
	% Generate a name for a specially reserved global variable
	% (or static member variable)
	% whose address is used to represent the specified constructor.
:- func ml_format_reserved_object_name(string, arity) = mlds__var_name.

	% Generate a name for a local static constant.
	%
:- pred ml_format_static_const_name(ml_gen_info::in, string::in, const_seq::in,
	mlds__var_name::out) is det.

	% Generate a definition of a static constant,
	% given the constant's name, type, accessibility,
	% and initializer.
	%
:- func ml_gen_static_const_defn(mlds__var_name, mlds__type, mlds__access,
	mlds__initializer, prog_context) = mlds__defn.

	% Return the declaration flags appropriate for an
	% initialized local static constant.
	%
:- func ml_static_const_decl_flags = mlds__decl_flags.

	% Succeed iff the specified mlds__defn defines
	% a local static constant.
	%
:- pred ml_decl_is_static_const(mlds__defn::in) is semidet.

%-----------------------------------------------------------------------------%
%
% Routines for dealing with fields
%

	% Given the user-specified field name, if any,
	% and the argument number (starting from one),
	% generate an MLDS field name.
:- func ml_gen_field_name(maybe(ctor_field_name), int) = mlds__field_name.

	% Succeed iff the specified type must be boxed when used as a field.
	% For the MLDS->C and MLDS->asm back-ends,
	% we need to box types that are not word-sized, because the code
	% for `arg' etc. in std_util.m rely on all arguments being word-sized.
:- pred ml_must_box_field_type(prog_type::in, module_info::in) is semidet.

%-----------------------------------------------------------------------------%
%
% Routines for handling success and failure
%

	% Generate code to succeed in the given code_model.
	%
:- pred ml_gen_success(code_model::in, prog_context::in, mlds__statements::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Generate code to fail in the given code_model.
	%
:- pred ml_gen_failure(code_model::in, prog_context::in, mlds__statements::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Generate the declaration for the built-in `succeeded' flag.
	% (`succeeded' is a boolean variable used to record
	% the success or failure of model_semi procedures.)
	%
:- func ml_gen_succeeded_var_decl(mlds__context) = mlds__defn.

	% Return the lval for the `succeeded' flag.
	% (`succeeded' is a boolean variable used to record
	% the success or failure of model_semi procedures.)
	%
:- pred ml_success_lval(ml_gen_info::in, mlds__lval::out) is det.

	% Return an rval which will test the value of the `succeeded' flag.
	% (`succeeded' is a boolean variable used to record
	% the success or failure of model_semi procedures.)
	%
:- pred ml_gen_test_success(ml_gen_info::in, mlds__rval::out) is det.

	% Generate code to set the `succeeded' flag to the
	% specified truth value.
	%
:- pred ml_gen_set_success(ml_gen_info::in, mlds__rval::in, prog_context::in,
	mlds__statement::out) is det.

	% Generate the declaration for the specified `cond'
	% variable.
	% (`cond' variables are boolean variables used to record
	% the success or failure of model_non conditions of
	% if-then-elses.)
	%
:- func ml_gen_cond_var_decl(cond_seq, mlds__context) = mlds__defn.

	% Return the lval for the specified `cond' flag.
	% (`cond' variables are boolean variables used to record
	% the success or failure of model_non conditions of
	% if-then-elses.)
	%
:- pred ml_cond_var_lval(ml_gen_info::in, cond_seq::in, mlds__lval::out) is det.

	% Return an rval which will test the value of the specified
	% `cond' variable.
	% (`cond' variables are boolean variables used to record
	% the success or failure of model_non conditions of
	% if-then-elses.)
	%
:- pred ml_gen_test_cond_var(ml_gen_info::in, cond_seq::in, mlds__rval::out)
	is det.

	% Generate code to set the specified `cond' variable to the
	% specified truth value.
	%
:- pred ml_gen_set_cond_var(ml_gen_info::in, cond_seq::in, mlds__rval::in,
	prog_context::in, mlds__statement::out) is det.

	% Return the success continuation that was
	% passed as the current function's argument(s).
	% The success continuation consists of two parts, the
	% `cont' argument, and the `cont_env' argument.
	% The `cont' argument is a continuation function that
	% will be called when a model_non goal succeeds.
	% The `cont_env' argument is a pointer to the environment (set
	% of local variables in the containing procedure) for the continuation
	% function.  (If we're using gcc nested function, the `cont_env'
	% is not used.)
	% The output variable lvals and types need to be supplied when
	% generating a continuation using --nondet-copy-out, otherwise
	% they should be empty.
	%
:- pred ml_initial_cont(ml_gen_info::in, list(mlds__lval)::in,
	list(prog_type)::in, success_cont::out) is det.

	% Generate code to call the current success continuation.
	% This is used for generating success when in a model_non context.
	%
:- pred ml_gen_call_current_success_cont(prog_context::in,
	mlds__statement::out, ml_gen_info::in, ml_gen_info::out) is det.

	% Generate code to call the current success continuation, using
	% a local function as a proxy.
	% This is used for generating success when in a model_non context
	% from within pragma C code (currently only in IL).
	%
:- pred ml_gen_call_current_success_cont_indirectly(prog_context::in,
	mlds__statement::out, ml_gen_info::in, ml_gen_info::out) is det.

%-----------------------------------------------------------------------------%
%
% Routines for dealing with the environment pointer
% used for nested functions.
%

	% Return an rval for a pointer to the current environment
	% (the set of local variables in the containing procedure).
	% Note that we generate this as a dangling reference.
	% The ml_elim_nested pass will insert the declaration
	% of the env_ptr variable.
:- pred ml_get_env_ptr(ml_gen_info::in, mlds__rval::out) is det.

	% Return an mlds__argument for a pointer to the current environment
	% (the set of local variables in the containing procedure).
:- pred ml_declare_env_ptr_arg(mlds__argument::out) is det.

%-----------------------------------------------------------------------------%
%
% Code to handle accurate GC
%

	% ml_gen_maybe_gc_trace_code(Var, Type, Context, Code):
	%
	% If accurate GC is enabled, and the specified
	% variable might contain pointers, generate code to call
	% `private_builtin__gc_trace' to trace the variable.
:- pred ml_gen_maybe_gc_trace_code(var_name::in, prog_type::in,
	prog_context::in, maybe(mlds__statement)::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% ml_gen_maybe_gc_trace_code(Var, DeclType, ActualType, Context, Code):
	%
	% This is the same as the //4 version (above), except that it takes
	% two type arguments, rather than one.  The first
	% (DeclType) is the type that the variable was declared with,
	% while the second (ActualType) is that type that the variable
	% is known to have.  This is used to generate GC tracing code
	% for the temporaries variables used when calling procedures with
	% polymorphically-typed output arguments.
	% In that case, DeclType may be a type variable from the callee's
	% type declaration, but ActualType will be the type from the caller.
	%
	% We can't just use DeclType to generate the GC trace code,
	% because there's no way to compute the type_info for type variables
	% that come from the callee rather than the current procedure.
	% And we can't just use ActualType, since DeclType may contain
	% pointers even when ActualType doesn't (e.g. because DeclType
	% may be a boxed float).  So we need to pass both.
	%
:- pred ml_gen_maybe_gc_trace_code(var_name::in, prog_type::in, prog_type::in,
	prog_context::in, maybe(mlds__statement)::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% ml_gen_maybe_gc_trace_code_with_typeinfo(Var, DeclType, TypeInfoRval,
	%	Context, Code):
	% This is the same as ml_gen_maybe_gc_trace_code//5,
	% except that rather than passing ActualType,
	% the caller constructs the type-info itself,
	% and just passes the rval for it to this routine.
	%
	% This is used by ml_closure_gen.m to generate GC tracing code
	% for the the local variables in closure wrapper functions.
	%
:- pred ml_gen_maybe_gc_trace_code_with_typeinfo(var_name::in, prog_type::in,
	mlds__rval::in, prog_context::in, maybe(mlds__statement)::out,
	ml_gen_info::in, ml_gen_info::out) is det.

%-----------------------------------------------------------------------------%
%
% Magic numbers relating to the representation of
% typeclass_infos, base_typeclass_infos, and closures.
%
	% This function returns the offset to add to the argument
	% number of a closure arg to get its field number.
:- func ml_closure_arg_offset = int.

	% This function returns the offset to add to the argument
	% number of a typeclass_info arg to get its field number.
:- func ml_typeclass_info_arg_offset = int.

	% This function returns the offset to add to the method number
	% for a type class method to get its field number within the
	% base_typeclass_info.
:- func ml_base_typeclass_info_method_offset = int.

%-----------------------------------------------------------------------------%
%
% Miscellaneous routines
%

	% Get the value of the appropriate --det-copy-out or --nondet-copy-out
	% option, depending on the code model.
:- func get_copy_out_option(globals, code_model) = bool.

	% Add the qualifier `builtin' to any unqualified name.
	% Although the builtin types `int', `float', etc. are treated as part
	% of the `builtin' module, for historical reasons they don't have
	% any qualifiers in the HLDS, so we need to add the `builtin'
	% qualifier before converting such names to MLDS.
:- func fixup_builtin_module(module_name) = module_name.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
%
% The `ml_gen_info' ADT.
%

	%
	% The `ml_gen_info' type holds information used during
	% MLDS code generation for a given procedure.
	%
:- type ml_gen_info.

	% initialize the ml_gen_info, so that it is
	% ready for generating code for the given procedure
:- func ml_gen_info_init(module_info, pred_id, proc_id) = ml_gen_info.

	% accessor predicates; these just get the specified
	% information from the ml_gen_info

:- pred ml_gen_info_get_module_info(ml_gen_info::in, module_info::out) is det.
:- pred ml_gen_info_get_module_name(ml_gen_info::in, mercury_module_name::out)
	is det.
:- pred ml_gen_info_get_pred_id(ml_gen_info::in, pred_id::out) is det.
:- pred ml_gen_info_get_proc_id(ml_gen_info::in, proc_id::out) is det.
:- pred ml_gen_info_get_varset(ml_gen_info::in, prog_varset::out) is det.
:- pred ml_gen_info_get_var_types(ml_gen_info::in, vartypes::out) is det.
:- pred ml_gen_info_get_byref_output_vars(ml_gen_info::in, list(prog_var)::out)
	is det.
:- pred ml_gen_info_get_value_output_vars(ml_gen_info::in, list(prog_var)::out)
	is det.
:- pred ml_gen_info_get_globals(ml_gen_info::in, globals::out) is det.

:- pred ml_gen_info_set_byref_output_vars(list(prog_var)::in,
	ml_gen_info::in, ml_gen_info::out) is det.
:- pred ml_gen_info_set_value_output_vars(list(prog_var)::in,
	ml_gen_info::in, ml_gen_info::out) is det.

	% lookup the --gcc-nested-functions option
:- pred ml_gen_info_use_gcc_nested_functions(ml_gen_info::in, bool::out)
	is det.

	% lookup the --put-commit-in-nested-func option
:- pred ml_gen_info_put_commit_in_own_func(ml_gen_info::in, bool::out) is det.

	% Generate a new label number for use in label statements.
	% This is used to give unique names to the case labels generated
	% for dense switch statements.
:- type label_num == int.
:- pred ml_gen_info_new_label(label_num::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% A number corresponding to an MLDS nested function which serves as a
	% label (i.e. a continuation function).
:- type ml_label_func == mlds__func_sequence_num.

	% Generate a new function label number.
	% This is used to give unique names to the nested functions
	% used when generating code for nondet procedures.
:- pred ml_gen_info_new_func_label(ml_label_func::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Increase the function label and const sequence number counters
	% by some amount which is presumed to be sufficient
	% to ensure that if we start again with a fresh
	% ml_gen_info and then call this function,
	% we won't encounter any already-used function labels or constants.
	% (This is used when generating wrapper functions
	% for type class methods.)
:- pred ml_gen_info_bump_counters(ml_gen_info::in, ml_gen_info::out) is det.

	% Generate a new commit label number.
	% This is used to give unique names to the labels
	% used when generating code for commits.
:- type commit_sequence_num == int.
:- pred ml_gen_info_new_commit_label(commit_sequence_num::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Generate a new `cond' variable number.
	% This is used to give unique names to the local
	% variables used to hold the results of
	% nondet conditions of if-then-elses.
:- type cond_seq == int.
:- pred ml_gen_info_new_cond_var(cond_seq::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Generate a new `conv' variable number.
	% This is used to give unique names to the local
	% variables generated by ml_gen_box_or_unbox_lval,
	% which are used to handle boxing/unboxing
	% argument conversions.
:- type conv_seq == int.
:- pred ml_gen_info_new_conv_var(conv_seq::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Generate a new `const' sequence number.
	% This is used to give unique names to the local constants
	% generated for --static-ground-terms, closure layouts,
	% string switch hash tables, etc.
:- type const_seq == int.
:- pred ml_gen_info_new_const(const_seq::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Set the `const' sequence number
	% corresponding to a given HLDS variable.
	%
:- pred ml_gen_info_set_const_num(prog_var::in, const_seq::in,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Lookup the `const' sequence number
	% corresponding to a given HLDS variable.
	%
:- pred ml_gen_info_lookup_const_num(ml_gen_info::in, prog_var::in,
	const_seq::out) is det.

	%
	% A success continuation specifies the (rval for the variable
	% holding the address of the) function that a nondet procedure
	% should call if it succeeds, and possibly also the
	% (rval for the variable holding) the environment pointer
	% for that function, and possibly also the (list of rvals
	% for the) arguments to the continuation.
	%
:- type success_cont
	--->	success_cont(
			mlds__rval,	% function pointer
			mlds__rval,	% environment pointer
				% note that if we're using nested
				% functions then the environment
				% pointer will not be used
			list(mlds__type), % argument types, if any
			list(mlds__lval)  % arguments, if any
				% The arguments will only be non-empty if the
				% --nondet-copy-out option is enabled.
				% They do not include the environment pointer.
		).

	%
	% The ml_gen_info contains a stack of success continuations.
	% The following routines provide access to that stack.
	%

:- pred ml_gen_info_push_success_cont(success_cont::in,
	ml_gen_info::in, ml_gen_info::out) is det.

:- pred ml_gen_info_pop_success_cont(ml_gen_info::in, ml_gen_info::out) is det.

:- pred ml_gen_info_current_success_cont(success_cont::out,
	ml_gen_info::in, ml_gen_info::out) is det.

	%
	% We keep a partial mapping from vars to lvals.
	% This is used in special cases to override the normal
	% lval for a variable.  ml_gen_var will check this
	% map first, and if the variable is not in this map,
	% then it will go ahead and generate an lval for it
	% as usual.
	%

	% Set the lval for a variable.
:- pred ml_gen_info_set_var_lval(prog_var::in, mlds__lval::in,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Get the partial mapping from variables to lvals.
:- pred ml_gen_info_get_var_lvals(ml_gen_info::in,
	map(prog_var, mlds__lval)::out) is det.

	% Set the partial mapping from variables to lvals.
:- pred ml_gen_info_set_var_lvals(map(prog_var, mlds__lval)::in,
	ml_gen_info::in, ml_gen_info::out) is det.

	%
	% The ml_gen_info contains a list of extra definitions
	% of functions or global constants which should be inserted
	% before the definition of the function for the current procedure.
	% This is used for the definitions of the wrapper functions needed
	% for closures.  When generating code for a procedure that creates
	% a closure, we insert the definition of the wrapper function used
	% for that closure into this list.
	%

	% Insert an extra definition at the start of the list of extra
	% definitions.
:- pred ml_gen_info_add_extra_defn(mlds__defn::in,
	ml_gen_info::in, ml_gen_info::out) is det.

	% Get the list of extra definitions.
:- pred ml_gen_info_get_extra_defns(ml_gen_info::in, mlds__defns::out) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- import_module backend_libs__foreign.
:- import_module backend_libs__rtti.
:- import_module check_hlds__mode_util.
:- import_module check_hlds__polymorphism.
:- import_module check_hlds__type_util.
:- import_module hlds__hlds_goal.
:- import_module hlds__instmap.
:- import_module hlds__special_pred.
:- import_module libs__globals.
:- import_module libs__options.
:- import_module ml_backend__ml_call_gen.
:- import_module ml_backend__ml_code_gen.
:- import_module parse_tree__error_util.
:- import_module parse_tree__prog_data.
:- import_module parse_tree__prog_io.
:- import_module parse_tree__prog_util.

:- import_module counter, stack, string, require, set, term, varset.

%-----------------------------------------------------------------------------%
%
% Code for various utility routines
%

	% Generate an MLDS assignment statement.
ml_gen_assign(Lval, Rval, Context) = Statement :-
	Assign = assign(Lval, Rval),
	Stmt = atomic(Assign),
	Statement = mlds__statement(Stmt, mlds__make_context(Context)).

	%
	% Append an appropriate `return' statement for the given code_model
	% and returning the given OutputVarLvals, if needed.
	%
ml_append_return_statement(Info, CodeModel, CopiedOutputVarLvals, Context,
		!Statements) :-
	(
		CodeModel = model_semi
	->
		ml_gen_test_success(Info, Succeeded),
		CopiedOutputVarRvals = list__map(func(Lval) = lval(Lval),
			CopiedOutputVarLvals),
		ReturnStmt = return([Succeeded | CopiedOutputVarRvals]),
		ReturnStatement = mlds__statement(ReturnStmt,
			mlds__make_context(Context)),
		!:Statements = list__append(!.Statements, [ReturnStatement])
	;
		CodeModel \= model_non,
		CopiedOutputVarLvals \= []
	->
		CopiedOutputVarRvals = list__map(func(Lval) = lval(Lval),
			CopiedOutputVarLvals),
		ReturnStmt = return(CopiedOutputVarRvals),
		ReturnStatement = mlds__statement(ReturnStmt,
			mlds__make_context(Context)),
		!:Statements = list__append(!.Statements, [ReturnStatement])
	;
		true
	).

	% Generate a block statement, i.e. `{ <Decls>; <Statements>; }'.
	% But if the block consists only of a single statement with no
	% declarations, then just return that statement.
	%
ml_gen_block(VarDecls, Statements, Context) =
	(
		VarDecls = [],
		Statements = [SingleStatement]
	->
		SingleStatement
	;
		mlds__statement(block(VarDecls, Statements),
			mlds__make_context(Context))
	).

	% ml_join_decls:
	% 	Join two statement lists and their corresponding
	% 	declaration lists in sequence.
	%
	% 	If the statements have no declarations in common,
	% 	then their corresponding declaration lists will be
	% 	concatenated together into a single list of declarations.
	% 	But if they have any declarations in common, then we
	% 	put each statement list and its declarations into
	% 	a block, so that the declarations remain local to
	% 	each statement list.
	%
ml_join_decls(FirstDecls, FirstStatements, RestDecls, RestStatements, Context,
		Decls, Statements) :-
	(
		list__member(mlds__defn(Name, _, _, _), FirstDecls),
		list__member(mlds__defn(Name, _, _, _), RestDecls)
	->
		First = ml_gen_block(FirstDecls, FirstStatements, Context),
		Rest = ml_gen_block(RestDecls, RestStatements, Context),
		Decls = [],
		Statements = [First, Rest]
	;
		Decls = list__append(FirstDecls, RestDecls),
		Statements = list__append(FirstStatements, RestStatements)
	).

	% ml_combine_conj:
	%	Given closures to generate code for two conjuncts,
	%	generate code for their conjunction.
	%
ml_combine_conj(FirstCodeModel, Context, DoGenFirst, DoGenRest,
		Decls, Statements, !Info) :-
	(
		%	model_det goal:
		%		<First, Rest>
		% 	===>
		%		<do First>
		%		<Rest>
		%
		FirstCodeModel = model_det,
		DoGenFirst(FirstDecls, FirstStatements, !Info),
		DoGenRest(RestDecls, RestStatements, !Info),
		ml_join_decls(FirstDecls, FirstStatements,
			RestDecls, RestStatements, Context,
			Decls, Statements)
	;
		%	model_semi goal:
		%		<Goal, Goals>
		% 	===>
		%		MR_bool succeeded;
		%
		%		<succeeded = Goal>;
		%		if (succeeded) {
		%			<Goals>;
		%		}
		%	except that we hoist any declarations generated
		%	for <Goals> to the outer scope, rather than
		%	inside the `if', so that they remain in
		%	scope for any later goals which follow this
		%	(this is needed for declarations of static consts)
		FirstCodeModel = model_semi,
		DoGenFirst(FirstDecls, FirstStatements, !Info),
		ml_gen_test_success(!.Info, Succeeded),
		DoGenRest(RestDecls, RestStatements, !Info),
		IfBody = ml_gen_block([], RestStatements, Context),
		IfStmt = if_then_else(Succeeded, IfBody, no),
		IfStatement = mlds__statement(IfStmt,
			mlds__make_context(Context)),
		Decls = list__append(FirstDecls, RestDecls),
		Statements = list__append(FirstStatements, [IfStatement])
	;
		%	model_non goal:
		%		<First, Rest>
		% 	===>
		%		succ_func() {
		%			<Rest && SUCCEED()>;
		%		}
		%
		%		<First && succ_func()>;
		%	except that we hoist any declarations generated
		%	for <First> and any _static_ declarations generated
		%	for <Rest> to the top of the scope, rather
		%	than inside or after the succ_func(), so that they
		%	remain in scope for any code following them
		%	(this is needed for declarations of static consts).
		%
		%	We take care to only hoist _static_ declarations
		%	outside nested functions, since access to non-local
		%	variables is less efficient.
		%
		% XXX The pattern above leads to deep nesting for long
		%     conjunctions; we should avoid that.
		%

		FirstCodeModel = model_non,

		% allocate a name for the `succ_func'
		ml_gen_new_func_label(no, RestFuncLabel, RestFuncLabelRval,
			!Info),

		% generate <First && succ_func()>
		ml_get_env_ptr(!.Info, EnvPtrRval),
		SuccessCont = success_cont(RestFuncLabelRval,
			EnvPtrRval, [], []),
		ml_gen_info_push_success_cont(SuccessCont, !Info),
		DoGenFirst(FirstDecls, FirstStatements, !Info),
		ml_gen_info_pop_success_cont(!Info),

		% generate the `succ_func'
		/* push nesting level */
		DoGenRest(RestDecls, RestStatements, !Info),
		list__filter(ml_decl_is_static_const, RestDecls,
			RestStaticDecls, RestOtherDecls),
		RestStatement = ml_gen_block(RestOtherDecls, RestStatements,
			Context),
		/* pop nesting level */
		ml_gen_nondet_label_func(!.Info, RestFuncLabel, Context,
			RestStatement, RestFunc),

		Decls = list__condense(
			[FirstDecls, RestStaticDecls, [RestFunc]]),
		Statements = FirstStatements
	).

	% Succeed iff the specified mlds__defn defines
	% a static constant.
	%
ml_decl_is_static_const(Defn) :-
	Defn = mlds__defn(Name, _Context, Flags, _DefnBody),
	Name = data(_),
	Flags = ml_static_const_decl_flags.

	% Given a function label and the statement which will comprise
	% the function body for that function, generate an mlds__defn
	% which defines that function.
	%
ml_gen_nondet_label_func(Info, FuncLabel, Context, Statement, Func) :-
	ml_gen_info_use_gcc_nested_functions(Info, UseNested),
	( UseNested = yes ->
		FuncParams = mlds__func_params([], [])
	;
		ml_declare_env_ptr_arg(EnvPtrArg),
		FuncParams = mlds__func_params([EnvPtrArg], [])
	),
	ml_gen_label_func(Info, FuncLabel, FuncParams, Context, Statement,
		Func).

	% Given a function label, the function parameters, and the statement
	% which will comprise the function body for that function,
	% generate an mlds__defn which defines that function.
	%
ml_gen_label_func(Info, FuncLabel, FuncParams, Context, Statement, Func) :-
	%
	% compute the function name
	%
	ml_gen_info_get_module_info(Info, ModuleInfo),
	ml_gen_info_get_pred_id(Info, PredId),
	ml_gen_info_get_proc_id(Info, ProcId),
	FuncName = ml_gen_nondet_label(ModuleInfo, PredId, ProcId, FuncLabel),

	%
	% compute the function definition
	%
	DeclFlags = ml_gen_label_func_decl_flags,
	MaybePredProcId = no,
	Attributes = [],
	FuncDefn = function(MaybePredProcId, FuncParams,
		defined_here(Statement), Attributes),
	Func = mlds__defn(FuncName, mlds__make_context(Context), DeclFlags,
		FuncDefn).

	% Return the declaration flags appropriate for a label func
	% (a label func is a function used as a continuation
	% when generating nondet code).
	%
:- func ml_gen_label_func_decl_flags = mlds__decl_flags.
ml_gen_label_func_decl_flags = DeclFlags :-
	Access = local,
	PerInstance = per_instance,
	Virtuality = non_virtual,
	Finality = overridable,
	Constness = modifiable,
	Abstractness = concrete,
	DeclFlags = init_decl_flags(Access, PerInstance,
		Virtuality, Finality, Constness, Abstractness).

%-----------------------------------------------------------------------------%
%
% Code for generating expressions.
%

ml_gen_and(X, Y) =
	(if X = const(true) then
		Y
	else if Y = const(true) then
		X
	else
		binop((and), X, Y)
	).

ml_gen_not(X) = unop(std_unop(not), X).

%-----------------------------------------------------------------------------%
%
% Code for generating types.
%

ml_gen_type(Info, Type, MLDS_Type) :-
	ml_gen_info_get_module_info(Info, ModuleInfo),
	MLDS_Type = mercury_type_to_mlds_type(ModuleInfo, Type).

ml_gen_array_elem_type(elem_type_string) = ml_string_type.
ml_gen_array_elem_type(elem_type_int) = mlds__native_int_type.
ml_gen_array_elem_type(elem_type_generic) = mlds__generic_type.

ml_string_type = mercury_type(string_type, str_type,
				non_foreign_type(string_type)).

ml_make_boxed_types(Arity) = BoxedTypes :-
	varset__init(TypeVarSet0),
	varset__new_vars(TypeVarSet0, Arity, BoxedTypeVars, _TypeVarSet),
	term__var_list_to_term_list(BoxedTypeVars, BoxedTypes).

%-----------------------------------------------------------------------------%
%
% Code for generating function declarations (i.e. mlds__func_params).
%

	% Generate the function prototype for a given procedure.
	%
ml_gen_proc_params(ModuleInfo, PredId, ProcId) = FuncParams :-
	module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
		PredInfo, ProcInfo),
	proc_info_varset(ProcInfo, VarSet),
	proc_info_headvars(ProcInfo, HeadVars),
	PredOrFunc = pred_info_is_pred_or_func(PredInfo),
	pred_info_arg_types(PredInfo, HeadTypes),
	proc_info_argmodes(ProcInfo, HeadModes),
	proc_info_interface_code_model(ProcInfo, CodeModel),
	HeadVarNames = ml_gen_var_names(VarSet, HeadVars),
	FuncParams = ml_gen_params(ModuleInfo, HeadVarNames, HeadTypes,
		HeadModes, PredOrFunc, CodeModel).

ml_gen_proc_params(PredId, ProcId, FuncParams, !Info) :-
	ModuleInfo = !.Info  ^  module_info,
	module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
		PredInfo, ProcInfo),
	proc_info_varset(ProcInfo, VarSet),
	proc_info_headvars(ProcInfo, HeadVars),
	PredOrFunc = pred_info_is_pred_or_func(PredInfo),
	pred_info_arg_types(PredInfo, HeadTypes),
	proc_info_argmodes(ProcInfo, HeadModes),
	proc_info_interface_code_model(ProcInfo, CodeModel),
	HeadVarNames = ml_gen_var_names(VarSet, HeadVars),
	% we must not generate GC tracing code for no_type_info_builtin
	% procedures, because the generated GC tracing code would refer
	% to type_infos that don't get passed
	PredModule = pred_info_module(PredInfo),
	PredName = pred_info_name(PredInfo),
	PredArity = pred_info_arity(PredInfo),
	( no_type_info_builtin(PredModule, PredName, PredArity) ->
		FuncParams = ml_gen_params(ModuleInfo, HeadVarNames, HeadTypes,
			HeadModes, PredOrFunc, CodeModel)
	;
		ml_gen_params(HeadVarNames, HeadTypes, HeadModes, PredOrFunc,
			CodeModel, FuncParams, !Info)
	).

	% As above, but from the rtti_proc_id rather than
	% from the module_info, pred_id, and proc_id.
	%
ml_gen_proc_params_from_rtti(ModuleInfo, RttiProcId) = FuncParams :-
	HeadVars = RttiProcId ^ proc_headvars,
	ArgTypes = RttiProcId ^ proc_arg_types,
	ArgModes = RttiProcId ^ proc_arg_modes,
	PredOrFunc = RttiProcId^pred_or_func,
	Detism = RttiProcId^proc_interface_detism,
	determinism_to_code_model(Detism, CodeModel),
	HeadVarNames = list__map((func(Var - Name) = Result :-
			term__var_to_int(Var, N),
			Result = mlds__var_name(Name, yes(N))
		), HeadVars),
	ml_gen_params_base(ModuleInfo, HeadVarNames, ArgTypes, ArgModes,
		PredOrFunc, CodeModel, FuncParams, no, _).

	% Generate the function prototype for a procedure with the
	% given argument types, modes, and code model.
	%
ml_gen_params(ModuleInfo, HeadVarNames, HeadTypes, HeadModes, PredOrFunc,
		CodeModel) = FuncParams :-
	modes_to_arg_modes(ModuleInfo, HeadModes, HeadTypes, ArgModes),
	ml_gen_params_base(ModuleInfo, HeadVarNames, HeadTypes, ArgModes,
		PredOrFunc, CodeModel, FuncParams, no, _).

ml_gen_params(HeadVarNames, HeadTypes, HeadModes, PredOrFunc,
		CodeModel, FuncParams, !Info) :-
	ModuleInfo = !.Info ^ module_info,
	modes_to_arg_modes(ModuleInfo, HeadModes, HeadTypes, ArgModes),
	ml_gen_params_base(ModuleInfo, HeadVarNames,
		HeadTypes, ArgModes, PredOrFunc, CodeModel, FuncParams,
		yes(!.Info), MaybeInfo),
	( MaybeInfo = yes(Info) ->
		!:Info = Info
	;
		error("ml_gen_params: missing ml_gen_info")
	).

:- pred ml_gen_params_base(module_info::in, list(mlds__var_name)::in,
	list(prog_type)::in, list(arg_mode)::in, pred_or_func::in,
	code_model::in, mlds__func_params::out,
	maybe(ml_gen_info)::in, maybe(ml_gen_info)::out) is det.

ml_gen_params_base(ModuleInfo, HeadVarNames, HeadTypes, HeadModes,
		PredOrFunc, CodeModel, FuncParams, !MaybeInfo) :-
	module_info_globals(ModuleInfo, Globals),
	CopyOut = get_copy_out_option(Globals, CodeModel),
	ml_gen_arg_decls(ModuleInfo, HeadVarNames, HeadTypes, HeadModes,
		CopyOut, FuncArgs0, RetTypes0, !MaybeInfo),
	(
		CodeModel = model_det,
		%
		% for model_det Mercury functions whose result argument has an
		% output mode, make the result into the MLDS return type
		%
		(
			RetTypes0 = [],
			PredOrFunc = function,
			pred_args_to_func_args(HeadModes, _, ResultMode),
			ResultMode = top_out,
			pred_args_to_func_args(HeadTypes, _, ResultType),
			\+ type_util__is_dummy_argument_type(ResultType)
		->
			pred_args_to_func_args(FuncArgs0, FuncArgs, RetArg),
			RetArg = mlds__argument(_RetArgName, RetTypePtr,
					_GC_TraceCode),
			( RetTypePtr = mlds__ptr_type(RetType) ->
				RetTypes = [RetType]
			;
				error("output mode function result doesn't have pointer type")
			)
		;
			FuncArgs = FuncArgs0,
			RetTypes = RetTypes0
		)
	;
		CodeModel = model_semi,
		%
		% for model_semi procedures, return a bool
		%
		FuncArgs = FuncArgs0,
		RetTypes = [mlds__native_bool_type | RetTypes0]
	;
		CodeModel = model_non,
		%
		% for model_non procedures, we return values
		% by passing them to the continuation
		%
		( CopyOut = yes ->
			ContType = mlds__cont_type(RetTypes0),
			RetTypes = []
		;
			ContType = mlds__cont_type([]),
			RetTypes = RetTypes0
		),
		ContName = data(var(var_name("cont", no))),
		% The cont variable always points to code, not to the heap,
		% so the GC never needs to trace it.
		ContGCTraceCode = no,
		ContArg = mlds__argument(ContName, ContType, ContGCTraceCode),
		ContEnvType = mlds__generic_env_ptr_type,
		ContEnvName = data(var(var_name("cont_env_ptr", no))),
		% The cont_env_ptr always points to the stack,
		% since continuation environments are always allocated
		% on the stack (unless put_nondet_env_on_heap is true,
		% which won't be the case when doing our own GC --
		% this is enforced in handle_options.m).
		% So the GC doesn't need to trace it.
		ContEnvGCTraceCode = no,
		ContEnvArg = mlds__argument(ContEnvName, ContEnvType,
			ContEnvGCTraceCode),
		globals__lookup_bool_option(Globals, gcc_nested_functions,
			NestedFunctions),
		(
			NestedFunctions = yes
		->
			FuncArgs = FuncArgs0 ++ [ContArg]
		;
			FuncArgs = FuncArgs0 ++ [ContArg, ContEnvArg]
		)
	),
	FuncParams = mlds__func_params(FuncArgs, RetTypes).

	% Given the argument variable names, and corresponding lists of their
	% types and modes, generate the MLDS argument declarations
	% and return types.
	%
:- pred ml_gen_arg_decls(module_info::in, list(mlds__var_name)::in,
	list(prog_type)::in, list(arg_mode)::in, bool::in,
	mlds__arguments::out, mlds__return_types::out,
	maybe(ml_gen_info)::in, maybe(ml_gen_info)::out) is det.

ml_gen_arg_decls(ModuleInfo, HeadVars, HeadTypes, HeadModes, CopyOut,
		FuncArgs, RetTypes, !MaybeInfo) :-
	(
		HeadVars = [],
		HeadTypes = [],
		HeadModes = []
	->
		FuncArgs = [],
		RetTypes = []
	;
		HeadVars = [Var | Vars],
		HeadTypes = [Type | Types],
		HeadModes = [Mode | Modes]
	->
		ml_gen_arg_decls(ModuleInfo, Vars, Types, Modes, CopyOut,
			FuncArgs0, RetTypes0, !MaybeInfo),
		(
			%
			% Exclude types such as io__state, etc.
			% Also exclude values with arg_mode `top_unused'.
			%
			( type_util__is_dummy_argument_type(Type)
			; Mode = top_unused
			)
		->
			FuncArgs = FuncArgs0,
			RetTypes = RetTypes0
		;
			%
			% for by-value outputs, generate a return type
			%
			Mode = top_out,
			CopyOut = yes
		->
			RetType = mercury_type_to_mlds_type(ModuleInfo, Type),
			RetTypes = [RetType | RetTypes0],
			FuncArgs = FuncArgs0
		;
			%
			% for inputs and by-reference outputs,
			% generate argument
			%
			ml_gen_arg_decl(ModuleInfo, Var, Type, Mode, FuncArg,
				!MaybeInfo),
			FuncArgs = [FuncArg | FuncArgs0],
			RetTypes = RetTypes0
		)
	;
		error("ml_gen_arg_decls: length mismatch")
	).

	% Given an argument variable, and its type and mode,
	% generate an MLDS argument declaration for it.
	%
:- pred ml_gen_arg_decl(module_info::in, var_name::in, prog_type::in,
	arg_mode::in, mlds__argument::out,
	maybe(ml_gen_info)::in, maybe(ml_gen_info)::out) is det.

ml_gen_arg_decl(ModuleInfo, Var, Type, ArgMode, FuncArg, !MaybeInfo) :-
	MLDS_Type = mercury_type_to_mlds_type(ModuleInfo, Type),
	( ArgMode \= top_in ->
		MLDS_ArgType = mlds__ptr_type(MLDS_Type)
	;
		MLDS_ArgType = MLDS_Type
	),
	Name = data(var(Var)),
	( !.MaybeInfo = yes(Info0) ->
		% XXX We should fill in this Context properly
		term__context_init(Context),
		ml_gen_maybe_gc_trace_code(Var, Type, Context,
			Maybe_GC_TraceCode, Info0, Info),
		!:MaybeInfo = yes(Info)
	;
		Maybe_GC_TraceCode = no,
		!:MaybeInfo = no
	),
	FuncArg = mlds__argument(Name, MLDS_ArgType, Maybe_GC_TraceCode).

ml_is_output_det_function(ModuleInfo, PredId, ProcId, RetArgVar) :-
	module_info_pred_proc_info(ModuleInfo, PredId, ProcId, PredInfo,
		ProcInfo),
	pred_info_is_pred_or_func(PredInfo) = function,
	proc_info_interface_code_model(ProcInfo, model_det),

	proc_info_argmodes(ProcInfo, Modes),
	pred_info_arg_types(PredInfo, ArgTypes),
	proc_info_headvars(ProcInfo, ArgVars),
	modes_to_arg_modes(ModuleInfo, Modes, ArgTypes, ArgModes),
	pred_args_to_func_args(ArgModes, _InputArgModes, RetArgMode),
	pred_args_to_func_args(ArgTypes, _InputArgTypes, RetArgType),
	pred_args_to_func_args(ArgVars, _InputArgVars, RetArgVar),

	RetArgMode = top_out,
	\+ type_util__is_dummy_argument_type(RetArgType).

%-----------------------------------------------------------------------------%
%
% Code for generating mlds__entity_names.
%

	% Generate the mlds__entity_name and module name for the entry point
	% function corresponding to a given procedure.
	%
ml_gen_proc_label(ModuleInfo, PredId, ProcId, MLDS_Name, MLDS_ModuleName) :-
	ml_gen_func_label(ModuleInfo, PredId, ProcId, no,
		MLDS_Name, MLDS_ModuleName).

	% Generate an mlds__entity_name for a continuation function
	% with the given sequence number.  The pred_id and proc_id
	% specify the procedure that this continuation function
	% is part of.
	%
ml_gen_nondet_label(ModuleInfo, PredId, ProcId, SeqNum) = MLDS_Name :-
	ml_gen_func_label(ModuleInfo, PredId, ProcId, yes(SeqNum),
		MLDS_Name, _MLDS_ModuleName).

:- pred ml_gen_func_label(module_info::in, pred_id::in, proc_id::in,
	maybe(ml_label_func)::in, mlds__entity_name::out,
	mlds_module_name::out) is det.

ml_gen_func_label(ModuleInfo, PredId, ProcId, MaybeSeqNum,
		MLDS_Name, MLDS_ModuleName) :-
	ml_gen_pred_label(ModuleInfo, PredId, ProcId,
		MLDS_PredLabel, MLDS_ModuleName),
	MLDS_Name = function(MLDS_PredLabel, ProcId, MaybeSeqNum, PredId).

	% Allocate a new function label and return an rval containing
	% the function's address.
	%
ml_gen_new_func_label(MaybeParams, FuncLabel, FuncLabelRval, !Info) :-
	ml_gen_info_new_func_label(FuncLabel, !Info),
	ml_gen_info_get_module_info(!.Info, ModuleInfo),
	ml_gen_info_get_pred_id(!.Info, PredId),
	ml_gen_info_get_proc_id(!.Info, ProcId),
	ml_gen_pred_label(ModuleInfo, PredId, ProcId,
		PredLabel, PredModule),
	ml_gen_info_use_gcc_nested_functions(!.Info, UseNestedFuncs),
	( MaybeParams = yes(Params) ->
		Signature = mlds__get_func_signature(Params)
	;
		( UseNestedFuncs = yes ->
			ArgTypes = []
		;
			ArgTypes = [mlds__generic_env_ptr_type]
		),
		Signature = mlds__func_signature(ArgTypes, [])
	),
	ProcLabel = qual(PredModule, PredLabel - ProcId),
	FuncLabelRval = const(code_addr_const(internal(ProcLabel,
		FuncLabel, Signature))).

	% Generate the mlds__pred_label and module name
	% for a given procedure.
	%
ml_gen_pred_label(ModuleInfo, PredId, ProcId, MLDS_PredLabel, MLDS_Module) :-
	RttiProcLabel = rtti__make_rtti_proc_label(ModuleInfo, PredId, ProcId),
	ml_gen_pred_label_from_rtti(ModuleInfo, RttiProcLabel,
		MLDS_PredLabel, MLDS_Module).

ml_gen_pred_label_from_rtti(ModuleInfo, RttiProcLabel, MLDS_PredLabel,
		MLDS_Module) :-
	RttiProcLabel = rtti_proc_label(PredOrFunc, ThisModule, PredModule,
		PredName, PredArity, _ArgTypes, PredId, ProcId,
		_HeadVarsWithNames, _ArgModes, Detism,
		PredIsImported, _PredIsPseudoImported,
		IsSpecialPred, _ProcIsExported, _ProcIsImported),
	( IsSpecialPred = yes(SpecialPred - TypeCtor) ->
		(
			% All type_ctors other than tuples here should be
			% module qualified, since builtin types are handled
			% separately in polymorphism.m.
			(
				TypeCtor = unqualified(TypeName) - TypeArity,
				type_ctor_is_tuple(TypeCtor),
				mercury_public_builtin_module(TypeModule)
			;
				TypeCtor = qualified(TypeModule, TypeName)
					- TypeArity
			)
		->
			(
				ThisModule \= TypeModule,
				SpecialPred = unify,
				\+ hlds_pred__in_in_unification_proc_id(ProcId)
			->
				% This is a locally-defined instance
				% of a unification procedure for a type
				% defined in some other module
				DefiningModule = ThisModule,
				MaybeDeclaringModule = yes(TypeModule)
			;
				% the module declaring the type is the same as
				% the module defining this special pred
				DefiningModule = TypeModule,
				MaybeDeclaringModule = no
			),
			MLDS_PredLabel = special_pred(PredName,
				MaybeDeclaringModule, TypeName, TypeArity)
		;
			string__append_list(["ml_gen_pred_label:\n",
				"cannot make label for special pred `",
				PredName, "'"], ErrorMessage),
			error(ErrorMessage)
		)
	;
		(
			% Work out which module supplies the code for
			% the predicate.
			ThisModule \= PredModule,
			PredIsImported = no
		->
			% This predicate is a specialized version of
			% a pred from a `.opt' file.
			DefiningModule = ThisModule,
			MaybeDeclaringModule = yes(PredModule)
		;
			% The predicate was declared in the same module
			% that it is defined in
			DefiningModule = PredModule,
			MaybeDeclaringModule = no
		),
		(
			PredOrFunc = function,
			\+ ml_is_output_det_function(ModuleInfo, PredId,
				ProcId, _)
		->
			NonOutputFunc = yes
		;
			NonOutputFunc = no
		),
		determinism_to_code_model(Detism, CodeModel),
		MLDS_PredLabel = pred(PredOrFunc, MaybeDeclaringModule,
			PredName, PredArity, CodeModel, NonOutputFunc)
	),
	MLDS_Module = mercury_module_name_to_mlds(DefiningModule).

ml_gen_new_label(Label, !Info) :-
	ml_gen_info_new_label(LabelNum, !Info),
	string__format("label_%d", [i(LabelNum)], Label).

%-----------------------------------------------------------------------------%
%
% Code for dealing with variables
%

	% Generate a list of the mlds__lvals corresponding to a
	% given list of prog_vars.
	%
ml_gen_var_list(_Info, [], []).
ml_gen_var_list(Info, [Var | Vars], [Lval | Lvals]) :-
	ml_gen_var(Info, Var, Lval),
	ml_gen_var_list(Info, Vars, Lvals).

	% Generate the mlds__lval corresponding to a given prog_var.
	%
ml_gen_var(Info, Var, Lval) :-
	%
	% First check the var_lvals override mapping;
	% if an lval has been set for this variable, use it
	%
	ml_gen_info_get_var_lvals(Info, VarLvals),
	( map__search(VarLvals, Var, VarLval) ->
		Lval = VarLval
	;
		%
		% Otherwise just look up the variable's type
		% and generate an lval for it using the ordinary
		% algorithm.
		%
		ml_variable_type(Info, Var, Type),
		ml_gen_var_with_type(Info, Var, Type, Lval)
	).

	% Generate the mlds__lval corresponding to a given prog_var,
	% with a given type.
	%
ml_gen_var_with_type(Info, Var, Type, Lval) :-
	( type_util__is_dummy_argument_type(Type) ->
		%
		% The variable won't have been declared, so
		% we need to generate a dummy lval for this variable.
		%
		mercury_private_builtin_module(PrivateBuiltin),
		MLDS_Module = mercury_module_name_to_mlds(PrivateBuiltin),
		ml_gen_type(Info, Type, MLDS_Type),
		Lval = var(qual(MLDS_Module, var_name("dummy_var", no)),
			MLDS_Type)
	;
		ml_gen_info_get_varset(Info, VarSet),
		VarName = ml_gen_var_name(VarSet, Var),
		ml_gen_type(Info, Type, MLDS_Type),
		ml_gen_var_lval(Info, VarName, MLDS_Type, VarLval),
		%
		% output variables may be passed by reference...
		%
		ml_gen_info_get_byref_output_vars(Info, OutputVars),
		( list__member(Var, OutputVars) ->
			Lval = mem_ref(lval(VarLval), MLDS_Type)
		;
			Lval = VarLval
		)
	).

	% Lookup the types of a list of variables.
	%
ml_variable_types(_Info, [], []).
ml_variable_types(Info, [Var | Vars], [Type | Types]) :-
	ml_variable_type(Info, Var, Type),
	ml_variable_types(Info, Vars, Types).

	% Lookup the type of a variable.
	%
ml_variable_type(Info, Var, Type) :-
	ml_gen_info_get_var_types(Info, VarTypes),
	map__lookup(VarTypes, Var, Type).

	% Generate the MLDS variable names for a list of HLDS variables.
	%
ml_gen_var_names(VarSet, Vars) = list__map(ml_gen_var_name(VarSet), Vars).

	% Generate the MLDS variable name for an HLDS variable.
	%
ml_gen_var_name(VarSet, Var) = UniqueVarName :-
	varset__lookup_name(VarSet, Var, VarName),
	term__var_to_int(Var, VarNumber),
	UniqueVarName = mlds__var_name(VarName, yes(VarNumber)).

	% ml_format_reserved_object_name(CtorName, CtorArity, ReservedObjName):
	% Generate a name for a specially reserved global variable
	% (or static member variable)
	% whose address is used to represent the specified constructor.
	%
	% We add the "obj_" prefix to avoid any potential name clashes.
	%
ml_format_reserved_object_name(CtorName, CtorArity) = ReservedObjName :-
	Name = string__format("obj_%s_%d", [s(CtorName), i(CtorArity)]),
	ReservedObjName = var_name(Name, no).

	% Generate a name for a local static constant.
	%
	% To ensure that the names are unique, we qualify them with the
	% pred_id and proc_id numbers, as well as a sequence number.
	% This is needed to allow ml_elim_nested.m to hoist
	% such constants out to top level.
ml_format_static_const_name(Info, BaseName, SequenceNum, ConstName) :-
	ml_gen_info_get_pred_id(Info, PredId),
	ml_gen_info_get_proc_id(Info, ProcId),
	pred_id_to_int(PredId, PredIdNum),
	proc_id_to_int(ProcId, ProcIdNum),
	ConstName = mlds__var_name(
		string__format("const_%d_%d_%d_%s", [i(PredIdNum),
			i(ProcIdNum), i(SequenceNum), s(BaseName)]), no).

	% Qualify the name of the specified variable
	% with the current module name.
	%
ml_gen_var_lval(Info, VarName, VarType, QualifiedVarLval) :-
	ml_gen_info_get_module_name(Info, ModuleName),
	MLDS_Module = mercury_module_name_to_mlds(ModuleName),
	QualifiedVarLval = var(qual(MLDS_Module, VarName), VarType).

	% Generate a declaration for an MLDS variable, given its HLDS type.
	%
ml_gen_var_decl(VarName, Type, Context, Defn, !Info) :-
	ml_gen_info_get_module_info(!.Info, ModuleInfo),
	ml_gen_maybe_gc_trace_code(VarName, Type, Context, GC_TraceCode,
		!Info),
	Defn = ml_gen_mlds_var_decl(var(VarName),
		mercury_type_to_mlds_type(ModuleInfo, Type),
		GC_TraceCode, mlds__make_context(Context)).

	% Generate a declaration for an MLDS variable, given its MLDS type.
	%
ml_gen_mlds_var_decl(DataName, MLDS_Type, GC_TraceCode, Context) =
	ml_gen_mlds_var_decl(DataName, MLDS_Type, no_initializer, GC_TraceCode,
		Context).

	% Generate a declaration for an MLDS variable, given its MLDS type
	% and initializer.
	%
ml_gen_mlds_var_decl(DataName, MLDS_Type, Initializer, GC_TraceCode, Context) =
		MLDS_Defn :-
	Name = data(DataName),
	Defn = data(MLDS_Type, Initializer, GC_TraceCode),
	DeclFlags = ml_gen_local_var_decl_flags,
	MLDS_Defn = mlds__defn(Name, Context, DeclFlags, Defn).

	% Generate a definition of a local static constant,
	% given the constant's name, type, and initializer.
	%
ml_gen_static_const_defn(ConstName, ConstType, Access, Initializer, Context) =
		MLDS_Defn :-
	Name = data(var(ConstName)),
	% The GC never needs to trace static constants,
	% because they can never point into the heap
	% (only to other static constants).
	GC_TraceCode = no,
	Defn = data(ConstType, Initializer, GC_TraceCode),
	DeclFlags = mlds__set_access(ml_static_const_decl_flags, Access),
	MLDS_Context = mlds__make_context(Context),
	MLDS_Defn = mlds__defn(Name, MLDS_Context, DeclFlags, Defn).

	% Return the declaration flags appropriate for a public field
	% in the derived constructor class of a discriminated union.
	%
ml_gen_public_field_decl_flags = DeclFlags :-
	Access = public,
	PerInstance = per_instance,
	Virtuality = non_virtual,
	Finality = overridable,
	Constness = modifiable,
	Abstractness = concrete,
	DeclFlags = init_decl_flags(Access, PerInstance,
		Virtuality, Finality, Constness, Abstractness).

	% Return the declaration flags appropriate for a local variable.
ml_gen_local_var_decl_flags = DeclFlags :-
	Access = local,
	PerInstance = per_instance,
	Virtuality = non_virtual,
	Finality = overridable,
	Constness = modifiable,
	Abstractness = concrete,
	DeclFlags = init_decl_flags(Access, PerInstance,
		Virtuality, Finality, Constness, Abstractness).

	% Return the declaration flags appropriate for an
	% initialized local static constant.
	% Note that rtti_decl_flags, in rtti_to_mlds.m,
	% must be the same as this apart from the access.
	%
ml_static_const_decl_flags = DeclFlags :-
	Access = local,
	PerInstance = one_copy,
	Virtuality = non_virtual,
	Finality = final,
	Constness = const,
	Abstractness = concrete,
	DeclFlags = init_decl_flags(Access, PerInstance,
		Virtuality, Finality, Constness, Abstractness).

ml_var_name_to_string(var_name(Var, yes(Num))) =
	string__format("%s_%d", [s(Var), i(Num)]).
ml_var_name_to_string(var_name(Var, no)) = Var.

%-----------------------------------------------------------------------------%
%
% Code for dealing with fields
%

	% Given the user-specified field name, if any,
	% and the argument number (starting from one),
	% generate an MLDS field name.
	%
ml_gen_field_name(MaybeFieldName, ArgNum) = FieldName :-
	%
	% If the programmer specified a field name, we use that,
	% otherwise we just use `F' followed by the field number.
	%
	(
		MaybeFieldName = yes(QualifiedFieldName),
		unqualify_name(QualifiedFieldName, FieldName)
	;
		MaybeFieldName = no,
		FieldName = string__format("F%d", [i(ArgNum)])
	).

	% Succeed iff the specified type must be boxed when used as a field.
	% For the MLDS->C and MLDS->asm back-ends,
	% we need to box types that are not word-sized, because the code
	% for `arg' etc. in std_util.m rely on all arguments being word-sized.
	% XXX Currently we box such types even for the other MLDS based
	% back-ends that don't need it, e.g. the .NET and Java back-ends.
	% This routine should be modified to check the target.
ml_must_box_field_type(Type, ModuleInfo) :-
	classify_type(ModuleInfo, Type) = Category,
	ml_must_box_field_type_category(Category) = yes.

:- func ml_must_box_field_type_category(type_category) = bool.

ml_must_box_field_type_category(int_type) = no.
ml_must_box_field_type_category(char_type) = yes.
ml_must_box_field_type_category(str_type) = no.
ml_must_box_field_type_category(float_type) = yes.
ml_must_box_field_type_category(higher_order_type) = no.
ml_must_box_field_type_category(tuple_type) = no.
ml_must_box_field_type_category(enum_type) = no.
ml_must_box_field_type_category(variable_type) = no.
ml_must_box_field_type_category(type_info_type) = no.
ml_must_box_field_type_category(type_ctor_info_type) = no.
ml_must_box_field_type_category(typeclass_info_type) = no.
ml_must_box_field_type_category(base_typeclass_info_type) = no.
ml_must_box_field_type_category(void_type) = no.
ml_must_box_field_type_category(user_ctor_type) = no.

%-----------------------------------------------------------------------------%
%
% Code for handling success and failure
%

	% Generate code to succeed in the given code_model.
	%
ml_gen_success(model_det, _, Statements, !Info) :-
	%
	% det succeed:
	%	<do true>
	% ===>
	%	/* just fall through */
	%
	Statements = [].
ml_gen_success(model_semi, Context, [SetSuccessTrue], !Info) :-
	%
	% semidet succeed:
	%	<do true>
	% ===>
	%	succeeded = MR_TRUE;
	%
	ml_gen_set_success(!.Info, const(true), Context, SetSuccessTrue).
ml_gen_success(model_non, Context, [CallCont], !Info) :-
	%
	% nondet succeed:
	%	<true && SUCCEED()>
	% ===>
	%	SUCCEED()
	%
	ml_gen_call_current_success_cont(Context, CallCont, !Info).

	% Generate code to fail in the given code_model.
	%
ml_gen_failure(model_det, _, _, !Info) :-
	% this should never happen
	error("ml_code_gen: `fail' has determinism `det'").
ml_gen_failure(model_semi, Context, [SetSuccessFalse], !Info) :-
	%
	% semidet fail:
	%	<do fail>
	% ===>
	%	succeeded = MR_FALSE;
	%
	ml_gen_set_success(!.Info, const(false), Context, SetSuccessFalse).
ml_gen_failure(model_non, _, Statements, !Info) :-
	%
	% nondet fail:
	%	<fail && SUCCEED()>
	% ===>
	%	/* just fall through */
	%
	Statements = [].

%-----------------------------------------------------------------------------%

	% Generate the declaration for the built-in `succeeded' variable.
	%
ml_gen_succeeded_var_decl(Context) =
	ml_gen_mlds_var_decl(var(var_name("succeeded", no)),
		mlds__native_bool_type, no, Context).

	% Return the lval for the `succeeded' flag.
	% (`succeeded' is a boolean variable used to record
	% the success or failure of model_semi procedures.)
ml_success_lval(Info, SucceededLval) :-
	ml_gen_var_lval(Info, var_name("succeeded", no), mlds__native_bool_type,
		SucceededLval).

	% Return an rval which will test the value of the `succeeded' flag.
	% (`succeeded' is a boolean variable used to record
	% the success or failure of model_semi procedures.)
	%
ml_gen_test_success(Info, SucceededRval) :-
	ml_success_lval(Info, SucceededLval),
	SucceededRval = lval(SucceededLval).

	% Generate code to set the `succeeded' flag to the
	% specified truth value.
	%
ml_gen_set_success(Info, Value, Context, Statement) :-
	ml_success_lval(Info, Succeeded),
	Statement = ml_gen_assign(Succeeded, Value, Context).

%-----------------------------------------------------------------------------%

	% Generate the name for the specified `cond_<N>' variable.
	%
:- func ml_gen_cond_var_name(cond_seq) = mlds__var_name.

ml_gen_cond_var_name(CondVar) =
	mlds__var_name(string__append("cond_", string__int_to_string(CondVar)),
		no).

ml_gen_cond_var_decl(CondVar, Context) =
	ml_gen_mlds_var_decl(var(ml_gen_cond_var_name(CondVar)),
		mlds__native_bool_type, no, Context).

ml_cond_var_lval(Info, CondVar, CondVarLval) :-
	ml_gen_var_lval(Info, ml_gen_cond_var_name(CondVar),
		mlds__native_bool_type, CondVarLval).

ml_gen_test_cond_var(Info, CondVar, CondVarRval) :-
	ml_cond_var_lval(Info, CondVar, CondVarLval),
	CondVarRval = lval(CondVarLval).

ml_gen_set_cond_var(Info, CondVar, Value, Context, Statement) :-
	ml_cond_var_lval(Info, CondVar, CondVarLval),
	Statement = ml_gen_assign(CondVarLval, Value, Context).

%-----------------------------------------------------------------------------%

ml_initial_cont(Info, OutputVarLvals0, OutputVarTypes0, Cont) :-
	ml_skip_dummy_argument_types(OutputVarTypes0, OutputVarLvals0,
		OutputVarTypes, OutputVarLvals),
	list__map(ml_gen_type(Info), OutputVarTypes, MLDS_OutputVarTypes),
	%
	% We expect OutputVarlvals0 and OutputVarTypes0 to be empty if
	% `--nondet-copy-out' is not enabled.
	%
	ml_gen_var_lval(Info, mlds__var_name("cont", no),
		mlds__cont_type(MLDS_OutputVarTypes), ContLval),
	ml_gen_var_lval(Info, mlds__var_name("cont_env_ptr", no),
		mlds__generic_env_ptr_type, ContEnvLval),
	Cont = success_cont(lval(ContLval), lval(ContEnvLval),
		MLDS_OutputVarTypes, OutputVarLvals).

:- pred ml_skip_dummy_argument_types(list(prog_type)::in, list(T)::in,
	list(prog_type)::out, list(T)::out) is det.

ml_skip_dummy_argument_types([], [], [], []).
ml_skip_dummy_argument_types([Type | Types0], [Var | Vars0],
		Types, Vars) :-
	ml_skip_dummy_argument_types(Types0, Vars0, Types1, Vars1),
	( type_util__is_dummy_argument_type(Type) ->
		Types = Types1,
		Vars = Vars1
	;
		Types = [Type | Types1],
		Vars = [Var | Vars1]
	).
ml_skip_dummy_argument_types([_|_], [], _, _) :-
	error("ml_skip_dummy_argument_types: length mismatch").
ml_skip_dummy_argument_types([], [_|_], _, _) :-
	error("ml_skip_dummy_argument_types: length mismatch").

	% Generate code to call the current success continuation.
	% This is used for generating success when in a model_non context.
	%
ml_gen_call_current_success_cont(Context, Statement, !Info) :-
	ml_gen_info_current_success_cont(SuccCont, !Info),
	SuccCont = success_cont(FuncRval, EnvPtrRval,
		ArgTypes0, ArgLvals0),
	ArgRvals0 = list__map(func(Lval) = lval(Lval), ArgLvals0),
	ml_gen_info_use_gcc_nested_functions(!.Info, UseNestedFuncs),
	( UseNestedFuncs = yes ->
		ArgTypes = ArgTypes0,
		ArgRvals = ArgRvals0
	;
		ArgTypes = list__append(ArgTypes0,
			[mlds__generic_env_ptr_type]),
		ArgRvals = list__append(ArgRvals0, [EnvPtrRval])
	),
	RetTypes = [],
	Signature = mlds__func_signature(ArgTypes, RetTypes),
	ObjectRval = no,
	RetLvals = [],
	CallKind = ordinary_call,
	Stmt = call(Signature, FuncRval, ObjectRval, ArgRvals, RetLvals,
		CallKind),
	Statement = mlds__statement(Stmt, mlds__make_context(Context)).

	% XXX this code is quite similar to some of the existing code
	% for calling continuations when doing copy-in/copy-out.
	% Sharing code should be investigated.

ml_gen_call_current_success_cont_indirectly(Context, Statement, !Info) :-

		% We generate a call to the success continuation, just
		% as usual.
	ml_gen_info_current_success_cont(SuccCont, !Info),
	SuccCont = success_cont(ContinuationFuncRval, EnvPtrRval,
		ArgTypes0, ArgLvals0),
	ArgRvals0 = list__map(func(Lval) = lval(Lval), ArgLvals0),
	ml_gen_info_use_gcc_nested_functions(!.Info, UseNestedFuncs),
	( UseNestedFuncs = yes ->
		ArgTypes = ArgTypes0,
		ArgRvals = ArgRvals0
	;
		ArgTypes = list__append(ArgTypes0,
			[mlds__generic_env_ptr_type]),
		ArgRvals = list__append(ArgRvals0, [EnvPtrRval])
	),
	RetTypes = [],
	Signature = mlds__func_signature(ArgTypes, RetTypes),
	ObjectRval = no,
	RetLvals = [],
	CallKind = ordinary_call,

	MLDS_Context = mlds__make_context(Context),
	ml_gen_info_get_module_name(!.Info, PredModule),
	MLDS_Module = mercury_module_name_to_mlds(PredModule),

		% We generate a nested function that does the real call
		% to the continuation.
		%
		% All we do is change the call rvals to be the input
		% variables, and the func rval to be the input variable
		% for the continuation.
		%
		% Note that ml_gen_cont_params does not fill in the
		% gc_trace_code for the parameters.  This is OK, because
		% the parameters will not be used again after the call.
		% (Also currently this is only used for IL, for which GC
		% is the .NET CLR implementation's problem, not ours.)
		%
	ml_gen_cont_params(ArgTypes0, InnerFuncParams0, !Info),
	InnerFuncParams0 = func_params(InnerArgs0, Rets),
	InnerArgRvals = list__map(
		(func(mlds__argument(Data, Type, _GC) )
				= lval(var(qual(MLDS_Module, VarName), Type)) :-
			( Data = data(var(VarName0)) ->
				VarName = VarName0
			;
				error("expected variable name " ++
					"in continuation parameters")
			)
		), InnerArgs0),
	InnerFuncArgType = mlds__cont_type(ArgTypes0),
	PassedContVarName = mlds__var_name("passed_cont", no),
	% The passed_cont variable always points to code, not to heap,
	% so the GC never needs to trace it.
	PassedContGCTraceCode = no,
	PassedContArg = mlds__argument(data(var(PassedContVarName)),
		InnerFuncArgType, PassedContGCTraceCode),
	InnerFuncRval = lval(var(qual(MLDS_Module, PassedContVarName),
		InnerFuncArgType)),
	InnerFuncParams = func_params([PassedContArg | InnerArgs0],
			Rets),

	InnerStmt = call(Signature, InnerFuncRval, ObjectRval,
		InnerArgRvals, RetLvals, CallKind),
	InnerStatement = statement(InnerStmt, MLDS_Context),

	ml_gen_label_func(!.Info, 1, InnerFuncParams, Context,
		InnerStatement, Defn),

	ProxySignature = mlds__func_signature([InnerFuncArgType | ArgTypes],
		RetTypes),
	ProxyArgRvals = [ContinuationFuncRval | ArgRvals],
	(
		Defn = mlds__defn(function(PredLabel, ProcId,
			yes(SeqNum), _), _, _, function(_, _,
			defined_here(_), _))
	->
		% We call the proxy function.
		QualProcLabel = qual(MLDS_Module, PredLabel - ProcId),
		ProxyFuncRval = const(code_addr_const(
			internal(QualProcLabel, SeqNum, ProxySignature))),

		% Put it inside a block where we call it.
		Stmt = call(ProxySignature, ProxyFuncRval, ObjectRval,
			ProxyArgRvals, RetLvals, CallKind),
		Statement = mlds__statement(
			block([Defn], [statement(Stmt, MLDS_Context)]),
			MLDS_Context)
	;
		error("success continuation generated was not a function")
	).

%-----------------------------------------------------------------------------%
%
% Routines for dealing with the environment pointer
% used for nested functions.
%

	% Return an rval for a pointer to the current environment
	% (the set of local variables in the containing procedure).
	% Note that we generate this as a dangling reference.
	% The ml_elim_nested pass will insert the declaration
	% of the env_ptr variable.  At this point the type of these rvals
	% is `mlds__unknown_type'.
	%
ml_get_env_ptr(Info, lval(EnvPtrLval)) :-
	ml_gen_var_lval(Info, mlds__var_name("env_ptr", no),
		mlds__unknown_type, EnvPtrLval).

	% Return an rval for a pointer to the current environment
	% (the set of local variables in the containing procedure).
ml_declare_env_ptr_arg(mlds__argument(Name, Type, GC_TraceCode)) :-
	Name = data(var(mlds__var_name("env_ptr_arg", no))),
	Type = mlds__generic_env_ptr_type,
	% The env_ptr_arg always points to the stack,
	% since continuation environments are always allocated
	% on the stack (unless put_nondet_env_on_heap is true,
	% which won't be the case when doing our own GC --
	% this is enforced in handle_options.m).
	% So the GC doesn't need to trace it.
	GC_TraceCode = no.

%-----------------------------------------------------------------------------%
%
% Code to handle accurate GC
%

	% If accurate GC is enabled, and the specified
	% variable might contain pointers, generate code to call
	% `private_builtin__gc_trace' to trace the variable.
	%
ml_gen_maybe_gc_trace_code(VarName, Type, Context, Maybe_GC_TraceCode,
		!Info) :-
	ml_gen_maybe_gc_trace_code(VarName, Type, Type, Context,
		Maybe_GC_TraceCode, !Info).

ml_gen_maybe_gc_trace_code(VarName, DeclType, ActualType, Context,
		Maybe_GC_TraceCode, !Info) :-
	HowToGetTypeInfo = construct_from_type(ActualType),
	ml_gen_maybe_gc_trace_code_2(VarName, DeclType, HowToGetTypeInfo,
		Context, Maybe_GC_TraceCode, !Info).

ml_gen_maybe_gc_trace_code_with_typeinfo(VarName, DeclType, TypeInfoRval,
		Context, Maybe_GC_TraceCode, !Info) :-
	HowToGetTypeInfo = already_provided(TypeInfoRval),
	ml_gen_maybe_gc_trace_code_2(VarName, DeclType, HowToGetTypeInfo,
		Context, Maybe_GC_TraceCode, !Info).

:- type how_to_get_type_info
	--->	construct_from_type(prog_type)
	;	already_provided(mlds__rval).

:- pred ml_gen_maybe_gc_trace_code_2(var_name::in, prog_type::in,
	how_to_get_type_info::in, prog_context::in,
	maybe(mlds__statement)::out,
	ml_gen_info::in, ml_gen_info::out) is det.

ml_gen_maybe_gc_trace_code_2(VarName, DeclType, HowToGetTypeInfo, Context,
		Maybe_GC_TraceCode, !Info) :-
	ml_gen_info_get_module_info(!.Info, ModuleInfo),
	module_info_globals(ModuleInfo, Globals),
	globals__get_gc_method(Globals, GC),
	(
		GC = accurate,
		MLDS_DeclType = mercury_type_to_mlds_type(ModuleInfo,
			DeclType),
		ml_type_might_contain_pointers(MLDS_DeclType) = yes,
		% don't generate GC tracing code in no_type_info_builtins
		ml_gen_info_get_pred_id(!.Info, PredId),
		predicate_id(ModuleInfo, PredId, PredModule, PredName,
			PredArity),
		\+ no_type_info_builtin(PredModule, PredName, PredArity)
	->
		(
			HowToGetTypeInfo = construct_from_type(ActualType0),
			% We need to handle type_info/1 and typeclass_info/1
			% types specially, to avoid infinite recursion here...
			( trace_type_info_type(ActualType0, ActualType1) ->
				ActualType = ActualType1
			;
				ActualType = ActualType0
			),
			ml_gen_gc_trace_code(VarName, DeclType, ActualType,
				Context, GC_TraceCode, !Info)
		;
			HowToGetTypeInfo = already_provided(TypeInfoRval),
			ml_gen_trace_var(!.Info, VarName, DeclType,
				TypeInfoRval, Context, GC_TraceCode)
		),
		Maybe_GC_TraceCode = yes(GC_TraceCode)
	;
		Maybe_GC_TraceCode = no
	).

	% Return `yes' if the type needs to be traced by
	% the accurate garbage collector, i.e. if it might
	% contain pointers.
	%
	% Any type for which we return `yes' here must be word-sized,
	% because we will call private_builtin__gc_trace with its address,
	% and that procedure assumes that its argument is an `MR_Word *'.
	%
	% For floats, we can (and must) return `no' even though they might
	% get boxed in some circumstances, because if they are
	% boxed then they will be represented as mlds__generic_type.
	%
	% Note that with --gcc-nested-functions,
	% cont_type will be a function pointer that
	% may point to a trampoline function,
	% which might in fact contain pointers.
	% But the pointers will only be pointers to
	% code and pointers to the stack, not pointers
	% to the heap, so we don't need to trace them
	% for accurate GC.
	% Hence we can return `no' here for mlds__cont_type.
	%
	% Similarly, the only pointers in type_ctor_infos and
	% base_typeclass_infos are to static code and/or static data,
	% which do not need to be traced.

:- func ml_type_might_contain_pointers(mlds__type) = bool.

ml_type_might_contain_pointers(mercury_type(_Type, TypeCategory, _)) =
	ml_type_category_might_contain_pointers(TypeCategory).
ml_type_might_contain_pointers(mercury_array_type(_)) = yes.
ml_type_might_contain_pointers(mlds__native_int_type) = no.
ml_type_might_contain_pointers(mlds__native_float_type) = no.
ml_type_might_contain_pointers(mlds__native_bool_type) = no.
ml_type_might_contain_pointers(mlds__native_char_type) = no.
ml_type_might_contain_pointers(mlds__foreign_type(_)) = no.
	% We assume that foreign types are not allowed to contain pointers
	% to the Mercury heap.  XXX is this requirement too strict?
ml_type_might_contain_pointers(mlds__class_type(_, _, Category)) =
	(if Category = mlds__enum then no else yes).
ml_type_might_contain_pointers(mlds__ptr_type(_)) = yes.
ml_type_might_contain_pointers(mlds__array_type(_)) = yes.
ml_type_might_contain_pointers(mlds__func_type(_)) = no.
ml_type_might_contain_pointers(mlds__generic_type) = yes.
ml_type_might_contain_pointers(mlds__generic_env_ptr_type) = yes.
ml_type_might_contain_pointers(mlds__type_info_type) = yes.
ml_type_might_contain_pointers(mlds__pseudo_type_info_type) = yes.
ml_type_might_contain_pointers(mlds__cont_type(_)) = no.
ml_type_might_contain_pointers(mlds__commit_type) = no.
ml_type_might_contain_pointers(mlds__rtti_type(_)) = yes.
ml_type_might_contain_pointers(mlds__unknown_type) = yes.

:- func ml_type_category_might_contain_pointers(type_category) = bool.
ml_type_category_might_contain_pointers(int_type) = no.
ml_type_category_might_contain_pointers(char_type) = no.
ml_type_category_might_contain_pointers(str_type) = yes.
ml_type_category_might_contain_pointers(float_type) = no.
ml_type_category_might_contain_pointers(void_type) = no.
ml_type_category_might_contain_pointers(type_info_type) = yes.
ml_type_category_might_contain_pointers(type_ctor_info_type) = no.
ml_type_category_might_contain_pointers(typeclass_info_type) = yes.
ml_type_category_might_contain_pointers(base_typeclass_info_type) = no.
ml_type_category_might_contain_pointers(higher_order_type) = yes.
ml_type_category_might_contain_pointers(tuple_type) = yes.
ml_type_category_might_contain_pointers(enum_type) = no.
ml_type_category_might_contain_pointers(variable_type) = yes.
ml_type_category_might_contain_pointers(user_ctor_type) = yes.

	% trace_type_info_type(Type, RealType):
	%	Succeed iff Type is a type_info-related type
	%	which needs to be copied as if it were some other type,
	%	binding RealType to that other type.
:- pred trace_type_info_type(prog_type::in, prog_type::out) is semidet.

trace_type_info_type(Type, RealType) :-
	sym_name_and_args(Type, TypeName, _),
	TypeName = qualified(PrivateBuiltin, Name),
	mercury_private_builtin_module(PrivateBuiltin),
	( Name = "type_info", RealType = sample_type_info_type
	; Name = "type_ctor_info", RealType = c_pointer_type
	; Name = "typeclass_info", RealType = sample_typeclass_info_type
	; Name = "base_typeclass_info", RealType = c_pointer_type
	).

	% Generate code to call to `private_builtin__gc_trace'
	% to trace the specified variable.
	%
:- pred ml_gen_gc_trace_code(var_name::in, prog_type::in, prog_type::in,
	prog_context::in, mlds__statement::out,
	ml_gen_info::in, ml_gen_info::out) is det.

ml_gen_gc_trace_code(VarName, DeclType, ActualType, Context, GC_TraceCode,
		!Info) :-
	% Build HLDS code to construct the type_info for this type.
	ml_gen_make_type_info_var(ActualType, Context,
		TypeInfoVar, HLDS_TypeInfoGoals, !Info),
	NonLocalsList = list__map(
		(func(_G - GI) = NL :- goal_info_get_nonlocals(GI, NL)),
		HLDS_TypeInfoGoals),
	NonLocals = set__union_list(NonLocalsList),
	instmap_delta_from_assoc_list([TypeInfoVar - ground(shared, none)],
		InstMapDelta),
        goal_info_init(NonLocals, InstMapDelta, det, impure, GoalInfo),
	conj_list_to_goal(HLDS_TypeInfoGoals, GoalInfo, Conj),

	% Convert this HLDS code to MLDS
	ml_gen_goal(model_det, Conj, MLDS_TypeInfoStatement0, !Info),

	% Replace all heap allocation (new_object instructions)
	% with stack allocation (local variable declarations)
	% in the code to construct type_infos.  This is safe
	% because those type_infos will only be used in the
	% immediately following call to gc_trace/1.
	ml_gen_info_get_module_info(!.Info, ModuleInfo),
	module_info_name(ModuleInfo, ModuleName),
	fixup_newobj(MLDS_TypeInfoStatement0,
		mercury_module_name_to_mlds(ModuleName),
		MLDS_TypeInfoStatement, MLDS_NewobjLocals),

	% Build MLDS code to trace the variable
	ml_gen_var(!.Info, TypeInfoVar, TypeInfoLval),
	ml_gen_trace_var(!.Info, VarName, DeclType, lval(TypeInfoLval), Context,
		MLDS_TraceStatement),

	% Generate declarations for any type_info variables used.
	%
	% Note: this will generate local declarations even for
	% type_info variables which are not local to this goal.
	% However, fortunately ml_elim_nested.m will transform
	% the GC code to use the original definitions, which will
	% get put in the GC frame, rather than these declarations,
	% which will get ignored.
	% XXX This is not a very robust way of doing things...
	ml_gen_info_get_varset(!.Info, VarSet),
	ml_gen_info_get_var_types(!.Info, VarTypes),
	MLDS_Context = mlds__make_context(Context),
	GenLocalVarDecl =
		(func(Var) = MLDS_Defn :-
			LocalVarName = ml_gen_var_name(VarSet, Var),
			map__lookup(VarTypes, Var, LocalVarType),
			MLDS_Defn = ml_gen_mlds_var_decl(var(LocalVarName),
				mercury_type_to_mlds_type(ModuleInfo,
					LocalVarType),
				no, MLDS_Context)
		),
	set__to_sorted_list(NonLocals, NonLocalVarList),
	MLDS_NonLocalVarDecls = list__map(GenLocalVarDecl, NonLocalVarList),

	% Combine the MLDS code fragments together.
	GC_TraceCode = ml_gen_block(
		MLDS_NewobjLocals ++ MLDS_NonLocalVarDecls,
		[MLDS_TypeInfoStatement] ++ [MLDS_TraceStatement],
		Context).

	% ml_gen_trace_var(VarName, DeclType, TypeInfo, Context, Code):
	% Generate a call to `private_builtin__gc_trace'
	% for the specified variable, given the variable's name, type,
	% and the already-constructed type_info for that type.
	%
:- pred ml_gen_trace_var(ml_gen_info::in, var_name::in, prog_type::in,
	mlds__rval::in, prog_context::in, mlds__statement::out) is det.

ml_gen_trace_var(Info, VarName, Type, TypeInfoRval, Context, TraceStatement) :-
	%
	% Generate the lval for Var
	%
	ml_gen_info_get_module_info(Info, ModuleInfo),
	MLDS_Type = mercury_type_to_mlds_type(ModuleInfo, Type),
	ml_gen_var_lval(Info, VarName, MLDS_Type, VarLval),
	%
	% Generate the address of `private_builtin__gc_trace/1#0'
	%
	PredName = "gc_trace",
	PredOrigArity = 1,
	Pred = pred((predicate), no, PredName, PredOrigArity, model_det, no),
	ProcId = hlds_pred__initial_proc_id,
	mercury_private_builtin_module(PredModule),
	MLDS_Module = mercury_module_name_to_mlds(PredModule),
	Proc = qual(MLDS_Module, Pred - ProcId),
	CPointerType = mercury_type(c_pointer_type, user_ctor_type,
		non_foreign_type(c_pointer_type)),
	ArgTypes = [mlds__pseudo_type_info_type, CPointerType],
	Signature = mlds__func_signature(ArgTypes, []),
	FuncAddr = const(code_addr_const(proc(Proc, Signature))),
	%
	% Generate the call
	% `private_builtin__gc_trace(TypeInfo, (MR_C_Pointer) &Var);'.
	%
	CastVarAddr = unop(cast(CPointerType), mem_addr(VarLval)),
	TraceStatement = mlds__statement(
		call(Signature, FuncAddr, no,
			[TypeInfoRval, CastVarAddr], [], ordinary_call
		), mlds__make_context(Context)).

	% Generate HLDS code to construct the type_info for this type.
	%
:- pred ml_gen_make_type_info_var(prog_type::in, prog_context::in,
	prog_var::out, hlds_goals::out,
	ml_gen_info::in, ml_gen_info::out) is det.

ml_gen_make_type_info_var(Type, Context, TypeInfoVar, TypeInfoGoals, !Info) :-
	%
	% Extract the relevant information from the ml_gen_info
	%
	ModuleInfo0 = !.Info ^ module_info,
	PredId = !.Info ^ pred_id,
	ProcId = !.Info ^ proc_id,
	module_info_pred_proc_info(ModuleInfo0, PredId, ProcId,
		PredInfo0, ProcInfo0),

	%
	% Call polymorphism.m to generate the HLDS code to
	% create the type_infos.
	%
	create_poly_info(ModuleInfo0, PredInfo0, ProcInfo0, PolyInfo0),
	polymorphism__make_type_info_var(Type, Context,
		TypeInfoVar, TypeInfoGoals, PolyInfo0, PolyInfo),
	poly_info_extract(PolyInfo, PredInfo0, PredInfo,
		ProcInfo0, ProcInfo, ModuleInfo1),

	%
	% Save the new information back in the ml_gen_info
	%
	module_info_set_pred_proc_info(PredId, ProcId, PredInfo, ProcInfo,
		ModuleInfo1, ModuleInfo),
	proc_info_varset(ProcInfo, VarSet),
	proc_info_vartypes(ProcInfo, VarTypes),
	!:Info = (((!.Info ^ module_info := ModuleInfo)
		^ varset := VarSet)
		^ var_types := VarTypes).

%-----------------------------------------------------------------------------%

:- type fixup_newobj_info
	---> fixup_newobj_info(
		module_name	:: mlds_module_name,
					% the current module
		context		:: mlds__context,
					% the current context
		locals		:: mlds__defns,
					% the local variable declarations
					% accumulated so far
		next_id		:: counter
					% a counter used to allocate
					% variable names
	).

	% Replace all heap allocation (new_object instructions)
	% with stack allocation (local variable declarations)
	% in the specified statement, returning the local
	% variable declarations needed for the stack allocation.
	%
:- pred fixup_newobj(mlds__statement::in, mlds_module_name::in,
	 mlds__statement::out, mlds__defns::out) is det.

fixup_newobj(Statement0, ModuleName, Statement, Defns) :-
	Statement0 = mlds__statement(Stmt0, Context),
	Info0 = fixup_newobj_info(ModuleName, Context, [], counter__init(0)),
	fixup_newobj_in_stmt(Stmt0, Stmt, Info0, Info),
	Statement = mlds__statement(Stmt, Context),
	Defns = Info ^ locals.

:- pred fixup_newobj_in_statement(mlds__statement::in, mlds__statement::out,
	fixup_newobj_info::in, fixup_newobj_info::out) is det.

fixup_newobj_in_statement(Statement0, Statement, !Info) :-
	Statement0 = mlds__statement(Stmt0, Context),
	!:Info = !.Info ^ context := Context,
	fixup_newobj_in_stmt(Stmt0, Stmt, !Info),
	Statement = mlds__statement(Stmt, Context).

:- pred fixup_newobj_in_stmt(mlds__stmt::in, mlds__stmt::out,
	fixup_newobj_info::in, fixup_newobj_info::out) is det.

fixup_newobj_in_stmt(Stmt0, Stmt, !Fixup) :-
	(
		Stmt0 = block(Defns, Statements0),
		list__map_foldl(fixup_newobj_in_statement,
			Statements0, Statements, !Fixup),
		Stmt = block(Defns, Statements)
	;
		Stmt0 = while(Rval, Statement0, Once),
		fixup_newobj_in_statement(Statement0, Statement, !Fixup),
		Stmt = while(Rval, Statement, Once)
	;
		Stmt0 = if_then_else(Cond, Then0, MaybeElse0),
		fixup_newobj_in_statement(Then0, Then, !Fixup),
		fixup_newobj_in_maybe_statement(MaybeElse0, MaybeElse, !Fixup),
		Stmt = if_then_else(Cond, Then, MaybeElse)
	;
		Stmt0 = switch(Type, Val, Range, Cases0, Default0),
		list__map_foldl(fixup_newobj_in_case, Cases0, Cases, !Fixup),
		fixup_newobj_in_default(Default0, Default, !Fixup),
		Stmt = switch(Type, Val, Range, Cases, Default)
	;
		Stmt0 = label(_),
		Stmt = Stmt0
	;
		Stmt0 = goto(_),
		Stmt = Stmt0
	;
		Stmt0 = computed_goto(Rval, Labels),
		Stmt = computed_goto(Rval, Labels)
	;
		Stmt0 = call(_Sig, _Func, _Obj, _Args, _RetLvals,
			_TailCall),
		Stmt = Stmt0
	;
		Stmt0 = return(_Rvals),
		Stmt = Stmt0
	;
		Stmt0 = do_commit(_Ref),
		Stmt = Stmt0
	;
		Stmt0 = try_commit(Ref, Statement0, Handler0),
		fixup_newobj_in_statement(Statement0, Statement, !Fixup),
		fixup_newobj_in_statement(Handler0, Handler, !Fixup),
		Stmt = try_commit(Ref, Statement, Handler)
	;
		Stmt0 = atomic(AtomicStmt0),
		fixup_newobj_in_atomic_statement(AtomicStmt0, Stmt, !Fixup)
	).

:- pred fixup_newobj_in_case(mlds__switch_case::in, mlds__switch_case::out,
	fixup_newobj_info::in, fixup_newobj_info::out) is det.

fixup_newobj_in_case(Conds - Statement0, Conds - Statement, !Fixup) :-
	fixup_newobj_in_statement(Statement0, Statement, !Fixup).

:- pred fixup_newobj_in_maybe_statement(maybe(mlds__statement)::in,
	maybe(mlds__statement)::out,
	fixup_newobj_info::in, fixup_newobj_info::out) is det.

fixup_newobj_in_maybe_statement(no, no, !Fixup).
fixup_newobj_in_maybe_statement(yes(Statement0), yes(Statement), !Fixup) :-
	fixup_newobj_in_statement(Statement0, Statement, !Fixup).

:- pred fixup_newobj_in_default(mlds__switch_default::in,
	mlds__switch_default::out,
	fixup_newobj_info::in, fixup_newobj_info::out) is det.

fixup_newobj_in_default(default_is_unreachable, default_is_unreachable,
		!Fixup).
fixup_newobj_in_default(default_do_nothing, default_do_nothing, !Fixup).
fixup_newobj_in_default(default_case(Statement0), default_case(Statement),
		!Fixup) :-
	fixup_newobj_in_statement(Statement0, Statement, !Fixup).

:- pred fixup_newobj_in_atomic_statement(mlds__atomic_statement::in,
	mlds__stmt::out, fixup_newobj_info::in, fixup_newobj_info::out) is det.

fixup_newobj_in_atomic_statement(AtomicStatement0, Stmt, !Fixup) :-
	(
		AtomicStatement0 = new_object(Lval, MaybeTag, _HasSecTag,
			PointerType, _MaybeSizeInWordsRval, _MaybeCtorName,
			ArgRvals, _ArgTypes)
	->
		%
		% generate the declaration of the new local variable
		%
		% XXX Using array(generic_type) is wrong for
		% --high-level-data.
		%
		% We need to specify an initializer to tell the
		% C back-end what the length of the array is.
		% We initialize it with null pointers and then
		% later generate assignment statements to fill
		% in the values properly (see below).
		%
		counter__allocate(Id, !.Fixup ^ next_id, NextId),
		VarName = var_name("new_obj", yes(Id)),
		VarType = mlds__array_type(mlds__generic_type),
		NullPointers = list__duplicate(list__length(ArgRvals),
			init_obj(const(mlds__null(mlds__generic_type)))),
		Initializer = init_array(NullPointers),
		% this is used for the type_infos allocated during tracing,
		% and we don't need to trace them
		MaybeGCTraceCode = no,
		Context = !.Fixup ^ context,
		VarDecl = ml_gen_mlds_var_decl(var(VarName),
			VarType, Initializer, MaybeGCTraceCode, Context),
		!:Fixup = !.Fixup ^ next_id := NextId,
		!:Fixup= !.Fixup ^ locals := !.Fixup ^ locals ++ [VarDecl],
		%
		% Generate code to initialize the variable.
		%
		% Note that we need to use assignment statements,
		% rather than an initializer, to initialize the
		% local variable, because the initialization code
		% needs to occur at exactly the point where the
		% atomic_statement occurs, rather than at the
		% local variable declaration.
		%
		VarLval = mlds__var(qual(!.Fixup ^ module_name, VarName),
			VarType),
		PtrRval = mlds__unop(cast(PointerType), mem_addr(VarLval)),
		list__map_foldl(
			init_field_n(PointerType, PtrRval, Context),
			ArgRvals, ArgInitStatements, 0, _NumFields),
		%
		% generate code to assign the address of the new local
		% variable to the Lval
		%
		TaggedPtrRval = maybe_tag_rval(MaybeTag, PointerType, PtrRval),
		AssignStmt = atomic(assign(Lval, TaggedPtrRval)),
		AssignStatement = mlds__statement(AssignStmt, Context),
		Stmt = block([], ArgInitStatements ++ [AssignStatement])
	;
		Stmt = atomic(AtomicStatement0)
	).

:- pred init_field_n(mlds__type::in, mlds__rval::in,
	mlds__context::in, mlds__rval::in, mlds__statement::out,
	int::in, int::out) is det.

init_field_n(PointerType, PointerRval, Context, ArgRval, Statement,
		FieldNum, FieldNum + 1) :-
	FieldId = offset(const(int_const(FieldNum))),
	% XXX FieldType is wrong for --high-level-data
	FieldType = mlds__generic_type,
	MaybeTag = yes(0),
	Field = field(MaybeTag, PointerRval, FieldId, FieldType, PointerType),
	AssignStmt = atomic(assign(Field, ArgRval)),
	Statement = mlds__statement(AssignStmt, Context).

:- func maybe_tag_rval(maybe(mlds__tag), mlds__type, mlds__rval) = mlds__rval.

maybe_tag_rval(no, _Type, Rval) = Rval.
maybe_tag_rval(yes(Tag), Type, Rval) = unop(cast(Type), mkword(Tag, Rval)).

%-----------------------------------------------------------------------------%
%
% The definition of the `ml_gen_info' ADT.
%

%
% The `ml_gen_info' type holds information used during MLDS code generation
% for a given procedure.
%
% Only the `func_label', `commit_label', `cond_var', `conv_var', `const_num',
% `var_lvals', `success_cont_stack', and `extra_defns' fields are mutable;
% the others are set when the `ml_gen_info' is created and then never
% modified.
%

:- type ml_gen_info
	--->	ml_gen_info(
			%
			% these fields remain constant for each procedure
			%
			% (unless accurate GC is enabled, in which case the
			% varset and var_types may get updated if we create
			% fresh variables for type_info variables needed
			% for calls to private_builtin__gc_trace)
			%

			module_info	:: module_info,
			pred_id		:: pred_id,
			proc_id		:: proc_id,
			varset		:: prog_varset,
			var_types	:: map(prog_var, prog_type),
			byref_output_vars :: list(prog_var),
					% output arguments that are passed by
					% reference
			value_output_vars :: list(prog_var),
					% output arguments that are returned
					% as values

			%
			% these fields get updated as we traverse
			% each procedure
			%

				% XXX we should use the standard library
				% `counter' type here
			func_label	:: mlds__func_sequence_num,
			commit_label	:: commit_sequence_num,
			label		:: label_num,
			cond_var	:: cond_seq,
			conv_var	:: conv_seq,
			const_num	:: const_seq,
			const_num_map	:: map(prog_var, const_seq),
			success_cont_stack :: stack(success_cont),
					% a partial mapping from vars to lvals,
					% used to override the normal lval
					% that we use for a variable
			var_lvals	:: map(prog_var, mlds__lval),
					% definitions of functions or global
					% constants which should be inserted
					% before the definition of the function
					% for the current procedure
			extra_defns	:: mlds__defns
		).

ml_gen_info_init(ModuleInfo, PredId, ProcId) = Info :-
	module_info_pred_proc_info(ModuleInfo, PredId, ProcId,
			_PredInfo, ProcInfo),
	proc_info_headvars(ProcInfo, HeadVars),
	proc_info_varset(ProcInfo, VarSet),
	proc_info_vartypes(ProcInfo, VarTypes),
	proc_info_argmodes(ProcInfo, HeadModes),
	ByRefOutputVars = select_output_vars(ModuleInfo, HeadVars, HeadModes,
		VarTypes),
	ValueOutputVars = [],

	LabelCounter = 0,
	FuncLabelCounter = 0,
	CommitLabelCounter = 0,
	CondVarCounter = 0,
	ConvVarCounter = 0,
	ConstCounter = 0,
	map__init(ConstNumMap),
	stack__init(SuccContStack),
	map__init(VarLvals),
	ExtraDefns = [],

	Info = ml_gen_info(
			ModuleInfo,
			PredId,
			ProcId,
			VarSet,
			VarTypes,
			ByRefOutputVars,
			ValueOutputVars,
			LabelCounter,
			FuncLabelCounter,
			CommitLabelCounter,
			CondVarCounter,
			ConvVarCounter,
			ConstCounter,
			ConstNumMap,
			SuccContStack,
			VarLvals,
			ExtraDefns
		).

ml_gen_info_get_module_info(Info, Info ^ module_info).

ml_gen_info_get_module_name(Info, ModuleName) :-
	ml_gen_info_get_module_info(Info, ModuleInfo),
	module_info_name(ModuleInfo, ModuleName).

ml_gen_info_get_pred_id(Info, Info ^ pred_id).
ml_gen_info_get_proc_id(Info, Info ^ proc_id).
ml_gen_info_get_varset(Info, Info ^ varset).
ml_gen_info_get_var_types(Info, Info ^ var_types).
ml_gen_info_get_byref_output_vars(Info, Info ^ byref_output_vars).
ml_gen_info_get_value_output_vars(Info, Info ^ value_output_vars).
ml_gen_info_set_byref_output_vars(OutputVars, Info,
		Info ^ byref_output_vars := OutputVars).
ml_gen_info_set_value_output_vars(OutputVars, Info,
		Info ^ value_output_vars := OutputVars).

ml_gen_info_use_gcc_nested_functions(Info, UseNestedFuncs) :-
	ml_gen_info_get_globals(Info, Globals),
	globals__lookup_bool_option(Globals, gcc_nested_functions,
		UseNestedFuncs).

ml_gen_info_put_commit_in_own_func(Info, PutCommitInNestedFunc) :-
	ml_gen_info_get_globals(Info, Globals),
	globals__lookup_bool_option(Globals, put_commit_in_own_func,
		PutCommitInNestedFunc).

ml_gen_info_get_globals(Info, Globals) :-
	ml_gen_info_get_module_info(Info, ModuleInfo),
	module_info_globals(ModuleInfo, Globals).

ml_gen_info_new_label(Label, Info, Info ^ label := Label) :-
	Label = Info ^ label + 1.

ml_gen_info_new_func_label(Label, Info, Info ^ func_label := Label) :-
	Label = Info ^ func_label + 1.

ml_gen_info_bump_counters(Info,
	(Info ^ func_label := Info ^ func_label + 10000)
	      ^ const_num := Info ^ const_num + 10000).

ml_gen_info_new_commit_label(CommitLabel, Info,
		Info ^ commit_label := CommitLabel) :-
	CommitLabel = Info ^ commit_label + 1.

ml_gen_info_new_cond_var(CondVar, Info, Info ^ cond_var := CondVar) :-
	CondVar = Info ^ cond_var + 1.

ml_gen_info_new_conv_var(ConvVar, Info, Info ^ conv_var := ConvVar) :-
	ConvVar = Info ^ conv_var + 1.

ml_gen_info_new_const(ConstVar, Info, Info ^ const_num := ConstVar) :-
	ConstVar = Info ^ const_num + 1.

ml_gen_info_set_const_num(Var, ConstVar, Info,
	Info ^ const_num_map := map__set(Info ^ const_num_map, Var, ConstVar)).

ml_gen_info_lookup_const_num(Info, Var, ConstVar) :-
	ConstVar = map__lookup(Info ^ const_num_map, Var).

ml_gen_info_push_success_cont(SuccCont, Info,
	Info ^ success_cont_stack :=
		stack__push(Info ^ success_cont_stack, SuccCont)).

ml_gen_info_pop_success_cont(Info0, Info) :-
	Stack0 = Info0 ^ success_cont_stack,
	stack__pop_det(Stack0, _SuccCont, Stack),
	Info = (Info0 ^ success_cont_stack := Stack).

ml_gen_info_current_success_cont(SuccCont, Info, Info) :-
	stack__top_det(Info ^ success_cont_stack, SuccCont).

ml_gen_info_set_var_lval(Var, Lval, Info,
		Info ^ var_lvals := map__set(Info ^ var_lvals, Var, Lval)).

ml_gen_info_get_var_lvals(Info, Info ^ var_lvals).
ml_gen_info_set_var_lvals(VarLvals, Info, Info ^ var_lvals := VarLvals).

ml_gen_info_add_extra_defn(ExtraDefn, Info,
	Info ^ extra_defns := [ExtraDefn | Info ^ extra_defns]).

ml_gen_info_get_extra_defns(Info, Info ^ extra_defns).

%-----------------------------------------------------------------------------%

	% Given a list of variables and their corresponding modes,
	% return a list containing only those variables which have
	% an output mode.
	%
select_output_vars(ModuleInfo, HeadVars, HeadModes, VarTypes) = OutputVars :-
	( HeadVars = [], HeadModes = [] ->
		OutputVars = []
	; HeadVars = [Var|Vars], HeadModes = [Mode|Modes] ->
		map__lookup(VarTypes, Var, VarType),
		(
			mode_to_arg_mode(ModuleInfo, Mode, VarType, top_out)
		->
			OutputVars1 = select_output_vars(ModuleInfo,
					Vars, Modes, VarTypes),
			OutputVars = [Var | OutputVars1]
		;
			OutputVars = select_output_vars(ModuleInfo,
					Vars, Modes, VarTypes)
		)
	;
		error("select_output_vars: length mismatch")
	).

%-----------------------------------------------------------------------------%

	% This function returns the offset to add to the argument
	% number of a closure arg to get its field number.
	%	field 0 is the closure layout
	%	field 1 is the closure address
	%	field 2 is the number of arguments
	%	field 3 is the 1st argument field
	%	field 4 is the 2nd argument field,
	%	etc.
	% Hence the offset to add to the argument number
	% to get the field number is 2.
ml_closure_arg_offset = 2.

	% This function returns the offset to add to the argument
	% number of a typeclass_info arg to get its field number.
	% The Nth extra argument to pass to the method is
	% in field N of the typeclass_info, so the offset is zero.
ml_typeclass_info_arg_offset = 0.

	% This function returns the offset to add to the method number
	% for a type class method to get its field number within the
	% base_typeclass_info.
	%	field 0 is num_extra
	%	field 1 is num_constraints
	%	field 2 is num_superclasses
	%	field 3 is class_arity
	%	field 4 is num_methods
	%	field 5 is the 1st method
	%	field 6 is the 2nd method
	%	etc.
	%	(See the base_typeclass_info type in rtti.m or the
	%	description in notes/type_class_transformation.html for
	%	more information about the layout of base_typeclass_infos.)
	% Hence the offset is 4.
ml_base_typeclass_info_method_offset = 4.

%-----------------------------------------------------------------------------%
%
% Miscellaneous routines
%

	% Get the value of the appropriate --det-copy-out or --nondet-copy-out
	% option, depending on the code model.
get_copy_out_option(Globals, CodeModel) = CopyOut :-
	( CodeModel = model_non ->
		globals__lookup_bool_option(Globals,
			nondet_copy_out, CopyOut)
	;
		globals__lookup_bool_option(Globals,
			det_copy_out, CopyOut)
	).

	% Add the qualifier `builtin' to any unqualified name.
fixup_builtin_module(ModuleName0) = ModuleName :-
	( ModuleName0 = unqualified("") ->
		mercury_public_builtin_module(ModuleName)
	;
		ModuleName = ModuleName0
	).

%-----------------------------------------------------------------------------%

:- func this_file = string.
this_file = "ml_code_util.m".

:- end_module ml_code_util.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
