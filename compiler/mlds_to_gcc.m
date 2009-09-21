%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1999-2009 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% mlds_to_gcc - Convert MLDS to the GCC back-end representation.
% Main author: fjh.
%
% Note that this does *not* compile to GNU C -- instead it
% actually generates GCC's internal "Tree" representation,
% and then invokes the GCC back-end to compile it to assembler,
% without going via an external file.
%
% Code using the C interface, however, does get compiled to C; this module
% invokes mlds_to_c.m to do that.  We split off all the parts of the MLDS
% for `c_code'/`foreign_code' declarations, `c_header_code'/`foreign_decl'
% declarations, `export' declarations, and procedures defined with
% `c_code'/`foreign_proc', and pass them to mlds_to_c.m.  That will generate
% a `<module>.c' file for this module; mercury_compile.m will invoke the C
% compiler to compile that to `<module>__c_code.o'.  The remainding parts
% of the MLDS, which don't contain any foreign code, we handle normally,
% converting them to GCC trees and passing them to the GCC back-end
% to generate an assembler file.  Calls to procedures defined using
% `c_code'/`foreign_proc' will end up calling the functions defined in
% `<module>__c_code.o'.  This works because the calling convention that
% is used for the MLDS->C back-end is the same as (i.e. binary compatible
% with) the calling convention that we use here in the MLDS->GCC back-end.
%
% Currently this back-end supports grade hlc.gc only.
%
% Trailing will probably work too, but since trailing
% is currently implemented using the C interface,
% it will end up compiling everything via C.
%
% See also gcc/mercury/README.
%
% TODO:
%   Fix configuration issues:
%   - document installation procedure better
%     (there is some documentation in gcc/mercury/README,
%     but probably there should also be something in the INSTALL
%     file in the Mercury distribution)
%   - test more
%
%   Fix unimplemented standard Mercury features:
%   - Mmake support for nested modules
%   - support modules containing foreign_decls but no
%     foreign_procs or foreign code
%
%   Implement implementation-specific features that are supported
%   by other Mercury back-ends:
%   - support --high-level-data (enum types, pred types, user_type)
%   - support --profiling and --heap-profiling
%   - support --nondet-copy-out
%   - support --gcc-nested-functions (probably not worth it)
%   - pragma foreign_code(asm, ...)
%
%   Implement implementation-specific features that are supported
%   by other gcc front-ends:
%   - generate gcc trees rather than expanding as we go
%       This should probably wait until the GCC back-end
%       has a language-independent representation for switches.
%   - support gdb (hard!):
%       - improve accuracy of line numbers (e.g. for decls).
%       - make variable names match what's in the original source
%       - use nested functions or something like that to hide
%         from the user the environment struct stuff that we
%         generate for nondet code
%       - teach gdb to demangle Mercury symbol names
%       - extend gdb to print Mercury data structures better
%       - extend gdb to print Mercury stacks better
%       - extend gdb to support mdb's `retry' command
%       ...
%
%   Improve efficiency of generated code:
%   - implement annotation in gcc tree to force tailcalls
%   - improve code for switches with default_is_unreachable.
%     (We already do a reasonably good job, so this is a low priority.)
%     One way would be to implement computed_goto and unsigned_le,
%     and change target_supports_computed_goto_2(asm) in ml_switch_gen.m
%     to `yes'.
%
%   Improve efficiency of compilation:
%   - improve symbol table handling
%
%   See also the TODO list in ml_code_gen.m.
%
%-----------------------------------------------------------------------------%

:- module mlds_to_gcc.
:- interface.

:- import_module ml_backend.
:- import_module ml_backend.maybe_mlds_to_gcc.
:- import_module ml_backend.mlds.

:- import_module bool.
:- use_module io.

%-----------------------------------------------------------------------------%

    % run_gcc_backend(ModuleName, CallBack, CallBackOutput):
    %
    % Set things up to generate an assembler file whose name
    % is based on the specified module name, and then call the
    % CallBack procedure.  When the CallBack procedure exits
    % (returning CallBackOutput), finish generating the assembler
    % file, and then return the CallBackOutput back to the caller.
    %
    % Due to limitations in the GCC back-end, this procedure
    % must not be called more than once per process.

:- pred mlds_to_gcc__run_gcc_backend(mercury_module_name::in,
    frontend_callback(T)::in(frontend_callback), T::out,
    io.state::di, io.state::uo) is det.

    % compile_to_gcc(MLDS, ContainsCCode):
    %
    % Generate GCC trees and/or RTL for the given MLDS,
    % and invoke the GCC back-end to output assembler for
    % them to the assembler file.
    %
    % This procedure must only be called from within a callback
    % function passed to run_gcc_backend.  Otherwise it may
    % try to use the GCC back-end before it has been properly
    % initialized.
    %
    % The ContainsCCode bool returned is `yes' iff the module contained
    % C code. In that case, we will have output a separate C file which
    % needs to be compiled with the C compiler.
    %
    % XXX Currently the only foreign language we handle is C.
    %     To make it work properly we'd need to change the
    %     `ContainsCCode' boolean that we return to instead be a list
    %     of the foreign languages used, so that mercury_compile.m
    %     will know which foreign language files have been generated
    %     which foreign language compilers it needs to invoke,
    %     and which object files to link into the executable.

:- pred mlds_to_gcc__compile_to_asm(mlds__mlds::in, bool::out,
    io.state::di, io.state::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- use_module gcc.

:- import_module backend_libs.
:- import_module hlds.
:- import_module libs.
:- import_module parse_tree.

:- import_module backend_libs.builtin_ops.
:- import_module backend_libs.rtti. % for rtti.addr_to_string.
:- import_module hlds.code_model.
:- import_module hlds.hlds_pred.    % for proc_id_to_int and invalid_pred_id
:- import_module libs.file_util.
:- import_module libs.compiler_util.
:- import_module libs.globals.
:- import_module libs.options.
:- import_module mdbcomp.prim_data.
:- import_module ml_backend.ml_code_util.
    % For ml_gen_public_field_decl_flags, which is used by the code
    % that handles derived classes.
:- import_module ml_backend.ml_global_data.
:- import_module ml_backend.ml_util.
:- import_module ml_backend.mlds_to_c.  % to handle C foreign_code
:- import_module parse_tree.file_names.
:- import_module parse_tree.modules.
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_foreign.
:- import_module parse_tree.prog_type.

:- import_module int.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module set.
:- import_module solutions.
:- import_module string.
:- import_module term.

%-----------------------------------------------------------------------------%

mlds_to_gcc__run_gcc_backend(ModuleName, CallBack, CallBackOutput) -->
    globals__io_lookup_bool_option(pic, Pic),
    { Pic = yes ->
        PicExt = ".pic_s",
        PicOpt = "-fpic "
    ;
        PicExt = ".s",
        PicOpt = ""
    },
    module_name_to_file_name(ModuleName, ".m", do_not_create_dirs,
        SourceFileName),
    module_name_to_file_name(ModuleName, PicExt, do_create_dirs,
        AsmFileName),
    % XXX should use new gcc_* options rather than
    % reusing cflags, c_optimize
    globals__io_lookup_bool_option(statistics, Statistics),
    { Statistics = yes ->
        QuietOption = ""
    ;
        QuietOption = "-quiet "
    },
    globals__io_lookup_bool_option(c_optimize, C_optimize),
    { C_optimize = yes ->
        OptimizeOpt = "-O2 -fomit-frame-pointer "
    ;
        OptimizeOpt = ""
    },
    globals__io_lookup_bool_option(target_debug, Target_Debug),
    { Target_Debug = yes ->
        Target_DebugOpt = "-g "
    ;
        Target_DebugOpt = ""
    },
    globals__io_lookup_accumulating_option(cflags, C_Flags_List),
    { CFLAGS = string__append_list(list__map(func(Flag) = Flag ++ " ",
        C_Flags_List)) },
    % Be careful with the order here.
    % Also be careful that each option is separated by spaces.
    { string__append_list(["""<GCC back-end>"" ", PicOpt,
        QuietOption, OptimizeOpt, Target_DebugOpt, CFLAGS,
        SourceFileName, " -o ", AsmFileName], CommandLine) },
    globals__io_lookup_bool_option(verbose, Verbose),
    maybe_write_string(Verbose, "% Invoking GCC back-end as `"),
    maybe_write_string(Verbose, CommandLine),
    maybe_write_string(Verbose, "':\n"),
    maybe_flush_output(Verbose),
    gcc__run_backend(CommandLine, Result, CallBack, CallBackOutput),
    ( { Result \= 0 } ->
        report_error("GCC back-end failed!\n")
    ;
        maybe_write_string(Verbose, "% GCC back-end done.\n")
    ).

mlds_to_gcc__compile_to_asm(MLDS, ContainsCCode) -->
    % XXX We need to handle initialise declarations properly here.
    % XXX zs: I am not sure whether the handling of _GlobalData is right.
    { MLDS = mlds(ModuleName, AllForeignCode, Imports, _GlobalData, Defns0,
        InitPreds, FinalPreds, ExportedEnums) },

    % Handle output of any foreign code (C, Ada, Fortran, etc.)
    % to appropriate files.

    { list__filter(defn_contains_foreign_code(ml_target_asm), Defns0,
        ForeignDefns, Defns) },
        % We only handle C currently, so we just look up C
    { ForeignCode = map__lookup(AllForeignCode, lang_c) },
    globals.io_get_globals(Globals),
    (
        % Check if there is any C code from pragma foreign_code,
        % pragma export, or pragma foreign_proc declarations.
        % We only want to generate a `.c' file if there is C foreign
        % code.
        %
        % We don't generate a `.c' file if the
        % module contains only `pragma foreign_decls' . This
        % is needed to avoid generating a `.c' file when intermodule
        % optimization is enabled and `pragma foreign_decls'
        % declarations have been read in from the `.opt' files
        % and have propagated through to the MLDS.
        % Creating a C file when the module itself doesn't contain
        % C code breaks things, since Mmake won't compile and link
        % in the generated `.c' files, but those files contain the
        % definition of the `*__init_type_tables()' functions that
        % are referenced by `*_init.c'.
        %
        % XXX This is not quite right, since if the module itself
        % contains `pragma foreign_decls', the `.c' file might
        % be needed.  But the Mercury standard library needs
        % intermodule optimization enabled for `make install'
        % to work.  A better fix would be to ignore foreign_decls
        % that were defined in other modules, but to create the `.c'
        % file if there are foreign_decls that were defined in the
        % module that we're compiling.
        { ForeignCode = mlds_foreign_code(_Decls, _Imports, [], []) },
        { ForeignDefns = [] }
    ->
        { ContainsCCode = no },
        { NeedInitFn = yes }
    ;
        % XXX currently the only foreign code we handle is C;
        %     see comments above (at the declaration for
        %     mlds_to_c__compile_to_asm)
        { ContainsCCode = yes },
        { NeedInitFn = no },
        % create a new MLDS containing just the foreign code
        % (with all definitions made public, so we can use
        % them from the asm file!) and pass that to mlds_to_c.m
        % to create the .mih file, and if necessary the .c file.
        { ForeignMLDS = mlds(ModuleName, AllForeignCode, Imports,
            ml_global_data_init(do_not_use_common_cells),
            list__map(make_public, ForeignDefns),
            InitPreds, FinalPreds, ExportedEnums) },
        mlds_to_c__output_c_file(ForeignMLDS, Globals, "")
    ),
    %
    % Generate the .mih C header file for this module.
    % We do this regardless of whether the module contains C code,
    % because this is needed to allow interoperability between modules
    % compiled with --target asm and --target c.
    %
    mlds_to_c__output_c_header_file(MLDS, Globals, ""),

    %
    % We generate things in this order:
    %   #1. definitions of the types,
    %   #2. definitions of all the non-types
    %   #3. initialization functions
    % #1 needs to come before #2 since we need the types to be
    % complete before we generate local variables of that type.
    % (This happens for the environment structs that we
    % use for nested functions.)
    %
    % Declarations of functions and types referred to by this
    % module are generated on-demand.
    %
    { list__filter(defn_is_type, Defns, TypeDefns, NonTypeDefns) },
    { MLDS_ModuleName = mercury_module_name_to_mlds(ModuleName) },
    { GlobalInfo0 = global_info(map__init, map__init) },
    gen_defns(MLDS_ModuleName, TypeDefns, GlobalInfo0, GlobalInfo1),
    gen_defns(MLDS_ModuleName, NonTypeDefns, GlobalInfo1, GlobalInfo2),

    % XXX currently we just generate an empty initialization function.
    % Initialization functions are only needed for --profiling
    % and --heap-profiling, which we don't support yet.
    ( { NeedInitFn = yes } ->
        gen_init_fn_defns(MLDS_ModuleName, GlobalInfo2, _GlobalInfo)
    ;
        []
    ).
/****
not yet:
    { list__filter(defn_is_function, NonTypeDefns, FuncDefns) },
    { list__filter(defn_is_type_ctor_info, NonTypeDefns,
        TypeCtorInfoDefns) },
    mlds_output_init_fn_defns(MLDS_ModuleName, FuncDefns,
        TypeCtorInfoDefns), io__nl,
*****/

    % XXX we ought to output a reference to the mangled grade name,
    % to prevent linking with the wrong grade.
    % But this would require duplicating the logic in
    % runtime/mercury_grade.h.  Some of it is already duplicated
    % in
    % of the code in
/******
not yet:
    % mlds_output_grade_var, io__nl.
******/


/******
not yet implemented for mlds_to_gcc:
    %
    % Output a reference to the mangled grade name for the grade
    % that the C file gets compiled with.  This ensures that
    % we don't try to link objects files compiled in different
    % grades.
    %
:- pred mlds_output_grade_var(io__state::di, io__state::uo) is det.
mlds_output_grade_var -->
    io__write_string(
        "// ensure everything is compiled with the same grade\n"),
    io__write_string(
        "static const void *const MR_grade = &MR_GRADE_VAR;\n").
******/

:- func make_public(mlds_defn) = mlds_defn.
make_public(mlds_defn(Name, Context, Flags0, Defn)) =
        mlds_defn(Name, Context, Flags, Defn) :-
    Flags = mlds__set_access(Flags0, acc_public).

%-----------------------------------------------------------------------------%

:- pred gen_init_fn_defns(mlds_module_name::in,
        global_info::in, global_info::out,
        io__state::di, io__state::uo) is det.

gen_init_fn_defns(MLDS_ModuleName, GlobalInfo0, GlobalInfo) -->
    %
    % Generate an empty function of the form
    %
    %   void <foo>_init_type_tables() {}
    %
    { GlobalInfo = GlobalInfo0 },
    { FuncName = init_fn_name(MLDS_ModuleName, "_type_tables") },
    { GCC_ParamTypes = gcc__empty_param_types },
    { GCC_ParamDecls = gcc__empty_param_decls },
    { GCC_RetType = gcc__void_type_node },
    gcc__build_function_decl(FuncName, FuncName,
        GCC_RetType, GCC_ParamTypes, GCC_ParamDecls, GCC_FuncDecl),
    { Name = entity_export(FuncName) },
    { map__init(SymbolTable) },
    { map__init(LabelTable) },
    { DefnInfo = defn_info(GlobalInfo,
        qual(MLDS_ModuleName, module_qual, Name),
        SymbolTable, LabelTable) },
    { term__context_init(Context) },
    { FuncBody = statement(ml_stmt_block([], []),
        mlds_make_context(Context)) },
    gcc__start_function(GCC_FuncDecl),
    gen_statement(DefnInfo, FuncBody),
    gcc__end_function.

:- func init_fn_name(mlds_module_name, string) = string.

init_fn_name(ModuleName, Suffix) = InitFnName :-
        % Here we ensure that we only get one "mercury__" at the
        % start of the function name.
    ModuleNameString0 = sym_name_to_string_sep(
        mlds_module_name_to_sym_name(ModuleName), "__"),
    (
        string__prefix(ModuleNameString0, "mercury__")
    ->
        ModuleNameString = ModuleNameString0
    ;
        string__append("mercury__", ModuleNameString0,
            ModuleNameString)
    ),
    string__append_list([ModuleNameString, "__init", Suffix], InitFnName).

%-----------------------------------------------------------------------------%

/***************
XXX The following is all not yet implemented for mlds_to_gcc.m.
The code below shows what mlds_to_c.m does
(modified to avoid using C macros, which we'll need to do for mlds_to_gcc.m).

    %
    % Maybe output the function `mercury__<modulename>__init()'.
    % The body of the function consists of calls
    % MR_init_entry(<function>) for each function defined in the
    % module.
    %
:- pred mlds_output_init_fn_decls(mlds_module_name::in,
        io__state::di, io__state::uo) is det.

mlds_output_init_fn_decls(ModuleName) -->
    output_init_fn_name(ModuleName, ""),
    io__write_string(";\n"),
    output_init_fn_name(ModuleName, "_type_tables"),
    io__write_string(";\n"),
    output_init_fn_name(ModuleName, "_debugger"),
    io__write_string(";\n").

:- pred mlds_output_init_fn_defns(mlds_module_name::in, list(mlds_defn)::in,
        list(mlds_defn)::in, io__state::di, io__state::uo) is det.

mlds_output_init_fn_defns(ModuleName, FuncDefns, TypeCtorInfoDefns) -->
    output_init_fn_name(ModuleName, ""),
    io__write_string("\n{\n"),
    io_get_globals(Globals),
    (
        { need_to_init_entries(Globals) },
        { FuncDefns \= [] }
    ->
        io__write_strings(
                ["\tstatic MR_bool initialised = MR_FALSE;\n",
                "\tif (initialised) return;\n",
                "\tinitialised = MR_TRUE;\n\n"]),
        mlds_output_calls_to_init_entry(ModuleName, FuncDefns)
    ;
        []
    ),
    io__write_string("}\n\n"),

    output_init_fn_name(ModuleName, "_type_tables"),
    io__write_string("\n{\n"),
    (
        { TypeCtorInfoDefns \= [] }
    ->
        io__write_strings(
                ["\tstatic MR_bool initialised = MR_FALSE;\n",
                "\tif (initialised) return;\n",
                "\tinitialised = MR_TRUE;\n\n"]),
        mlds_output_calls_to_register_tci(ModuleName,
            TypeCtorInfoDefns)
    ;
        []
    ),
    io__write_string("}\n\n"),

    output_init_fn_name(ModuleName, "_debugger"),
    io__write_string("\n{\n"),
    io__write_string(
        "\tMR_fatal_error(""debugger initialization in MLDS grade"");\n"),
    io__write_string("}\n").

:- pred output_init_fn_name(mlds_module_name::in, string::in,
        io__state::di, io__state::uo) is det.

output_init_fn_name(ModuleName, Suffix) -->
        % Here we ensure that we only get one "mercury__" at the
        % start of the function name.
    { mdbcomp__prim_data__sym_name_to_string(
        mlds_module_name_to_sym_name(ModuleName), "__",
        ModuleNameString0) },
    { string__prefix(ModuleNameString0, "mercury__") ->
        ModuleNameString = ModuleNameString0
    ;
        string__append("mercury__", ModuleNameString0, ModuleNameString)
    },
    io__write_string("void "),
    io__write_string(ModuleNameString),
    io__write_string("__init"),
    io__write_string(Suffix),
    io__write_string("(void)").

:- pred need_to_init_entries(globals::in) is semidet.
need_to_init_entries(Globals) :-
    % We only need to output calls to MR_init_entry() if profiling is
    % enabled.
    ( Option = profile_calls
    ; Option = profile_time
    ; Option = profile_memory
    ),
    globals__lookup_bool_option(Globals, Option, yes).

    % Generate calls to MR_init_entry() for the specified functions.
    %
:- pred mlds_output_calls_to_init_entry(mlds_module_name::in,
    list(mlds_defn)::in, io__state::di, io__state::uo) is det.

mlds_output_calls_to_init_entry(_ModuleName, []) --> [].
mlds_output_calls_to_init_entry(ModuleName, [FuncDefn | FuncDefns]) -->
    { FuncDefn = mlds_defn(EntityName, _, _, _) },
    % Generate a call to MR_insert_entry_label(), which is declared as
    %   MR_insert_entry_label(const char *name, MR_Code *addr,
    %       const MR_Stack_Layout_Entry *entry_layout);
    io__write_string("\tMR_insert_entry_label("""),
    { QualifiedName = qual(ModuleName, module_qual, EntityName) },
    mlds_output_fully_qualified_name(QualifiedName),
    io__write_string("\t"", "),
    mlds_output_fully_qualified_name(QualifiedName),
    io__write_string(", NULL);\n"),
    mlds_output_calls_to_init_entry(ModuleName, FuncDefns).

    % Generate calls to MR_register_type_ctor_info() for the specified
    % type_ctor_infos.
    %
:- pred mlds_output_calls_to_register_tci(mlds_module_name::in,
    list(mlds_defn)::in, io__state::di, io__state::uo) is det.

mlds_output_calls_to_register_tci(_ModuleName, []) --> [].
mlds_output_calls_to_register_tci(ModuleName,
        [TypeCtorInfoDefn | TypeCtorInfoDefns]) -->
    { TypeCtorInfoDefn = mlds_defn(EntityName, _, _, _) },
    io__write_string("\tMR_register_type_ctor_info(&"),
    mlds_output_fully_qualified_name(
        qual(ModuleName, module_qual, EntityName)),
    io__write_string(");\n"),
    mlds_output_calls_to_register_tci(ModuleName, TypeCtorInfoDefns).
********************/

%-----------------------------------------------------------------------------%
%
% Foreign language interface stuff
%

/****************
XXX The following code for handling `pragma export'
is all not yet implemented for mlds_to_gcc.m.
The code below is copied from mlds_to_c.m.
It shows what we need to do.

:- pred mlds_output_pragma_export_decl(mlds_module_name, indent,
        mlds_pragma_export, io__state, io__state).
:- mode mlds_output_pragma_export_decl(in, in, in, di, uo) is det.

mlds_output_pragma_export_decl(ModuleName, Indent, PragmaExport) -->
    mlds_output_pragma_export_func_name(ModuleName, Indent, PragmaExport),
    io__write_string(";").

:- pred mlds_output_pragma_export_defn(mlds_module_name, indent,
        mlds_pragma_export, io__state, io__state).
:- mode mlds_output_pragma_export_defn(in, in, in, di, uo) is det.

mlds_output_pragma_export_defn(ModuleName, Indent, PragmaExport) -->
    { PragmaExport = ml_pragma_export(_C_name, MLDS_Name, MLDS_Signature,
            Context) },
    mlds_output_pragma_export_func_name(ModuleName, Indent, PragmaExport),
    io__write_string("\n"),
    mlds_indent(Context, Indent),
    io__write_string("{\n"),
    mlds_indent(Context, Indent),
    mlds_output_pragma_export_defn_body(ModuleName, MLDS_Name,
                MLDS_Signature),
    io__write_string("}\n").

:- pred mlds_output_pragma_export_func_name(mlds_module_name, indent,
        mlds_pragma_export, io__state, io__state).
:- mode mlds_output_pragma_export_func_name(in, in, in, di, uo) is det.

mlds_output_pragma_export_func_name(ModuleName, Indent,
        ml_pragma_export(C_name, _MLDS_Name, Signature, Context)) -->
    { Name = qual(ModuleName, module_qual, export(C_name)) },
    mlds_indent(Context, Indent),
    % For functions exported using `pragma export',
    % we use the default C calling convention.
    { CallingConvention = "" },
    mlds_output_func_decl_ho(Indent, Name, Context,
            CallingConvention, Signature,
            mlds_output_pragma_export_type(prefix),
            mlds_output_pragma_export_type(suffix)).

:- type locn ---> prefix ; suffix.
:- pred mlds_output_pragma_export_type(locn, mlds_type, io__state, io__state).
:- mode mlds_output_pragma_export_type(in, in, di, uo) is det.

mlds_output_pragma_export_type(suffix, _Type) --> [].
mlds_output_pragma_export_type(prefix, mercury_type(Type, _)) -->
    { export__type_to_type_string(Type, String) },
    io__write_string(String).
mlds_output_pragma_export_type(prefix, mlds_cont_type(_)) -->
    io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds_commit_type) -->
    io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds_native_bool_type) -->
    io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds_native_int_type) -->
    io__write_string("MR_Integer").
mlds_output_pragma_export_type(prefix, mlds_native_float_type) -->
    io__write_string("MR_Float").
mlds_output_pragma_export_type(prefix, mlds_native_char_type) -->
    io__write_string("MR_Char").
mlds_output_pragma_export_type(prefix, mlds_class_type(_, _, _)) -->
    io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds_array_type(_)) -->
    io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds_ptr_type(Type)) -->
    mlds_output_pragma_export_type(prefix, Type),
    io__write_string(" *").
mlds_output_pragma_export_type(prefix, mlds_func_type(_)) -->
    io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds_generic_type) -->
    io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds_generic_env_ptr_type) -->
    io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds_pseudo_type_info_type) -->
    io__write_string("MR_Word").
mlds_output_pragma_export_type(prefix, mlds_rtti_type(_)) -->
    io__write_string("MR_Word").


    %
    % Output the definition body for a pragma export
    %
:- pred mlds_output_pragma_export_defn_body(mlds_module_name,
        mlds_qualified_entity_name, func_params, io__state, io__state).
:- mode mlds_output_pragma_export_defn_body(in, in, in, di, uo) is det.

mlds_output_pragma_export_defn_body(ModuleName, FuncName, Signature) -->
    { Signature = mlds_func_params(Parameters, RetTypes) },

    ( { RetTypes = [] } ->
        io__write_string("\t")
    ; { RetTypes = [RetType] } ->
        io__write_string("\treturn ("),
        mlds_output_pragma_export_type(prefix, RetType),
        mlds_output_pragma_export_type(suffix, RetType),
        io__write_string(") ")
    ;
        { unexpected(this_file, "mlds_output_pragma_export: multiple return types") }
    ),

    mlds_output_fully_qualified_name(FuncName),
    io__write_string("("),
    io__write_list(Parameters, ", ",
            mlds_output_name_with_cast(ModuleName)),
    io__write_string(");\n").


    %
    % Write out the arguments to the MLDS function.  Note the last
    % in the list of the arguments is the return value, so it must
    % be "&arg"
    %
:- pred write_func_args(mlds_module_name::in, mlds_arguments::in,
        io__state::di, io__state::uo) is det.

write_func_args(_ModuleName, []) -->
    { error("write_func_args: empty list") }.
write_func_args(_ModuleName, [_Arg]) -->
    io__write_string("&arg").
write_func_args(ModuleName, [Arg | Args]) -->
    { Args = [_|_] },
    mlds_output_name_with_cast(ModuleName, Arg),
    io__write_string(", "),
    write_func_args(ModuleName, Args).

    %
    % Output a fully qualified name preceded by a cast.
    %
:- pred mlds_output_name_with_cast(mlds_module_name::in,
        pair(mlds_entity_name, mlds_type)::in,
        io__state::di, io__state::uo) is det.

mlds_output_name_with_cast(ModuleName, Name - Type) -->
    mlds_output_cast(Type),
    mlds_output_fully_qualified_name(qual(ModuleName, module_qual, Name)).

************************/

%-----------------------------------------------------------------------------%
%
% Code to output declarations and definitions
%


    % Handle MLDS definitions that occur at global scope.
:- pred gen_defns(mlds_module_name, list(mlds_defn), global_info, global_info,
        io__state, io__state).
:- mode gen_defns(in, in, in, out, di, uo) is det.

gen_defns(_ModuleName, [], GlobalInfo, GlobalInfo) --> [].
gen_defns(ModuleName, [Defn | Defns], GlobalInfo0, GlobalInfo) -->
    gen_defn(ModuleName, Defn, GlobalInfo0, GlobalInfo1),
    gen_defns(ModuleName, Defns, GlobalInfo1, GlobalInfo).

    % Handle MLDS definitions that are nested inside a
    % function definition (or inside a block within a function),
    % and which are hence local to that function.
:- pred build_local_defns(list(mlds_defn), mlds_module_name,
    defn_info, defn_info, io__state, io__state).
:- mode build_local_defns(in, in, in, out, di, uo) is det.

build_local_defns([], _, DefnInfo, DefnInfo) --> [].
build_local_defns([Defn|Defns], ModuleName, DefnInfo0, DefnInfo) -->
    build_local_defn(Defn, DefnInfo0, ModuleName, GCC_Defn),
    % Insert the variable definition into our symbol table.
    % The MLDS code that the MLDS code generator generates should
    % not have any shadowing of parameters or local variables by
    % nested local variables, so we use map__det_insert rather
    % than map__set here.  (Actually nothing in this module depends
    % on it, so this sanity check here is perhaps a bit paranoid.)
    { Defn = mlds_defn(Name, _, _, _) },
    { DefnInfo1 = DefnInfo0 ^ local_vars :=
        map__det_insert(DefnInfo0 ^ local_vars,
            qual(ModuleName, module_qual, Name), GCC_Defn) },
    build_local_defns(Defns, ModuleName, DefnInfo1, DefnInfo).

    % Handle MLDS definitions that are nested inside a type,
    % i.e. fields of that type.
:- pred build_field_defns(list(mlds_defn), mlds_module_name, global_info,
        gcc__field_decls, field_table, field_table,
        io__state, io__state).
:- mode build_field_defns(in, in, in, out, in, out, di, uo) is det.

build_field_defns([], _, _, FieldList, FieldTable, FieldTable) -->
    gcc__empty_field_list(FieldList).
build_field_defns([Defn|Defns], ModuleName, GlobalInfo, FieldList,
        FieldTable0, FieldTable) -->
    build_field_defn(Defn, ModuleName, GlobalInfo, GCC_FieldDefn),
    % Insert the field definition into our field symbol table.
    { Defn = mlds_defn(Name, _, _, _) },
    ( { Name = entity_data(mlds_data_var(FieldName)) } ->
        { GCC_FieldName = ml_var_name_to_string(FieldName) },
        { FieldTable1 = map__det_insert(FieldTable0,
            qual(ModuleName, type_qual, GCC_FieldName),
            GCC_FieldDefn) }
    ;
        { unexpected(this_file, "non-var field") }
    ),
    build_field_defns(Defns, ModuleName, GlobalInfo, FieldList0,
        FieldTable1, FieldTable),
    gcc__cons_field_list(GCC_FieldDefn, FieldList0, FieldList).

:- pred gen_defn(mlds_module_name, mlds_defn, global_info, global_info,
        io__state, io__state).
:- mode gen_defn(in, in, in, out, di, uo) is det.

gen_defn(ModuleName, Defn, GlobalInfo0, GlobalInfo) -->
    { Defn = mlds_defn(Name, Context, Flags, DefnBody) },
    gen_defn_body(qual(ModuleName, module_qual, Name), Context, Flags,
        DefnBody, GlobalInfo0, GlobalInfo).

:- pred build_local_defn(mlds_defn, defn_info, mlds_module_name,
        gcc__var_decl, io__state, io__state).
:- mode build_local_defn(in, in, in, out, di, uo) is det.

build_local_defn(Defn, DefnInfo, ModuleName, GCC_Defn) -->
    { Defn = mlds_defn(Name, Context, Flags, DefnBody) },
    build_local_defn_body(qual(ModuleName, module_qual, Name),
        DefnInfo, Context, Flags,
        DefnBody, GCC_Defn).

:- pred build_field_defn(mlds_defn, mlds_module_name, global_info,
        gcc__field_decl, io__state, io__state).
:- mode build_field_defn(in, in, in, out, di, uo) is det.

build_field_defn(Defn, ModuleName, GlobalInfo, GCC_Defn) -->
    { Defn = mlds_defn(Name, Context, Flags, DefnBody) },
    build_field_defn_body(qual(ModuleName, type_qual, Name),
        Context, Flags, DefnBody, GlobalInfo, GCC_Defn).

:- pred gen_defn_body(mlds_qualified_entity_name,
        mlds_context, mlds_decl_flags, mlds_entity_defn,
        global_info, global_info, io__state, io__state).
:- mode gen_defn_body(in, in, in, in, in, out, di, uo) is det.

gen_defn_body(Name, Context, Flags, DefnBody, GlobalInfo0, GlobalInfo) -->
    (
        { DefnBody = mlds_data(Type, Initializer, _GCStatement) },
        { LocalVars = map__init },
        { LabelTable = map__init },
        { DefnInfo = defn_info(GlobalInfo0, Name, LocalVars,
            LabelTable) },
        { GCC_Name = build_qualified_name(Name) },
        build_type(Type, get_initializer_array_size(Initializer),
            GlobalInfo0, GCC_Type),
        build_initializer(Initializer, GCC_Type, DefnInfo,
            GCC_Initializer),
        gcc__build_static_var_decl(GCC_Name, GCC_Type, GCC_Initializer,
            GCC_Defn),
        add_var_decl_flags(Flags, GCC_Defn),
        gcc__finish_static_var_decl(GCC_Defn),
        %
        % insert the definition in our symbol table
        %
        { GlobalVars0 = GlobalInfo0 ^ global_vars },
        { GlobalVars = map__det_insert(GlobalVars0, Name, GCC_Defn) },
        { GlobalInfo = GlobalInfo0 ^ global_vars := GlobalVars }
    ;
        { DefnBody = mlds_function(_MaybePredProcId, Signature,
            FunctionBody, _Attributes, EnvVarNames) },
        { expect(set.empty(EnvVarNames), this_file,
            "gen_defn_body: EnvVarNames") },
        gen_func(Name, Context, Flags, Signature, FunctionBody,
            GlobalInfo0, GlobalInfo)
    ;
        { DefnBody = mlds_class(ClassDefn) },
        gen_class(Name, Context, ClassDefn,
            GlobalInfo0, GlobalInfo)
    ).

:- pred build_local_defn_body(mlds_qualified_entity_name, defn_info,
        mlds_context, mlds_decl_flags, mlds_entity_defn,
        gcc__var_decl, io__state, io__state).
:- mode build_local_defn_body(in, in, in, in, in, out, di, uo) is det.

build_local_defn_body(Name, DefnInfo, _Context, Flags, DefnBody, GCC_Defn) -->
    (
        { DefnBody = mlds_data(Type, Initializer, _GCStatement) },
        build_local_data_defn(Name, Flags, Type,
            Initializer, DefnInfo, GCC_Defn)
    ;
        { DefnBody = mlds_function(_, _, _, _, _) },
        % nested functions should get eliminated by ml_elim_nested,
        % unless --gcc-nested-functions is enabled.
        % XXX --gcc-nested-functions is not yet implemented
        { sorry(this_file, "nested function (`--gcc-nested-functions' "
            ++ "not yet supported with `--target asm')") }
    ;
        { DefnBody = mlds_class(_) },
        % currently the MLDS code generator doesn't generate
        % types nested inside functions, so we don't need to
        % implement this
        { unexpected(this_file, "nested type") }
    ).

:- pred build_field_defn_body(mlds_qualified_entity_name,
        mlds_context, mlds_decl_flags, mlds_entity_defn,
        global_info, gcc__field_decl,
        io__state, io__state).
:- mode build_field_defn_body(in, in, in, in, in, out, di, uo) is det.

build_field_defn_body(Name, _Context, Flags, DefnBody, GlobalInfo,
        GCC_Defn) -->
    (
        { DefnBody = mlds_data(Type, Initializer, _GCStatement) },
        build_field_data_defn(Name, Type, Initializer, GlobalInfo,
            GCC_Defn),
        add_field_decl_flags(Flags, GCC_Defn)
    ;
        { DefnBody = mlds_function(_, _, _, _, _) },
        { unexpected(this_file, "function nested in type") }
    ;
        { DefnBody = mlds_class(_) },
        { unexpected(this_file, "type nested in type") }
    ).

%-----------------------------------------------------------------------------%
%
% Code to handle declaration flags.
%

%
% decl flags for variables
%

:- pred add_var_decl_flags(mlds_decl_flags, gcc__var_decl,
        io__state, io__state).
:- mode add_var_decl_flags(in, in, di, uo) is det.

add_var_decl_flags(Flags, GCC_Defn) -->
    add_var_access_flag(        access(Flags),      GCC_Defn),
    % note that the per_instance flag is handled separately,
    % by calling build_local_var or build_static_var
    add_var_virtuality_flag(    virtuality(Flags),  GCC_Defn),
    add_var_finality_flag(      finality(Flags),    GCC_Defn),
    add_var_constness_flag(     constness(Flags),   GCC_Defn),
    add_var_abstractness_flag(  abstractness(Flags),    GCC_Defn).

:- pred add_var_access_flag(access, gcc__var_decl, io__state, io__state).
:- mode add_var_access_flag(in, in, di, uo) is det.

add_var_access_flag(acc_public, GCC_Defn) -->
    gcc__set_var_decl_public(GCC_Defn).
add_var_access_flag(acc_private, _GCC_Defn) -->
    % this should only be used for global variables,
    % where it is the default
    [].
add_var_access_flag(acc_protected, _GCC_Defn) -->
    { sorry(this_file, "`protected' access") }.
add_var_access_flag(acc_default, _GCC_Defn) -->
    { sorry(this_file, "`default' access") }.
add_var_access_flag(acc_local, _GCC_Defn) -->
    % this should only be used for local variables,
    % where it is the default
    [].

:- pred add_var_virtuality_flag(virtuality, gcc__var_decl,
    io__state, io__state).
:- mode add_var_virtuality_flag(in, in, di, uo) is det.

add_var_virtuality_flag(virtual, _GCC_Defn) -->
    % `virtual' should only be used for methods,
    % not for variables.
    { unexpected(this_file, "`virtual' variable") }.
add_var_virtuality_flag(non_virtual, _GCC_Defn) -->
    % this is the default
    [].

:- pred add_var_constness_flag(constness, gcc__var_decl,
    io__state, io__state).
:- mode add_var_constness_flag(in, in, di, uo) is det.

add_var_constness_flag(const, GCC_Defn) -->
    gcc__set_var_decl_readonly(GCC_Defn).
add_var_constness_flag(modifiable, _GCC_Defn) -->
    % this is the default
    [].

:- pred add_var_finality_flag(finality, gcc__var_decl,
    io__state, io__state).
:- mode add_var_finality_flag(in, in, di, uo) is det.

add_var_finality_flag(final, GCC_Defn) -->
    gcc__set_var_decl_readonly(GCC_Defn).
add_var_finality_flag(overridable, _GCC_Defn) -->
    % this is the default
    [].

:- pred add_var_abstractness_flag(mlds__abstractness, gcc__var_decl,
    io__state, io__state).
:- mode add_var_abstractness_flag(in, in, di, uo) is det.

add_var_abstractness_flag(concrete, _GCC_Defn) -->
    % this is the default
    [].
add_var_abstractness_flag(abstract, _GCC_Defn) -->
    % `abstract' should only be used for fields or methods,
    % not for variables.
    { unexpected(this_file, "`abstract' variable") }.

%
% decl flags for fields
%

:- pred add_field_decl_flags(mlds_decl_flags, gcc__field_decl,
        io__state, io__state).
:- mode add_field_decl_flags(in, in, di, uo) is det.

add_field_decl_flags(Flags, GCC_Defn) -->
    add_field_access_flag(access(Flags), GCC_Defn),
    add_field_per_instance_flag(per_instance(Flags), GCC_Defn),
    add_field_virtuality_flag(virtuality(Flags), GCC_Defn),
    add_field_finality_flag(finality(Flags), GCC_Defn),
    add_field_constness_flag(constness(Flags), GCC_Defn),
    add_field_abstractness_flag(abstractness(Flags), GCC_Defn).

:- pred add_field_access_flag(access, gcc__field_decl,
        io__state, io__state).
:- mode add_field_access_flag(in, in, di, uo) is det.

add_field_access_flag(acc_public, _GCC_Defn) -->
    % this is the default
    [].
add_field_access_flag(acc_private, _GCC_Defn) -->
    { sorry(this_file, "`private' field") }.
add_field_access_flag(acc_protected, _GCC_Defn) -->
    { sorry(this_file, "`protected' field") }.
add_field_access_flag(acc_default, _GCC_Defn) -->
    { sorry(this_file, "`default' field") }.
add_field_access_flag(acc_local, _GCC_Defn) -->
    { sorry(this_file, "`local' field") }.

:- pred add_field_per_instance_flag(mlds__per_instance, gcc__field_decl,
    io__state, io__state).
:- mode add_field_per_instance_flag(in, in, di, uo) is det.

add_field_per_instance_flag(per_instance, _GCC_Defn) -->
    % this is the default
    [].
add_field_per_instance_flag(one_copy, _GCC_Defn) -->
    % Static fields should be hoisted out as global variables
    { unexpected(this_file, "`static' field") }.

:- pred add_field_virtuality_flag(virtuality, gcc__field_decl,
    io__state, io__state).
:- mode add_field_virtuality_flag(in, in, di, uo) is det.

add_field_virtuality_flag(virtual, _GCC_Defn) -->
    { sorry(this_file, "`virtual' field") }.
add_field_virtuality_flag(non_virtual, _GCC_Defn) -->
    % this is the default
    [].

:- pred add_field_constness_flag(constness, gcc__field_decl,
    io__state, io__state).
:- mode add_field_constness_flag(in, in, di, uo) is det.

add_field_constness_flag(const, _GCC_Defn) -->
    { sorry(this_file, "`const' field") }.
add_field_constness_flag(modifiable, _GCC_Defn) -->
    % this is the default
    [].

:- pred add_field_finality_flag(finality, gcc__field_decl,
    io__state, io__state).
:- mode add_field_finality_flag(in, in, di, uo) is det.

add_field_finality_flag(final, _GCC_Defn) -->
    { sorry(this_file, "`final' field") }.
add_field_finality_flag(overridable, _GCC_Defn) -->
    % this is the default
    [].

:- pred add_field_abstractness_flag(mlds__abstractness, gcc__field_decl,
    io__state, io__state).
:- mode add_field_abstractness_flag(in, in, di, uo) is det.

add_field_abstractness_flag(concrete, _GCC_Defn) -->
    % this is the default
    [].
add_field_abstractness_flag(abstract, _GCC_Defn) -->
    { sorry(this_file, "`abstract' field") }.

%
% decl flags for functions
%

:- pred add_func_decl_flags(mlds_decl_flags, gcc__func_decl,
    io__state, io__state).
:- mode add_func_decl_flags(in, in, di, uo) is det.

add_func_decl_flags(Flags, GCC_Defn) -->
    add_func_access_flag(       access(Flags),      GCC_Defn),
    add_func_per_instance_flag( per_instance(Flags),    GCC_Defn),
    add_func_virtuality_flag(   virtuality(Flags),  GCC_Defn),
    add_func_finality_flag(     finality(Flags),    GCC_Defn),
    add_func_constness_flag(    constness(Flags),   GCC_Defn),
    add_func_abstractness_flag( abstractness(Flags),    GCC_Defn).

:- pred add_func_access_flag(access, gcc__func_decl,
    io__state, io__state).
:- mode add_func_access_flag(in, in, di, uo) is det.

add_func_access_flag(acc_public, GCC_Defn) -->
    gcc__set_func_decl_public(GCC_Defn).
add_func_access_flag(acc_private, _GCC_Defn) -->
    % this is the default
    [].
add_func_access_flag(acc_protected, _GCC_Defn) -->
    { sorry(this_file, "`protected' access") }.
add_func_access_flag(acc_default, _GCC_Defn) -->
    { sorry(this_file, "`default' access") }.
add_func_access_flag(acc_local, _GCC_Defn) -->
    % nested functions are not supported
    { sorry(this_file, "`local' access") }.

:- pred add_func_per_instance_flag(mlds__per_instance, gcc__func_decl,
    io__state, io__state).
:- mode add_func_per_instance_flag(in, in, di, uo) is det.

    % For functions, we ignore the `per_instance' flag here.
    % For global functions, this flag is meaningless;
    % and currently we don't support nested functions
    % or class member functions.
add_func_per_instance_flag(per_instance, _GCC_Defn) --> [].
add_func_per_instance_flag(one_copy, _GCC_Defn) --> [].

:- pred add_func_virtuality_flag(virtuality, gcc__func_decl,
    io__state, io__state).
:- mode add_func_virtuality_flag(in, in, di, uo) is det.

add_func_virtuality_flag(virtual, _GCC_Defn) -->
    { sorry(this_file, "`virtual' function") }.
add_func_virtuality_flag(non_virtual, _GCC_Defn) -->
    % this is the default
    [].

:- pred add_func_constness_flag(constness, gcc__func_decl,
    io__state, io__state).
:- mode add_func_constness_flag(in, in, di, uo) is det.

add_func_constness_flag(const, _GCC_Defn) -->
    { sorry(this_file, "`const' function") }.
add_func_constness_flag(modifiable, _GCC_Defn) -->
    % this is the default
    [].

:- pred add_func_finality_flag(finality, gcc__func_decl,
    io__state, io__state).
:- mode add_func_finality_flag(in, in, di, uo) is det.

add_func_finality_flag(final, _GCC_Defn) -->
    { sorry(this_file, "`final' function") }.
add_func_finality_flag(overridable, _GCC_Defn) -->
    % this is the default
    [].

:- pred add_func_abstractness_flag(mlds__abstractness, gcc__func_decl,
    io__state, io__state).
:- mode add_func_abstractness_flag(in, in, di, uo) is det.

add_func_abstractness_flag(abstract, _GCC_Defn) -->
    { sorry(this_file, "`abstract' function") }.
add_func_abstractness_flag(concrete, _GCC_Defn) -->
    % this is the default
    [].

%-----------------------------------------------------------------------------%
%
% Code to output data declarations/definitions
%

    % Handle an MLDS data definition that is nested inside a
    % function definition (or inside a block within a function),
    % and which is hence local to that function.
:- pred build_local_data_defn(mlds_qualified_entity_name, mlds_decl_flags,
        mlds_type, mlds_initializer, defn_info, gcc__var_decl,
        io__state, io__state).
:- mode build_local_data_defn(in, in, in, in, in, out, di, uo) is det.

build_local_data_defn(Name, Flags, Type, Initializer, DefnInfo, GCC_Defn) -->
    build_type(Type, get_initializer_array_size(Initializer),
        DefnInfo ^ global_info, GCC_Type),
    { Name = qual(_ModuleName, _QualKind, UnqualName) },
    ( { UnqualName = entity_data(mlds_data_var(VarName0)) } ->
        { VarName = VarName0 }
    ;
        % var/1 should be the only kind of mlds_data_name for which
        % the MLDS code generator generates local definitions
        % (within functions)
        { unexpected(this_file, "build_local_data_defn: non-var") }
    ),
    { PerInstance = per_instance(Flags) },
    (
        { PerInstance = per_instance },
        % an ordinary local variable
        { GCC_VarName = ml_var_name_to_string(VarName) },
        gcc__build_local_var_decl(GCC_VarName, GCC_Type, GCC_Defn),
        add_var_decl_flags(Flags, GCC_Defn),
        ( { Initializer = no_initializer } ->
            []
        ;
            build_initializer(Initializer, GCC_Type, DefnInfo,
                GCC_InitExpr),
            gcc__gen_assign(gcc__var_expr(GCC_Defn), GCC_InitExpr)
        )
    ;
        { PerInstance = one_copy },
        % a local static variable
        % these must always have initializers
        build_initializer(Initializer, GCC_Type, DefnInfo,
            GCC_InitExpr),
        { GCC_VarName = ml_var_name_to_string(VarName) },
        gcc__build_static_var_decl(GCC_VarName, GCC_Type, GCC_InitExpr,
            GCC_Defn),
        { MangledVarName = name_mangle(GCC_VarName) },
        gcc__set_var_decl_asm_name(GCC_Defn, MangledVarName),
        add_var_decl_flags(Flags, GCC_Defn),
        gcc__finish_static_var_decl(GCC_Defn)
    ).

    % Handle an MLDS data definition that is nested inside a type,
    % i.e. a field definition.
:- pred build_field_data_defn(mlds_qualified_entity_name, mlds_type,
        mlds_initializer, global_info, gcc__field_decl,
        io__state, io__state).
:- mode build_field_data_defn(in, in, in, in, out, di, uo) is det.

build_field_data_defn(Name, Type, Initializer, GlobalInfo, GCC_Defn) -->
    build_type(Type, get_initializer_array_size(Initializer),
        GlobalInfo, GCC_Type),
    { Name = qual(_ModuleName, _QualKind, UnqualName) },
    ( { UnqualName = entity_data(mlds_data_var(VarName)) } ->
        { GCC_VarName = ml_var_name_to_string(VarName) },
        gcc__build_field_decl(GCC_VarName, GCC_Type, GCC_Defn)
    ;
        { sorry(this_file, "build_field_data_defn: non-var") }
    ),
    ( { Initializer = no_initializer } ->
        []
    ;
        % fields can't have initializers
        { sorry(this_file, "build_field_data_defn: initializer") }
    ).

:- pred build_initializer(mlds_initializer, gcc__type, defn_info,
        gcc__expr, io__state, io__state) is det.
:- mode build_initializer(in, in, in, out, di, uo) is det.

build_initializer(Initializer, GCC_Type, DefnInfo, GCC_Expr) -->
    (
        { Initializer = no_initializer },
        { unexpected(this_file, "no_initializer (build_initializer)") }
    ;
        { Initializer = init_obj(Rval) },
        build_rval(Rval, DefnInfo, GCC_Expr)
    ;
        { Initializer = init_struct(_Type, InitList) },
        gcc__get_struct_field_decls(GCC_Type, GCC_FieldDecls),
        build_struct_initializer(InitList, GCC_FieldDecls, DefnInfo,
            GCC_InitList),
        gcc__build_initializer_expr(GCC_InitList, GCC_Type, GCC_Expr)
    ;
        { Initializer = init_array(InitList) },
        gcc__get_array_elem_type(GCC_Type, GCC_ElemType),
        build_array_initializer(InitList, GCC_ElemType, 0, DefnInfo,
            GCC_InitList),
        gcc__build_initializer_expr(GCC_InitList, GCC_Type, GCC_Expr)
    ).

:- pred build_array_initializer(list(mlds_initializer), gcc__type, int,
        defn_info, gcc__init_list, io__state, io__state) is det.
:- mode build_array_initializer(in, in, in, in, out, di, uo) is det.

build_array_initializer([], _, _, _, GCC_InitList) -->
    gcc__empty_init_list(GCC_InitList).
build_array_initializer([Init | Inits], GCC_ElemType, Index, DefnInfo,
        GCC_InitList) -->
    gcc__array_elem_initializer(Index, GCC_InitIndex),
    build_initializer(Init, GCC_ElemType, DefnInfo, GCC_InitValue),
    build_array_initializer(Inits, GCC_ElemType, Index + 1, DefnInfo,
        GCC_InitList0),
    gcc__cons_init_list(GCC_InitIndex, GCC_InitValue,
        GCC_InitList0, GCC_InitList).

:- pred build_struct_initializer(list(mlds_initializer), gcc__field_decls,
        defn_info, gcc__init_list, io__state, io__state) is det.
:- mode build_struct_initializer(in, in, in, out, di, uo) is det.

build_struct_initializer([], _, _, GCC_InitList) -->
    gcc__empty_init_list(GCC_InitList).
build_struct_initializer([Init | Inits], GCC_FieldDecls, DefnInfo,
        GCC_InitList) -->
    gcc__next_field_decl(GCC_FieldDecls, GCC_ThisFieldDecl,
        GCC_RemainingFieldDecls),
    gcc__struct_field_initializer(GCC_ThisFieldDecl, GCC_InitField),
    gcc__field_type(GCC_ThisFieldDecl, GCC_ThisFieldType),
    build_initializer(Init, GCC_ThisFieldType, DefnInfo, GCC_InitValue),
    build_struct_initializer(Inits, GCC_RemainingFieldDecls, DefnInfo,
        GCC_InitList0),
    gcc__cons_init_list(GCC_InitField, GCC_InitValue, GCC_InitList0,
        GCC_InitList).

%-----------------------------------------------------------------------------%
%
% Code to output type definitions
%

:- pred gen_class(mlds_qualified_entity_name, mlds_context,
        mlds_class_defn, global_info, global_info,
        io__state, io__state).
:- mode gen_class(in, in, in, in, out, di, uo) is det.

gen_class(Name, Context, ClassDefn, GlobalInfo0, GlobalInfo) -->
    %
    % To avoid name clashes, we need to qualify the names of
    % the member constants with the class name.
    % (In particular, this is needed for enumeration constants
    % and for the nested classes that we generate for constructors
    % of discriminated union types.)
    % Here we compute the appropriate qualifier.
    %
    { Name = qual(ModuleName, QualKind, UnqualName) },
    globals__io_get_globals(Globals),
    { UnqualName = entity_type(ClassName, ClassArity) ->
        globals.get_target(Globals, Target),
        ClassModuleName = mlds_append_class_qualifier(Target, ModuleName,
            QualKind, ClassName, ClassArity)
    ;
        unexpected(this_file, "mlds_output_enum_constants")
    },

    %
    % Hoist out static members, since plain old C doesn't support
    % static members in structs (except for enumeration constants).
    %
    % XXX this should be conditional: only when compiling to C,
    % not when compiling to C++
    %
    { ClassDefn = mlds_class_defn(Kind, _Imports, BaseClasses, _Implements,
        Ctors, AllMembers) },
    { Ctors = [] ->
        true
    ;
        unexpected(this_file, "constructors")
    },
    ( { Kind = mlds_enum } ->
        { StaticMembers = [] },
        { StructMembers = AllMembers }
    ;
        { list__filter(is_static_member, AllMembers, StaticMembers,
            NonStaticMembers) },
        { StructMembers = NonStaticMembers }
    ),

    %
    % Convert the base classes into member variables,
    % since plain old C doesn't support base classes.
    %
    % This is copied from the MLDS->C back-end.
    % We could probably handle it more directly for the
    % MLDS->GCC back-end, but doing it this way is simple
    % enough, and works.
    %
    { list__map_foldl(mlds_make_base_class(Context),
        BaseClasses, BaseDefns, 1, _) },
    { list__append(BaseDefns, StructMembers, BasesAndMembers) },

    %
    % Output the class declaration and the class members.
    % We treat enumerations specially.
    %
    ( { Kind = mlds_enum } ->
        % XXX enumeration definitions are not yet implemented
        { sorry(this_file, "enum type (`--high-level-data' not yet "
            ++ "implemented for `--target asm')") }
        /************
        mlds_output_class_decl(Indent, Name, ClassDefn),
        io__write_string(" {\n"),
        mlds_output_enum_constants(Indent + 1, ClassModuleName,
            BasesAndMembers)
        *************/
    ;
        %
        % Build a gcc declaration node for the struct and
        % for the fields it contains.  Create a field table
        % mapping the field names to their respective nodes.
        %
        { map__init(FieldTable0) },
        build_field_defns(BasesAndMembers, ClassModuleName,
            GlobalInfo0, FieldDecls, FieldTable0, FieldTable),
        { AsmStructName = build_qualified_name(Name) },
        gcc__build_struct_type_decl(AsmStructName,
            FieldDecls, StructTypeDecl),
        %
        % Insert the gcc declaration node and the field table
        % for this type into the global type table
        %
        { TypeTable0 = GlobalInfo0 ^ type_table },
        { map__det_insert(TypeTable0, Name,
            gcc_type_info(StructTypeDecl, FieldTable),
            TypeTable) },
        { GlobalInfo1 = GlobalInfo0 ^ type_table := TypeTable }
    ),
    %
    % Output the static members.
    %
    gen_defns(ClassModuleName, StaticMembers, GlobalInfo1, GlobalInfo).

:- pred is_static_member(mlds_defn::in) is semidet.

is_static_member(Defn) :-
    Defn = mlds_defn(Name, _, Flags, _),
    (   Name = entity_type(_, _)
    ;   per_instance(Flags) = one_copy
    ).

    % Convert a base class class_id into a member variable
    % that holds the value of the base class.
    %
:- pred mlds_make_base_class(mlds_context, mlds_class_id, mlds_defn,
        int, int).
:- mode mlds_make_base_class(in, in, out, in, out) is det.

mlds_make_base_class(Context, ClassId, MLDS_Defn, BaseNum0, BaseNum) :-
    BaseName = string__format("base_%d", [i(BaseNum0)]),
    Type = ClassId,
    % We only need GC tracing code for top-level variables,
    % not for base classes.
    GCStatement = gc_no_stmt,
    MLDS_Defn = mlds_defn(
        entity_data(mlds_data_var(mlds_var_name(BaseName, no))), Context,
        ml_gen_public_field_decl_flags,
        mlds_data(Type, no_initializer, GCStatement)),
    BaseNum = BaseNum0 + 1.

/***********
XXX enumeration definitions are not yet implemented for mlds_to_gcc.m.
The following code for handling enumeration definitions is copied from
mlds_to_c.m.  It shows what we should generate.

:- pred mlds_output_class_decl(indent, mlds_qualified_entity_name,
        mlds_class_defn, io__state, io__state).
:- mode mlds_output_class_decl(in, in, in, di, uo) is det.

mlds_output_class_decl(_Indent, Name, ClassDefn) -->
    ( { ClassDefn^kind = mlds_enum } ->
        io__write_string("enum "),
        mlds_output_fully_qualified_name(Name),
        io__write_string("_e")
    ;
        io__write_string("struct "),
        mlds_output_fully_qualified_name(Name),
        io__write_string("_s")
    ).

    % Output the definitions of the enumeration constants
    % for an enumeration type.
    %
:- pred mlds_output_enum_constants(indent, mlds_module_name,
        list(mlds_defn), io__state, io__state).
:- mode mlds_output_enum_constants(in, in, in, di, uo) is det.

mlds_output_enum_constants(Indent, EnumModuleName, Members) -->
    %
    % Select the enumeration constants from the list of members
    % for this enumeration type, and output them.
    %
    { EnumConsts = list__filter(is_enum_const, Members) },
    io__write_list(EnumConsts, ",\n",
        mlds_output_enum_constant(Indent, EnumModuleName)),
    io__nl.

    % Test whether one of the members of an mlds_enum class
    % is an enumeration constant.
    %
:- pred is_enum_const(mlds_defn).
:- mode is_enum_const(in) is semidet.

is_enum_const(Defn) :-
    Defn = mlds_defn(_Name, _Context, Flags, _DefnBody),
    constness(Flags) = const.

    % Output the definition of a single enumeration constant.
    %
:- pred mlds_output_enum_constant(indent, mlds_module_name, mlds_defn,
        io__state, io__state).
:- mode mlds_output_enum_constant(in, in, in, di, uo) is det.

mlds_output_enum_constant(Indent, EnumModuleName, Defn) -->
    { Defn = mlds_defn(Name, Context, _Flags, DefnBody) },
    (
        { DefnBody = data(Type, Initializer) }
    ->
        mlds_indent(Context, Indent),
        mlds_output_fully_qualified_name(
            qual(EnumModuleName, type_qual, Name)),
        mlds_output_initializer(Type, Initializer)
    ;
        { unexpected(this_file,
            "mlds_output_enum_constant: constant is not data") }
    ).

***********/

%-----------------------------------------------------------------------------%
%
% Code to output function declarations/definitions
%

:- pred gen_func(mlds_qualified_entity_name, mlds_context,
        mlds_decl_flags, mlds_func_params, mlds_function_body,
        global_info, global_info, io__state, io__state).
:- mode gen_func(in, in, in, in, in, in, out, di, uo) is det.

gen_func(Name, Context, Flags, Signature, MaybeBody,
        GlobalInfo0, GlobalInfo) -->
    { GlobalInfo = GlobalInfo0 },
    (
        { MaybeBody = body_external }
    ;
        { MaybeBody = body_defined_here(Body) },
        gcc__push_gc_context,
        make_func_decl_for_defn(Name, Signature, GlobalInfo0,
            FuncDecl, SymbolTable),
        add_func_decl_flags(Flags, FuncDecl),
        build_label_table(Body, LabelTable),
        { DefnInfo = defn_info(GlobalInfo,
            Name, SymbolTable, LabelTable) },
        set_context(Context),
        gcc__start_function(FuncDecl),
        % mlds_maybe_output_time_profile_instr(Context, Name)
        gen_statement(DefnInfo, Body),
        set_context(Context),
        gcc__end_function,
        gcc__pop_gc_context
    ).

    %
    % Before generating code for a function,
    % we build a table of all the label declarations
    % in that function body.
    %
:- pred build_label_table(statement::in, label_table::out,
        io__state::di, io__state::uo) is det.
build_label_table(Statement, LabelTable) -->
    { solutions.solutions(statement_contains_label(Statement), Labels) },
    list__map_foldl(gcc__build_label, Labels, GCC_LabelDecls),
    { map__from_corresponding_lists(Labels, GCC_LabelDecls,
        LabelTable) }.

:- pred statement_contains_label(statement::in, mlds_label::out)
    is nondet.
statement_contains_label(Statement, Label) :-
    statement_contains_statement(Statement, SubStatement),
    SubStatement = statement(ml_stmt_label(Label), _).

    % XXX we should lookup the existing definition, if there is one,
    % rather than always making a new one
:- pred make_func_decl(mlds_qualified_entity_name::in,
        mlds_func_signature::in, global_info::in,
        gcc__func_decl::out, io__state::di, io__state::uo) is det.
make_func_decl(Name, Signature, GlobalInfo, GCC_FuncDecl) -->
    { Signature = mlds_func_signature(Arguments, ReturnTypes) },
    get_return_type(ReturnTypes, GlobalInfo, RetType),
    { get_qualified_func_name(Name, _ModuleName, FuncName, AsmFuncName) },
    build_param_types(Arguments, GlobalInfo, GCC_Types, GCC_ParamTypes),
    build_dummy_param_decls(GCC_Types, GCC_ParamDecls),
    gcc__build_function_decl(FuncName, AsmFuncName,
        RetType, GCC_ParamTypes, GCC_ParamDecls, GCC_FuncDecl).

:- pred build_dummy_param_decls(list(gcc__type), gcc__param_decls,
        io__state, io__state).
:- mode build_dummy_param_decls(in, out, di, uo) is det.

build_dummy_param_decls([], gcc__empty_param_decls) --> [].
build_dummy_param_decls([Type | Types],
        gcc__cons_param_decls(ParamDecl, ParamDecls)) -->
    gcc__build_param_decl("<unnamed param>", Type, ParamDecl),
    build_dummy_param_decls(Types, ParamDecls).

    % Like make_func_decl, except that it fills in the
    % function parameters properly
:- pred make_func_decl_for_defn(mlds_qualified_entity_name::in,
        mlds_func_params::in, global_info::in, gcc__func_decl::out,
        symbol_table::out, io__state::di, io__state::uo) is det.
make_func_decl_for_defn(Name, Parameters, GlobalInfo, FuncDecl,
        SymbolTable) -->
    { Parameters = mlds_func_params(Arguments, ReturnTypes) },
    get_return_type(ReturnTypes, GlobalInfo, RetType),
    { get_qualified_func_name(Name, ModuleName, FuncName, AsmFuncName) },
    build_param_types_and_decls(Arguments, ModuleName, GlobalInfo,
        ParamTypes, ParamDecls, SymbolTable),
    gcc__build_function_decl(FuncName, AsmFuncName,
        RetType, ParamTypes, ParamDecls, FuncDecl).

:- pred get_return_type(list(mlds_type)::in, global_info::in, gcc__type::out,
        io__state::di, io__state::uo) is det.
get_return_type(List, GlobalInfo, GCC_Type) -->
    ( { List = [] } ->
        { GCC_Type = gcc__void_type_node }
    ; { List = [Type] } ->
        build_type(Type, GlobalInfo, GCC_Type)
    ;
        { unexpected(this_file, "multiple return types") }
    ).

    % get_func_name(Name, ModuleName, FuncName, AsmFuncName):
    % Get the module name and the function name.
    % `FuncName' is the name used for generating debug symbols,
    % whereas `AsmFuncName' is what we actually spit out in the
    % assembler file.
:- pred get_qualified_func_name(mlds_qualified_entity_name::in,
        mlds_module_name::out, string::out, string::out) is det.
get_qualified_func_name(Name, ModuleName, FuncName, AsmFuncName) :-
    Name = qual(ModuleName, _QualKind, EntityName),
    get_func_name(EntityName, FuncName, AsmFuncName0),
    maybe_add_module_qualifier(Name, AsmFuncName0, AsmFuncName).

    % get_func_name(Name, FuncName, AsmFuncName):
    % Get the function name (without any module qualifier).
    % `FuncName' is the name used for generating debug symbols,
    % whereas `AsmFuncName' is what we actually spit out in the
    % assembler file.
:- pred get_func_name(mlds_entity_name::in,
        string::out, string::out) is det.
get_func_name(FunctionName, FuncName, AsmFuncName) :-
    (
        FunctionName = entity_function(PredLabel, ProcId, MaybeSeqNum,
            _PredId)
    ->
        %
        % Generate the AsmFuncName
        % This needs to be fully name mangled to ensure that it
        % is unique.
        %
        % XXX we should consider not appending the modenum and seqnum
        %     if they are not needed.
        %
        get_pred_label_name(PredLabel, AsmFuncName0),
        proc_id_to_int(ProcId, ProcIdNum),
        ( MaybeSeqNum = yes(SeqNum) ->
            AsmFuncName = string__format("%s_%d_%d",
                [s(AsmFuncName0), i(ProcIdNum), i(SeqNum)])
        ;
            AsmFuncName = string__format("%s_%d",
                [s(AsmFuncName0), i(ProcIdNum)])
        ),
        %
        % Generate the FuncName.
        % This is for human consumption, and does not
        % necessarily need to be unique.
        %
        (
            PredLabel = mlds_user_pred_label(_PorF, _ModuleName,
                PredName, _Arity, _CodeModel, _NonOutputFunc),
            FuncName = PredName
        ;
            PredLabel = mlds_special_pred_label(SpecialPredName,
                _ModuleName, TypeName, _Arity),
            FuncName = SpecialPredName ++ TypeName
        )
    ;
        unexpected(this_file, "get_func_name: non-function")
    ).

    % XXX same as mlds_output_pred_label in mlds_to_c,
    % except that it returns a string.
:- pred get_pred_label_name(mlds_pred_label, string).
:- mode get_pred_label_name(in, out) is det.

get_pred_label_name(mlds_user_pred_label(PredOrFunc, MaybeDefiningModule, Name,
        Arity, _CodeMode, _NonOutputFunc), LabelName) :-
    ( PredOrFunc = pf_predicate, Suffix = "p"
    ; PredOrFunc = pf_function, Suffix = "f"
    ),
    MangledName = name_mangle(Name),
    string__format("%s_%d_%s", [s(MangledName), i(Arity), s(Suffix)],
        LabelName0),
    ( MaybeDefiningModule = yes(DefiningModule) ->
        LabelName = LabelName0 ++ "_in__" ++
            get_module_name(DefiningModule)
    ;
        LabelName = LabelName0
    ).
get_pred_label_name(mlds_special_pred_label(PredName, MaybeTypeModule,
        TypeName, TypeArity), LabelName) :-
    MangledPredName = name_mangle(PredName),
    MangledTypeName = name_mangle(TypeName),
    TypeNameString = string__format("%s_%d",
        [s(MangledTypeName), i(TypeArity)]),
    ( MaybeTypeModule = yes(TypeModule) ->
        TypeNameList = [get_module_name(TypeModule),
            "__", TypeNameString]
    ;
        TypeNameList = [TypeNameString]
    ),
    LabelName = string__append_list([MangledPredName, "__" | TypeNameList]).

:- func get_module_name(module_name) = string.

get_module_name(ModuleName) = sym_name_mangle(ModuleName).

:- pred build_param_types(mlds_arg_types::in, global_info::in,
    list(gcc__type)::out, gcc__param_types::out,
    io__state::di, io__state::uo) is det.

build_param_types(ArgTypes, GlobalInfo, GCC_Types, ParamTypes) -->
    build_param_types(ArgTypes, GlobalInfo, GCC_Types,
        gcc__empty_param_types, ParamTypes).

% build a list of parameter types, and prepend this list to the
% gcc__param_types list passed as input
:- pred build_param_types(mlds_arg_types::in, global_info::in,
    list(gcc__type)::out, gcc__param_types::in, gcc__param_types::out,
    io__state::di, io__state::uo) is det.

build_param_types([], _, [], ParamTypes, ParamTypes) --> [].
build_param_types([ArgType | ArgTypes], GlobalInfo, [GCC_Type | GCC_Types],
        ParamTypes0, ParamTypes) -->
    build_param_types(ArgTypes, GlobalInfo, GCC_Types,
        ParamTypes0, ParamTypes1),
    build_type(ArgType, GlobalInfo, GCC_Type),
    { ParamTypes = gcc__cons_param_types(GCC_Type, ParamTypes1) }.

:- pred build_param_types_and_decls(mlds_arguments::in, mlds_module_name::in,
        global_info::in, gcc__param_types::out, gcc__param_decls::out,
        symbol_table::out, io__state::di, io__state::uo) is det.

build_param_types_and_decls([], _, _, gcc__empty_param_types,
        gcc__empty_param_decls, SymbolTable) -->
    { map__init(SymbolTable) }.
build_param_types_and_decls([Arg|Args], ModuleName, GlobalInfo,
        ParamTypes, ParamDecls, SymbolTable) -->
    build_param_types_and_decls(Args, ModuleName, GlobalInfo,
        ParamTypes0, ParamDecls0, SymbolTable0),
    { Arg = mlds_argument(ArgName, Type, _Statement) },
    build_type(Type, GlobalInfo, GCC_Type),
    ( { ArgName = entity_data(mlds_data_var(ArgVarName)) } ->
        { GCC_ArgVarName = ml_var_name_to_string(ArgVarName) },
        gcc__build_param_decl(GCC_ArgVarName, GCC_Type, ParamDecl),
        { SymbolTable = map__det_insert(SymbolTable0,
            qual(ModuleName, module_qual, ArgName), ParamDecl) }
    ;
        { unexpected(this_file,
            "build_param_types_and_decls: invalid param name") }
    ),
    { ParamTypes = gcc__cons_param_types(GCC_Type, ParamTypes0) },
    { ParamDecls = gcc__cons_param_decls(ParamDecl, ParamDecls0) }.

%-----------------------------------------------------------------------------%
%
% Code to build types
%

:- pred build_type(mlds_type, global_info, gcc__type, io__state, io__state).
:- mode build_type(in, in, out, di, uo) is det.

build_type(Type, GlobalInfo, GCC_Type) -->
    build_type(Type, no_size, GlobalInfo, GCC_Type).

:- pred build_type(mlds_type, initializer_array_size, global_info,
        gcc__type, io__state, io__state).
:- mode build_type(in, in, in, out, di, uo) is det.

    % Just represent Mercury arrays as MR_Word.
build_type(mlds_mercury_array_type(_ElemType), _, _, GCC_Type) -->
    globals__io_lookup_bool_option(highlevel_data, HighLevelData),
    ( { HighLevelData = yes } ->
        { sorry(this_file, "--high-level-data (mercury_array_type)") }
    ;
        { GCC_Type = 'MR_Word' }
    ).
build_type(mercury_type(Type, TypeCategory, _), _, _, GCC_Type) -->
    build_mercury_type(Type, TypeCategory, GCC_Type).
build_type(mlds_foreign_type(_), _, _, 'MR_Box') --> [].
build_type(mlds_native_int_type, _, _, gcc__integer_type_node) --> [].
build_type(mlds_native_float_type, _, _, gcc__double_type_node) --> [].
build_type(mlds_native_bool_type, _, _, gcc__boolean_type_node) --> [].
build_type(mlds_native_char_type, _, _, gcc__char_type_node)  --> [].
build_type(mlds_class_type(Name, Arity, ClassKind), _, GlobalInfo,
        GCC_Type) -->
    ( { ClassKind = mlds_enum } ->
        %
        % XXX following comment is copied from mlds_to_c;
        % it is wrong for mlds_to_gcc back-end
        %
        % We can't just use the enumeration type,
        % since the enumeration type's definition
        % is not guaranteed to be in scope at this point.
        % (Fixing that would be somewhat complicated; it would
        % require writing enum definitions to a separate header file.)
        % Also the enumeration might not be word-sized,
        % which would cause problems for e.g. `std_util:arg/2'.
        % So we just use `MR_Integer'.
        %
        { GCC_Type = 'MR_Integer' }
    ;
        %
        % Check to see whether we already have a definition for
        % this type.
        %
        { Name = qual(ModuleName, QualKind, TypeName) },
        { EntityName = qual(ModuleName, QualKind,
            entity_type(TypeName, Arity)) },
        (
            { map__search(GlobalInfo ^ type_table, EntityName,
                gcc_type_info(GCC_TypeDecl, _)) }
        ->
            { GCC_Type = gcc__declared_type(GCC_TypeDecl) }
        ;
            %
            % The type was not already defined.
            % This case only arises with `--high-level-data'.
            % For struct types which are not defined in this
            % module, it's OK to use an incomplete type,
            % since don't use such types directly, we only
            % use pointers to them.
            %
            % XXX currently we use `void' as the canonical
            % incomplete type.  Probably it would be better
            % to generate an incomplete struct type decl
            % for each struct type.
            %
            { GCC_Type = gcc__void_type_node },
            %
            % XXX The I/O code below is just for debugging,
            % and should eventually be removed
            %
            io__write_string("note: undeclared class_type "),
            io__print(EntityName),
            io__write_string(", i.e. "),
            { AsmName = build_qualified_name(EntityName) },
            io__write_string(AsmName),
            io__nl
        )
    ).
build_type(mlds_ptr_type(Type), _, GlobalInfo, GCC_PtrType) -->
    build_type(Type, GlobalInfo, GCC_Type),
    gcc__build_pointer_type(GCC_Type, GCC_PtrType).
build_type(mlds_array_type(Type), ArraySize, GlobalInfo, GCC_ArrayType) -->
    build_type(Type, GlobalInfo, GCC_Type),
    build_sized_array_type(GCC_Type, ArraySize, GCC_ArrayType).
build_type(mlds_func_type(Params), _, GlobalInfo, GCC_FuncPtrType) -->
    { Signature = mlds_get_func_signature(Params) },
    { Signature = mlds_func_signature(ArgTypes, RetTypes) },
    ( { RetTypes = [] } ->
        { GCC_RetType = gcc__void_type_node }
    ; { RetTypes = [RetType] } ->
        build_type(RetType, no_size, GlobalInfo, GCC_RetType)
    ;
        { sorry(this_file, "multiple return types") }
    ),
    build_param_types(ArgTypes, GlobalInfo, _, GCC_ParamTypes),
    gcc__build_function_type(GCC_RetType, GCC_ParamTypes, GCC_FuncType),
    gcc__build_pointer_type(GCC_FuncType, GCC_FuncPtrType).
build_type(mlds_generic_type, _, _, 'MR_Box') --> [].
build_type(mlds_generic_env_ptr_type, _, _, gcc__ptr_type_node) --> [].
build_type(mlds_type_info_type, _, _, 'MR_TypeInfo') --> [].
build_type(mlds_pseudo_type_info_type, _, _, 'MR_PseudoTypeInfo') --> [].
build_type(mlds_cont_type(ArgTypes), _, GlobalInfo, GCC_Type) -->
    % mlds_to_c treats the ArgTypes = [] case specially -- it generates
    % references to typedefs `MR_NestedCont' and `MR_Cont', which are
    % defined as follows:
    %   typedef void MR_CALL (*MR_NestedCont)(void)
    %   typedef void MR_CALL (*MR_Cont)(void *)
    % However, the generic code here works fine for those cases too,
    % i.e. it generates the same types.

    % first get the type for the environment parameter, if needed,
    globals__io_lookup_bool_option(gcc_nested_functions, GCC_NestedFuncs),
    ( { GCC_NestedFuncs = no } ->
        { GCC_ParamTypes0 = gcc__cons_param_types(gcc__ptr_type_node,
                gcc__empty_param_types) }
    ;
        { GCC_ParamTypes0 = gcc__empty_param_types }
    ),
    % then prepend the types for the other arguments
    build_param_types(ArgTypes, GlobalInfo, _GCC_Types,
        GCC_ParamTypes0, GCC_ParamTypes),
    gcc__build_function_type(gcc__void_type_node, GCC_ParamTypes, FuncType),
    gcc__build_pointer_type(FuncType, GCC_Type).
build_type(mlds_commit_type, _, _, gcc__jmpbuf_type_node) --> [].
build_type(mlds_rtti_type(RttiIdMaybeElement), InitializerSize, _GlobalInfo,
        GCC_Type) -->
    build_rtti_type(RttiIdMaybeElement, InitializerSize, GCC_Type).
build_type(mlds_tabling_type(_TablingId), _InitializerSize, _GlobalInfo,
        _GCC_Type) -->
    { sorry(this_file, "NYI: tabling in the asm backend") }.
build_type(mlds_unknown_type, _, _, _) -->
    { unexpected(this_file, "build_type: unknown type") }.

:- pred build_mercury_type(mer_type, type_ctor_category, gcc__type,
    io__state, io__state).
:- mode build_mercury_type(in, in, out, di, uo) is det.

build_mercury_type(Type, CtorCat, GCC_Type) -->
    (
        { CtorCat = ctor_cat_builtin(cat_builtin_char) },
        { GCC_Type = 'MR_Char' }
    ;
        { CtorCat = ctor_cat_builtin(cat_builtin_int) },
        { GCC_Type = 'MR_Integer' }
    ;
        { CtorCat = ctor_cat_builtin(cat_builtin_string) },
        { GCC_Type = 'MR_String' }
    ;
        { CtorCat = ctor_cat_builtin(cat_builtin_float) },
        { GCC_Type = 'MR_Float' }
    ;
        { CtorCat = ctor_cat_void },
        { GCC_Type = 'MR_Word' }
    ;
        { CtorCat = ctor_cat_system(cat_system_type_info) },
        build_mercury_type(Type, ctor_cat_user(cat_user_general),
            GCC_Type)
    ;
        { CtorCat = ctor_cat_system(cat_system_type_ctor_info) },
        build_mercury_type(Type, ctor_cat_user(cat_user_general),
            GCC_Type)
    ;
        { CtorCat = ctor_cat_system(cat_system_typeclass_info) },
        globals__io_lookup_bool_option(highlevel_data, HighLevelData),
        ( { HighLevelData = yes } ->
            { sorry(this_file,
                "--high-level-data (typeclass_info_type)") }
        ;
            { GCC_Type = 'MR_Word' }
        )
    ;
        { CtorCat = ctor_cat_system(cat_system_base_typeclass_info) },
        globals__io_lookup_bool_option(highlevel_data, HighLevelData),
        ( { HighLevelData = yes } ->
            { sorry(this_file,
                "--high-level-data (base_typeclass_info_type)") }
        ;
            { GCC_Type = 'MR_Word' }
        )
    ;
        { CtorCat = ctor_cat_variable },
        { GCC_Type = 'MR_Box' }
    ;
        { CtorCat = ctor_cat_tuple },
        % tuples are always (pointers to)
        % arrays of polymorphic terms
        gcc__build_pointer_type('MR_Box', MR_Tuple),
        { GCC_Type = MR_Tuple }
    ;
        { CtorCat = ctor_cat_higher_order },
        globals__io_lookup_bool_option(highlevel_data, HighLevelData),
        ( { HighLevelData = yes } ->
            { sorry(this_file, "--high-level-data (pred_type)") }
            % { GCC_Type = 'MR_ClosurePtr' }
        ;
            { GCC_Type = 'MR_Word' }
        )
    ;
        { CtorCat = ctor_cat_enum(_)
        ; CtorCat = ctor_cat_builtin_dummy
        },
        % Note that the MLDS -> C back-end uses 'MR_Word' here,
        % unless --high-level-data is enabled.  But 'MR_Integer'
        % seems better, I think.  It probably doesn't make any real
        % difference either way.
        % XXX for --high-level-data, we should use a real enum type
        { GCC_Type = 'MR_Integer' }
    ;
        { CtorCat = ctor_cat_user(_) },
        globals__io_lookup_bool_option(highlevel_data, HighLevelData),
        ( { HighLevelData = yes } ->
            { sorry(this_file, "--high-level-data (user_type)") }
        ;
            { GCC_Type = 'MR_Word' }
        )
    ).

:- pred build_sized_array_type(gcc__type, initializer_array_size, gcc__type,
        io__state, io__state).
:- mode build_sized_array_type(in, in, out, di, uo) is det.

build_sized_array_type(GCC_Type, ArraySize, GCC_ArrayType) -->
    { ArraySize = no_size, Size = 0
    ; ArraySize = array_size(Size)
    },
    gcc__build_array_type(GCC_Type, Size, GCC_ArrayType).

%-----------------------------------------------------------------------------%
%
% Code to build RTTI types
%

% The types constructed here should be the same as the types
% defined in runtime/mercury_type_info.h for the C back-end.
% See that file for documentation on these types.

% XXX We should consider avoiding the code duplication, by
% generating the relevant parts of runtime/mercury_type_info.h
% automatically, from a Mercury data structure describing the
% types.  The same Mercury data structure could be used here.

% XXX it would be more efficient to construct these types once,
% at initialization time, rather than every time they are used.

:- pred build_rtti_type(rtti_id_maybe_element::in, initializer_array_size::in,
    gcc__type::out, io__state::di, io__state::uo) is det.

build_rtti_type(RttiIdMaybeElement, Size, GCC_Type, !IO) :-
    (
        RttiIdMaybeElement = item_type(RttiId)
    ;
        RttiIdMaybeElement = element_type(RttiId)
    ),
    (
        RttiId = ctor_rtti_id(_, RttiName),
        build_rtti_type_name(RttiName, BaseType, !IO)
    ;
        RttiId = tc_rtti_id(_, TCRttiName),
        build_rtti_type_tc_name(TCRttiName, BaseType, !IO)
    ),
    IsArray = rtti_id_has_array_type(RttiId),
    (
        RttiIdMaybeElement = item_type(_),
        (
            IsArray = not_array,
            GCC_Type = BaseType
        ;
            IsArray = is_array,
            build_sized_array_type(BaseType, Size, GCC_Type, !IO)
        )
    ;
        RttiIdMaybeElement = element_type(_),
        expect(unify(IsArray, is_array), this_file,
            "build_rtti_type: element of non-array"),
        GCC_Type = BaseType
    ).

:- pred build_rtti_type_name(ctor_rtti_name::in, gcc__type::out,
    io__state::di, io__state::uo) is det.

build_rtti_type_name(type_ctor_exist_locns(_), GCC_Type, !IO) :-
    build_du_exist_locn_type(GCC_Type, !IO).
build_rtti_type_name(type_ctor_exist_locn, GCC_Type, !IO) :-
    build_du_exist_locn_type(GCC_Type, !IO).
build_rtti_type_name(type_ctor_exist_tc_constr(_, _, N), GCC_Type, !IO) :-
    build_tc_constr_struct_type(N, GCC_Type, !IO).
build_rtti_type_name(type_ctor_exist_tc_constrs(_), GCC_Type, !IO) :-
    build_tc_constr_type(GCC_Type, !IO).
build_rtti_type_name(type_ctor_exist_info(_), GCC_Type, !IO) :-
    build_du_exist_info_type(GCC_Type, !IO).
build_rtti_type_name(type_ctor_field_names(_), 'MR_ConstString', !IO).
build_rtti_type_name(type_ctor_field_types(_), 'MR_PseudoTypeInfo', !IO).
build_rtti_type_name(type_ctor_res_addrs, gcc__ptr_type_node, !IO).
build_rtti_type_name(type_ctor_res_addr_functors, gcc__ptr_type_node, !IO).
build_rtti_type_name(type_ctor_enum_functor_desc(_), GCC_Type, !IO) :-
    % typedef struct {
    %     MR_ConstString      MR_enum_functor_name;
    %     MR_int_least32_t    MR_enum_functor_ordinal;
    % } MR_EnumFunctorDesc;
    build_struct_type("MR_EnumFunctorDesc",
        ['MR_ConstString'   - "MR_enum_functor_name",
         'MR_int_least32_t' - "MR_enum_functor_ordinal"],
        GCC_Type, !IO).
build_rtti_type_name(type_ctor_foreign_enum_functor_desc(_), _, _, _) :-
    sorry(this_file, "NYI foreign enums and asm backend.").
build_rtti_type_name(type_ctor_notag_functor_desc, GCC_Type, !IO) :-
    % typedef struct {
    %     MR_ConstString      MR_notag_functor_name;
    %     MR_PseudoTypeInfo   MR_notag_functor_arg_type;
    %     MR_ConstString      MR_notag_functor_arg_name;
    % } MR_NotagFunctorDesc;
    build_struct_type("MR_NotagFunctorDesc",
        ['MR_ConstString'   - "MR_notag_functor_name",
         'MR_PseudoTypeInfo'    - "MR_notag_functor_arg_type",
         'MR_ConstString'   - "MR_notag_functor_arg_name"],
        GCC_Type, !IO).
build_rtti_type_name(type_ctor_du_functor_desc(_), GCC_Type, !IO) :-
    % typedef struct {
    %     MR_ConstString          MR_du_functor_name;
    %     MR_int_least16_t        MR_du_functor_orig_arity;
    %     MR_int_least16_t        MR_du_functor_arg_type_contains_var;
    %     MR_Sectag_Locn          MR_du_functor_sectag_locn;
    %     MR_int_least8_t         MR_du_functor_primary;
    %     MR_int_least32_t        MR_du_functor_secondary;
    %     MR_int_least32_t        MR_du_functor_ordinal;
    %     const MR_PseudoTypeInfo *MR_du_functor_arg_types;
    %     const MR_ConstString    *MR_du_functor_arg_names;
    %     const MR_DuExistInfo    *MR_du_functor_exist_info;
    % } MR_DuFunctorDesc;
    build_du_exist_info_type(MR_DuExistInfo, !IO),
    gcc__build_pointer_type('MR_PseudoTypeInfo', MR_PseudoTypeInfoPtr, !IO),
    gcc__build_pointer_type(MR_DuExistInfo, MR_DuExistInfoPtr, !IO),
    gcc__build_pointer_type('MR_ConstString', MR_ConstStringPtr, !IO),
    build_struct_type("MR_DuFunctorDesc",
        ['MR_ConstString'   - "MR_du_functor_name",
         'MR_int_least16_t' - "MR_du_functor_orig_arity",
         'MR_int_least16_t' - "MR_du_functor_arg_type_contains_var",
         'MR_Sectag_Locn'   - "MR_du_functor_sectag_locn",
         'MR_int_least8_t'  - "MR_du_functor_primary",
         'MR_int_least32_t' - "MR_du_functor_secondary",
         'MR_int_least32_t' - "MR_du_functor_ordinal",
         MR_PseudoTypeInfoPtr   - "MR_du_functor_arg_types",
         MR_ConstStringPtr  - "MR_du_functor_arg_names",
         MR_DuExistInfoPtr  - "MR_du_functor_exist_info"],
        GCC_Type, !IO).
build_rtti_type_name(type_ctor_res_functor_desc(_), GCC_Type, !IO) :-
    % typedef struct {
    %     MR_ConstString      MR_ra_functor_name;
    %     MR_int_least32_t    MR_ra_functor_ordinal;
    %     const void *        MR_ra_functor_reserved_addr;
    % } MR_ReservedAddrFunctorDesc;
    build_struct_type("MR_ReservedAddrFunctorDesc",
        ['MR_ConstString'   - "MR_ra_functor_name",
         'MR_int_least32_t' - "MR_ra_functor_ordinal",
         gcc__ptr_type_node - "MR_ra_functor_reserved_addr"],
        GCC_Type, !IO).
build_rtti_type_name(type_ctor_enum_name_ordered_table, gcc__ptr_type_node,
        !IO).
build_rtti_type_name(type_ctor_enum_value_ordered_table, gcc__ptr_type_node,
        !IO).
build_rtti_type_name(type_ctor_foreign_enum_name_ordered_table, 
        gcc__ptr_type_node, !IO).
build_rtti_type_name(type_ctor_foreign_enum_ordinal_ordered_table,
        gcc__ptr_type_node, !IO).
build_rtti_type_name(type_ctor_du_name_ordered_table, gcc__ptr_type_node, !IO).
build_rtti_type_name(type_ctor_du_stag_ordered_table(_), gcc__ptr_type_node,
        !IO).
build_rtti_type_name(type_ctor_du_ptag_ordered_table, GCC_Type, !IO) :-
    build_rtti_type_name(type_ctor_du_ptag_layout(0), GCC_Type, !IO).
build_rtti_type_name(type_ctor_du_ptag_layout(_), GCC_Type, !IO) :-
    % typedef struct {
    %     MR_int_least32_t        MR_sectag_sharers;
    %     MR_Sectag_Locn          MR_sectag_locn;
    %     const MR_DuFunctorDesc * const * MR_sectag_alternatives;
    % } MR_DuPtagLayout;
    build_struct_type("MR_DuPtagLayout",
        ['MR_int_least32_t' - "MR_sectag_sharers",
         'MR_Sectag_Locn'   - "MR_sectag_locn",
         gcc__ptr_type_node - "MR_sectag_alternatives"],
        GCC_Type, !IO).
build_rtti_type_name(type_ctor_res_value_ordered_table, GCC_Type, !IO) :-
    % typedef struct {
    %     MR_int_least16_t    MR_ra_num_res_numeric_addrs;
    %     MR_int_least16_t    MR_ra_num_res_symbolic_addrs;
    %     const void * const *MR_ra_res_symbolic_addrs;
    %     const MR_ReservedAddrFunctorDesc * const * MR_ra_constants;
    %     MR_DuTypeLayout     MR_ra_other_functors;
    % } MR_ReservedAddrTypeDesc;
    build_struct_type("MR_ReservedAddrTypeDesc",
        ['MR_int_least16_t' - "MR_ra_num_res_numeric_addrs",
         'MR_int_least16_t' - "MR_ra_num_res_symbolic_addrs",
         gcc__ptr_type_node - "MR_ra_res_symbolic_addrs",
         gcc__ptr_type_node - "MR_ra_constants",
         gcc__ptr_type_node - "MR_ra_other_functors"
        ], GCC_Type, !IO).
build_rtti_type_name(type_ctor_res_name_ordered_table, GCC_Type, !IO) :-
    build_rtti_type_name(type_ctor_maybe_res_addr_functor_desc, GCC_Type,
        !IO).
build_rtti_type_name(type_ctor_maybe_res_addr_functor_desc, GCC_Type, !IO) :-
    % typedef union {
        %   MR_DuFunctorDesc            *MR_maybe_res_du_ptr;
        %   MR_ReservedAddrFunctorDesc  *MR_maybe_res_res_ptr;
    % } MR_MaybeResFunctorDescPtr;
    %
    % typedef struct {
        %   MR_ConstString              MR_maybe_res_name;
        %   MR_Integer                  MR_maybe_res_arity;
        %   MR_bool                     MR_maybe_res_is_res;
        %   MR_MaybeResFunctorDescPtr   MR_maybe_res_ptr;
    % } MR_MaybeResAddrFunctorDesc;
    build_struct_type("MR_MaybeResFunctorDesc",
        [gcc__ptr_type_node - "MR_maybe_res_init"],
        MR_MaybeResFunctorDescPtr, !IO),
    build_struct_type("MR_MaybeResAddrFunctorDesc",
        ['MR_ConstString'   - "MR_maybe_res_name",
         'MR_Integer'       - "MR_maybe_res_arity",
         'MR_bool'      - "MR_maybe_res_is_res",
         MR_MaybeResFunctorDescPtr  - "MR_maybe_res_ptr"
        ], GCC_Type, !IO).
build_rtti_type_name(type_ctor_type_functors, GCC_Type, !IO) :-
    build_struct_type("MR_TypeFunctors",
        [gcc__ptr_type_node - "MR_functors_init"],
        GCC_Type, !IO).
build_rtti_type_name(type_ctor_type_layout, GCC_Type, !IO) :-
    build_struct_type("MR_TypeLayout",
        [gcc__ptr_type_node - "MR_layout_init"],
        GCC_Type, !IO).
build_rtti_type_name(type_ctor_functor_number_map, gcc__ptr_type_node,
        !IO).
build_rtti_type_name(type_ctor_type_ctor_info, GCC_Type, !IO) :-
    % MR_Integer          MR_type_ctor_arity;
    % MR_int_least8_t     MR_type_ctor_version;
    % MR_int_least8_t     MR_type_ctor_num_ptags;         /* if DU */
    % MR_TypeCtorRepInt   MR_type_ctor_rep_CAST_ME;
    % MR_ProcAddr         MR_type_ctor_unify_pred;
    % MR_ProcAddr         MR_type_ctor_compare_pred;
    % MR_ConstString      MR_type_ctor_module_name;
    % MR_ConstString      MR_type_ctor_name;
    % MR_TypeFunctors     MR_type_ctor_functors;
    % MR_TypeLayout       MR_type_ctor_layout;
    % MR_int_least32_t    MR_type_ctor_num_functors;
    % MR_int_least16_t    MR_type_ctor_flags;
    % MR_Integer *        MR_type_ctor_functor_number_map;
    build_rtti_type_name(type_ctor_type_functors, MR_TypeFunctors, !IO),
    build_rtti_type_name(type_ctor_type_layout, MR_TypeLayout, !IO),
    build_struct_type("MR_TypeCtorInfo_Struct",
        ['MR_Integer'       - "MR_type_ctor_arity",
         'MR_int_least8_t'  - "MR_type_ctor_version",
         'MR_int_least8_t'  - "MR_type_ctor_num_ptags",
         % MR_TypeCtorRepInt is typedef'd to be MR_int_least16_t
         'MR_int_least16_t' - "MR_type_ctor_rep_CAST_ME",
         'MR_ProcAddr'      - "MR_type_ctor_unify_pred",
         'MR_ProcAddr'      - "MR_type_ctor_compare_pred",
         'MR_ConstString'   - "MR_type_ctor_module_name",
         'MR_ConstString'   - "MR_type_ctor_name",
         MR_TypeFunctors    - "MR_type_ctor_functors",
         MR_TypeLayout      - "MR_type_ctor_layout",
         'MR_int_least32_t' - "MR_type_ctor_num_functors",
         'MR_int_least16_t' - "MR_type_ctor_flags",
         gcc__ptr_type_node - "MR_type_ctor_functor_number_map"],
        GCC_Type, !IO).
build_rtti_type_name(type_ctor_type_info(TypeInfo), GCC_Type, !IO) :-
    build_type_info_type(TypeInfo, GCC_Type, !IO).
build_rtti_type_name(type_ctor_pseudo_type_info(PseudoTypeInfo), GCC_Type,
        !IO) :-
    build_pseudo_type_info_type(PseudoTypeInfo, GCC_Type, !IO).
build_rtti_type_name(type_ctor_type_hashcons_pointer, gcc__ptr_type_node, !IO).

:- pred build_rtti_type_tc_name(tc_rtti_name::in, gcc__type::out,
    io__state::di, io__state::uo) is det.

build_rtti_type_tc_name(type_class_base_typeclass_info(_, _),
        gcc__ptr_type_node, !IO).
build_rtti_type_tc_name(type_class_id, GCC_Type, !IO) :-
    build_tc_id_type(GCC_Type, !IO).
build_rtti_type_tc_name(type_class_id_var_names, 'MR_ConstString', !IO).
build_rtti_type_tc_name(type_class_id_method_ids, GCC_Type, !IO) :-
    build_tc_id_method_type(GCC_Type, !IO).
build_rtti_type_tc_name(type_class_decl, GCC_Type, !IO) :-
    build_tc_decl_type(GCC_Type, !IO).
build_rtti_type_tc_name(type_class_decl_super(_, N), GCC_Type, !IO) :-
    build_tc_constr_struct_type(N, GCC_Type, !IO).
build_rtti_type_tc_name(type_class_decl_supers, GCC_Type, !IO) :-
    build_tc_constr_type(StructType, !IO),
    gcc__build_pointer_type(StructType, GCC_Type, !IO).
build_rtti_type_tc_name(type_class_instance(_), GCC_Type, !IO) :-
    build_tc_instance_type(GCC_Type, !IO).
build_rtti_type_tc_name(type_class_instance_tc_type_vector(_),
        'MR_PseudoTypeInfo', !IO).
build_rtti_type_tc_name(type_class_instance_constraint(_, _, N),
        GCC_Type, !IO) :-
    build_tc_constr_struct_type(N, GCC_Type, !IO).
build_rtti_type_tc_name(type_class_instance_constraints(_), GCC_Type, !IO) :-
    build_tc_constr_type(StructType, !IO),
    gcc__build_pointer_type(StructType, GCC_Type, !IO).
build_rtti_type_tc_name(type_class_instance_methods(_), _GCC_Type, !IO) :-
    sorry(this_file,
        "build_rtti_type_tc_name: type_class_instance_methods").

:- pred build_type_info_type(rtti_type_info::in,
    gcc__type::out, io__state::di, io__state::uo) is det.

build_type_info_type(plain_arity_zero_type_info(_), GCC_Type) -->
    build_rtti_type_name(type_ctor_type_ctor_info, GCC_Type).
build_type_info_type(plain_type_info(_TypeCtor, ArgTypes),
        GCC_Type) -->
    { Arity = list__length(ArgTypes) },
    % typedef struct {
    %     MR_TypeCtorInfo  MR_ti_type_ctor_info;
    %     MR_TypeInfo      MR_ti_fixed_arity_arg_typeinfos[<ARITY>];
    % } MR_FA_TypeInfo_Struct<ARITY>;
    { MR_TypeCtorInfo = gcc__ptr_type_node },
    gcc__build_array_type('MR_TypeInfo', Arity, MR_TypeInfoArray),
    { StructName = string__format("MR_FA_TypeInfo_Struct%d",
        [i(Arity)]) },
    build_struct_type(StructName,
        [MR_TypeCtorInfo    - "MR_ti_type_ctor_info",
         MR_TypeInfoArray   - "MR_ti_fixed_arity_arg_typeinfos"],
        GCC_Type).
build_type_info_type(var_arity_type_info(_VarArityTypeId, ArgTypes), GCC_Type)
        -->
    { Arity = list__length(ArgTypes) },
    % struct NAME {
    %    MR_TypeCtorInfo    MR_ti_type_ctor_info;
    %    MR_Integer         MR_ti_var_arity_arity;
    %    MR_TypeInfo    MR_ti_var_arity_arg_typeinfos[ARITY];
    % }
    { MR_TypeCtorInfo = gcc__ptr_type_node },
    gcc__build_array_type('MR_TypeInfo', Arity, MR_TypeInfoArray),
    { StructName = string__format("MR_VA_TypeInfo_Struct%d",
        [i(Arity)]) },
    build_struct_type(StructName,
        [MR_TypeCtorInfo    - "MR_ti_type_ctor_info",
         'MR_Integer'       - "MR_ti_var_arity_arity",
         MR_TypeInfoArray   - "MR_ti_var_arity_arg_typeinfos"],
        GCC_Type).

:- pred build_pseudo_type_info_type(rtti_pseudo_type_info::in,
        gcc__type::out, io__state::di, io__state::uo) is det.

build_pseudo_type_info_type(type_var(_), _) -->
    % we use small integers to represent type_vars,
    % rather than pointers, so there is no pointed-to type
    { unexpected(this_file, "mlds_rtti_type: type_var") }.
build_pseudo_type_info_type(plain_arity_zero_pseudo_type_info(_), GCC_Type) -->
    build_rtti_type_name(type_ctor_type_ctor_info, GCC_Type).
build_pseudo_type_info_type(plain_pseudo_type_info(_TypeCtor, ArgTypes),
        GCC_Type) -->
    { Arity = list__length(ArgTypes) },
    % typedef struct {
    %     MR_TypeCtorInfo     MR_pti_type_ctor_info;
    %     MR_PseudoTypeInfo   MR_pti_fixed_arity_arg_pseudo_typeinfos[<ARITY>];
    % } MR_FA_PseudoTypeInfo_Struct<ARITY>;
    { MR_TypeCtorInfo = gcc__ptr_type_node },
    gcc__build_array_type('MR_PseudoTypeInfo', Arity,
        MR_PseudoTypeInfoArray),
    { StructName = string__format("MR_FA_PseudoTypeInfo_Struct%d",
        [i(Arity)]) },
    build_struct_type(StructName,
        [MR_TypeCtorInfo    - "MR_pti_type_ctor_info",
         MR_PseudoTypeInfoArray - "MR_pti_fixed_arity_arg_pseudo_typeinfos"],
        GCC_Type).
build_pseudo_type_info_type(var_arity_pseudo_type_info(_VarArityTypeId,
        ArgTypes), GCC_Type) -->
    { Arity = list__length(ArgTypes) },
    % struct NAME {
    %    MR_TypeCtorInfo    MR_pti_type_ctor_info;
    %    MR_Integer         MR_pti_var_arity_arity;
    %    MR_PseudoTypeInfo  MR_pti_var_arity_arg_pseudo_typeinfos[ARITY];
    % }
    { MR_TypeCtorInfo = gcc__ptr_type_node },
    gcc__build_array_type('MR_PseudoTypeInfo', Arity,
        MR_PseudoTypeInfoArray),
    { StructName = string__format("MR_VA_PseudoTypeInfo_Struct%d",
        [i(Arity)]) },
    build_struct_type(StructName,
        [MR_TypeCtorInfo    - "MR_pti_type_ctor_info",
         'MR_Integer'       - "MR_pti_var_arity_arity",
         MR_PseudoTypeInfoArray -
                "MR_pti_var_arity_arg_pseudo_typeinfos"],
        GCC_Type).

:- pred build_tc_constr_struct_type(int::in, gcc__type::out,
    io__state::di, io__state::uo) is det.

build_tc_constr_struct_type(N, MR_TypeClassConstraint_NStruct) -->
    % typedef struct MR_TypeClassConstraint_NStruct{
    %    MR_TypeClassDecl    MR_tc_constr_type_class;
    %    MR_PseudoTypeInfo   MR_tc_constr_arg_ptis[Arity];
    % } MR_TypeClassConstraint_N;
    gcc__build_array_type('MR_PseudoTypeInfo', N, MR_PseudoTypeInfoArray),
    build_tc_decl_type(MR_TypeClassDecl),
    gcc__build_pointer_type(MR_TypeClassDecl, MR_TypeClassDeclPtr),
    { StructName = string__format("MR_TypeClassConstraint_%dStruct",
        [i(N)]) },
    build_struct_type(StructName,
        [MR_TypeClassDeclPtr    - "MR_tc_constr_type_class",
         MR_PseudoTypeInfoArray - "MR_tc_constr_arg_ptis"],
        MR_TypeClassConstraint_NStruct).

:- pred build_tc_constr_type(gcc__type::out, io__state::di, io__state::uo)
    is det.

build_tc_constr_type(MR_TypeClassConstraint) -->
    build_tc_constr_struct_type(5, MR_TypeClassConstraint5Struct),
    gcc__build_pointer_type(MR_TypeClassConstraint5Struct,
        MR_TypeClassConstraint).

:- pred build_tc_id_method_type(gcc__type::out, io__state::di, io__state::uo)
    is det.

build_tc_id_method_type(MR_TypeClassMethod) -->
    % typedef struct {
    %    MR_ConstString              MR_tc_method_name;
    %    const MR_int_least8_t       MR_tc_method_arity;
    %    const MR_PredFunc           MR_tc_method_pred_func;
    % } MR_TypeClassMethod;
    build_struct_type("MR_TypeClassMethod",
        ['MR_ConstString'   - "MR_tc_method_name",
         'MR_int_least8_t'  - "MR_tc_method_arity",
         'MR_PredFunc'      - "MR_tc_method_pred_func"],
        MR_TypeClassMethod).

:- pred build_tc_id_type(gcc__type::out, io__state::di, io__state::uo)
    is det.

build_tc_id_type(MR_TypeClassId) -->
    % typedef struct {
    %    MR_ConstString              MR_tc_id_module_name;
    %    MR_ConstString              MR_tc_id_name;
    %    const MR_int_least8_t       MR_tc_id_arity;
    %    const MR_int_least8_t       MR_tc_id_num_type_vars;
    %    const MR_int_least16_t      MR_tc_id_num_methods;
    %    const MR_ConstString        *MR_tc_id_type_var_names;
    %    const MR_TypeClassMethod    *MR_tc_id_methods;
    % } MR_TypeClassId;
    gcc__build_pointer_type('MR_ConstString', MR_ConstStringPtr),
    build_tc_id_method_type(MR_TypeClassMethod),
    gcc__build_pointer_type(MR_TypeClassMethod, MR_TypeClassMethodPtr),
    build_struct_type("MR_TypeClassId",
        ['MR_ConstString'   - "MR_tc_id_module_name",
         'MR_ConstString'   - "MR_tc_id_name",
         'MR_int_least8_t'  - "MR_tc_id_arity",
         'MR_int_least8_t'  - "MR_tc_id_num_type_vars",
         'MR_int_least16_t' - "MR_tc_id_num_methods",
         MR_ConstStringPtr  - "MR_tc_id_type_var_names",
         MR_TypeClassMethodPtr  - "MR_tc_id_methods"],
        MR_TypeClassId).

:- pred build_tc_decl_type(gcc__type::out, io__state::di, io__state::uo)
    is det.

build_tc_decl_type(MR_TypeClassDecl) -->
    % struct MR_TypeClassDecl_Struct {
    %    const MR_TypeClassId            *MR_tc_decl_id;
    %    const MR_int_least8_t           MR_tc_decl_version_number;
    %    const MR_int_least8_t           MR_tc_decl_num_supers;
    %    const MR_TypeClassConstraint    *MR_tc_decl_supers;
    % };
    build_du_exist_locn_type(MR_TypeClassId),
    gcc__build_pointer_type(MR_TypeClassId, MR_TypeClassIdPtr),
    build_tc_constr_type(MR_TypeClassConstraint),
    gcc__build_pointer_type(MR_TypeClassConstraint,
        MR_TypeClassConstraintPtr),
    build_struct_type("MR_TypeClassDeclStruct",
        [MR_TypeClassIdPtr  - "MR_tc_decl_id",
         'MR_int_least8_t'  - "MR_tc_decl_version_number",
         'MR_int_least8_t'  - "MR_tc_decl_num_supers",
         MR_TypeClassConstraintPtr - "MR_tc_decl_supers"],
        MR_TypeClassDecl).

:- pred build_tc_instance_type(gcc__type::out, io__state::di, io__state::uo)
    is det.

build_tc_instance_type(MR_Instance) -->
    % struct MR_Instance_Struct {
    %    const MR_TypeClassDecl        MR_tc_inst_type_class;
    %    const MR_int_least8_t         MR_tc_inst_num_type_vars;
    %    const MR_int_least8_t     MR_tc_inst_num_instance_constraints;
    %    const MR_PseudoTypeInfo       *MR_tc_inst_type_args;
    %    const MR_TypeClassConstraint  *MR_tc_inst_instance_constraints;
    %    const MR_CodePtr              MR_tc_inst_methods;
    % };
    build_tc_decl_type(MR_TypeClassDecl),
    gcc__build_pointer_type(MR_TypeClassDecl, MR_TypeClassDeclPtr),
    gcc__build_pointer_type('MR_PseudoTypeInfo', MR_PseudoTypeInfoPtr),
    build_tc_constr_type(MR_TypeClassConstraint),
    gcc__build_pointer_type(MR_TypeClassConstraint,
        MR_TypeClassConstraintPtr),
    build_struct_type("MR_Instance",
        [MR_TypeClassDeclPtr    - "MR_tc_inst_type_class",
         'MR_int_least8_t'  - "MR_tc_inst_num_type_vars",
         'MR_int_least8_t'  - "MR_tc_inst_num_instance_constraints",
         'MR_int_least8_t'  - "MR_tc_decl_num_supers",
         MR_PseudoTypeInfoPtr   - "MR_tc_inst_type_args",
         MR_TypeClassConstraintPtr - "MR_tc_inst_instance_constraints"],
        MR_Instance).

:- pred build_du_exist_locn_type(gcc__type, io__state, io__state).
:- mode build_du_exist_locn_type(out, di, uo) is det.

build_du_exist_locn_type(MR_DuExistLocn) -->
    % typedef struct {
    %    MR_int_least16_t    MR_exist_arg_num;
    %    MR_int_least16_t    MR_exist_offset_in_tci;
    % } MR_DuExistLocn;
    build_struct_type("MR_DuExistLocn",
        ['MR_int_least16_t' - "MR_exist_arg_num",
         'MR_int_least16_t' - "MR_exist_offset_in_tci"],
        MR_DuExistLocn).

:- pred build_du_exist_info_type(gcc__type, io__state, io__state).
:- mode build_du_exist_info_type(out, di, uo) is det.

build_du_exist_info_type(MR_DuExistInfo) -->
    % typedef struct {
    %     MR_int_least16_t        MR_exist_typeinfos_plain;
    %     MR_int_least16_t        MR_exist_typeinfos_in_tci;
    %     MR_int_least16_t        MR_exist_tcis;
    %     const MR_DuExistLocn    *MR_exist_typeinfo_locns;
    % } MR_DuExistInfo;
    build_du_exist_locn_type(MR_DuExistLocn),
    gcc__build_pointer_type(MR_DuExistLocn, MR_DuExistLocnPtr),
    build_struct_type("MR_DuExistInfo",
        ['MR_int_least16_t' - "MR_exist_typeinfos_plain",
         'MR_int_least16_t' - "MR_exist_typeinfos_in_tci",
         'MR_int_least16_t' - "MR_exist_tcis",
         MR_DuExistLocnPtr  - "MR_exist_typeinfo_locns"],
        MR_DuExistInfo).

    % rtti_enum_const(Name, Value):
    %   Succeed iff Name is the name of an RTTI
    %   enumeration constant whose integer value is Value.
    %   The values here must match the definitions of the
    %   MR_TypeCtor and MR_Sectag_Locn enumerations in
    %   runtime/mercury_type_info.h.
:- pred rtti_enum_const(string::in, int::out) is semidet.

rtti_enum_const("MR_TYPECTOR_REP_ENUM", 0).
rtti_enum_const("MR_TYPECTOR_REP_ENUM_USEREQ", 1).
rtti_enum_const("MR_TYPECTOR_REP_DU", 2).
rtti_enum_const("MR_TYPECTOR_REP_DU_USEREQ", 3).
rtti_enum_const("MR_TYPECTOR_REP_NOTAG", 4).
rtti_enum_const("MR_TYPECTOR_REP_NOTAG_USEREQ", 5).
rtti_enum_const("MR_TYPECTOR_REP_EQUIV", 6).
rtti_enum_const("MR_TYPECTOR_REP_FUNC", 7).
rtti_enum_const("MR_TYPECTOR_REP_INT", 8).
rtti_enum_const("MR_TYPECTOR_REP_CHAR", 9).
rtti_enum_const("MR_TYPECTOR_REP_FLOAT", 10).
rtti_enum_const("MR_TYPECTOR_REP_STRING", 11).
rtti_enum_const("MR_TYPECTOR_REP_PRED", 12).
rtti_enum_const("MR_TYPECTOR_REP_SUBGOAL", 13).
rtti_enum_const("MR_TYPECTOR_REP_VOID", 14).
rtti_enum_const("MR_TYPECTOR_REP_C_POINTER", 15).
rtti_enum_const("MR_TYPECTOR_REP_TYPEINFO", 16).
rtti_enum_const("MR_TYPECTOR_REP_TYPECLASSINFO", 17).
rtti_enum_const("MR_TYPECTOR_REP_ARRAY", 18).
rtti_enum_const("MR_TYPECTOR_REP_SUCCIP", 19).
rtti_enum_const("MR_TYPECTOR_REP_HP", 20).
rtti_enum_const("MR_TYPECTOR_REP_CURFR", 21).
rtti_enum_const("MR_TYPECTOR_REP_MAXFR", 22).
rtti_enum_const("MR_TYPECTOR_REP_REDOFR", 23).
rtti_enum_const("MR_TYPECTOR_REP_REDOIP", 24).
rtti_enum_const("MR_TYPECTOR_REP_TRAIL_PTR", 25).
rtti_enum_const("MR_TYPECTOR_REP_TICKET", 26).
rtti_enum_const("MR_TYPECTOR_REP_NOTAG_GROUND", 27).
rtti_enum_const("MR_TYPECTOR_REP_NOTAG_GROUND_USEREQ", 28).
rtti_enum_const("MR_TYPECTOR_REP_EQUIV_GROUND", 29).
rtti_enum_const("MR_TYPECTOR_REP_TUPLE", 30).
rtti_enum_const("MR_TYPECTOR_REP_RESERVED_ADDR", 31).
rtti_enum_const("MR_TYPECTOR_REP_RESERVED_ADDR_USEREQ", 32).
rtti_enum_const("MR_TYPECTOR_REP_TYPECTORINFO", 33).
rtti_enum_const("MR_TYPECTOR_REP_BASETYPECLASSINFO", 34).
rtti_enum_const("MR_TYPECTOR_REP_TYPEDESC", 35).
rtti_enum_const("MR_TYPECTOR_REP_TYPECTORDESC", 36).
rtti_enum_const("MR_TYPECTOR_REP_FOREIGN", 37).
rtti_enum_const("MR_TYPECTOR_REP_REFERENCE", 38).
rtti_enum_const("MR_TYPECTOR_REP_STABLE_C_POINTER", 39).
rtti_enum_const("MR_TYPECTOR_REP_STABLE_FOREIGN", 40).
rtti_enum_const("MR_TYPECTOR_REP_PSEUDOTYPEDESC", 41).
rtti_enum_const("MR_TYPECTOR_REP_DUMMY", 42).
rtti_enum_const("MR_TYPECTOR_REP_BITMAP", 43).
rtti_enum_const("MR_TYPECTOR_REP_UNKNOWN", 44).
rtti_enum_const("MR_SECTAG_NONE", 0).
rtti_enum_const("MR_SECTAG_LOCAL", 1).
rtti_enum_const("MR_SECTAG_REMOTE", 2).
rtti_enum_const("MR_SECTAG_VARIABLE", 3).
rtti_enum_const("MR_PREDICATE", 0).
rtti_enum_const("MR_FUNCTION", 1).

:- pred build_struct_type(gcc__struct_name::in,
        list(pair(gcc__type, gcc__field_name))::in,
        gcc__type::out, io__state::di, io__state::uo) is det.

build_struct_type(StructName, Fields, GCC_Type) -->
    build_fields(Fields, GCC_Fields),
    gcc__build_struct_type_decl(StructName, GCC_Fields, GCC_TypeDecl),
    { GCC_Type = gcc__declared_type(GCC_TypeDecl) }.

:- pred build_fields(list(pair(gcc__type, gcc__field_name))::in,
        gcc__field_decls::out, io__state::di, io__state::uo) is det.

build_fields([], GCC_Fields) -->
    gcc__empty_field_list(GCC_Fields).
build_fields([Type - Name | Fields0], GCC_Fields) -->
    build_fields(Fields0, GCC_Fields0),
    gcc__build_field_decl(Name, Type, FieldDecl),
    gcc__cons_field_list(FieldDecl, GCC_Fields0, GCC_Fields).

%-----------------------------------------------------------------------------%
%
% Code to output names of various entities
%

:- func build_qualified_name(mlds_qualified_entity_name) = string.

build_qualified_name(QualifiedName) = AsmName :-
    QualifiedName = qual(_ModuleName, _QualKind, Name),
    AsmName0 = build_name(Name),
    maybe_add_module_qualifier(QualifiedName, AsmName0, AsmName).

:- pred maybe_add_module_qualifier(mlds_qualified_entity_name::in,
        string::in, string::out) is det.
maybe_add_module_qualifier(QualifiedName, AsmName0, AsmName) :-
    QualifiedName = qual(ModuleName, _QualKind, Name),
    (
        (
            %
            % don't module-qualify main/2
            %
            Name = entity_function(PredLabel, _, _, _),
            PredLabel = mlds_user_pred_label(pf_predicate, no,
                "main", 2, model_det, no)
        ;
            Name = entity_data(mlds_rtti(RttiId)),
            module_qualify_name_of_rtti_id(RttiId) = no
        ;
            % We don't module qualify pragma export names.
            Name = entity_export(_)
        )
    ->
        AsmName = AsmName0
    ;
        ModuleSymName = mlds_module_name_to_sym_name(ModuleName),
        AsmName = string__format("%s__%s",
            [s(get_module_name(ModuleSymName)), s(AsmName0)])
    ).

% XXX we should consider not appending the arity, modenum, and seqnum
%     if they are not needed.

:- func build_name(mlds_entity_name) = string.

build_name(entity_type(Name, Arity)) = TypeName :-
    MangledName = name_mangle(Name),
    TypeName = string__format("%s_%d", [s(MangledName), i(Arity)]).
build_name(entity_data(DataName)) = build_data_name(DataName).
build_name(EntityName) = AsmFuncName :-
    EntityName = entity_function(_, _, _, _),
    get_func_name(EntityName, _FuncName, AsmFuncName).
build_name(entity_export(Name)) = Name.

:- func build_data_name(mlds_data_name) = string.

build_data_name(mlds_data_var(Name)) =
    name_mangle(ml_var_name_to_string(Name)).
build_data_name(mlds_scalar_common_ref(_)) =
    sorry(this_file, "mlds_scalar_common_ref").
build_data_name(mlds_rtti(RttiId0)) = RttiAddrName :-
    RttiId = fixup_rtti_id(RttiId0),
    rtti__id_to_c_identifier(RttiId, RttiAddrName).
build_data_name(mlds_module_layout) = _ :-
    sorry(this_file, "mlds_module_layout").
build_data_name(mlds_proc_layout(_ProcLabel)) = _ :-
    sorry(this_file, "mlds_proc_layout").
build_data_name(mlds_internal_layout(_ProcLabel, _FuncSeqNum)) = _ :-
    sorry(this_file, "mlds_internal_layout").
build_data_name(mlds_tabling_ref(ProcLabel, Id)) = TablingPointerName :-
    % convert the proc_label into an entity_name,
    % so we can use get_func_name below
    ProcLabel = mlds_proc_label(PredLabel, ProcId),
    MaybeSeqNum = no,
    Name = entity_function(PredLabel, ProcId, MaybeSeqNum, invalid_pred_id),
    get_func_name(Name, _FuncName, AsmFuncName),
    TablingPointerName = tabling_info_id_str(Id) ++ "_" ++ AsmFuncName.

:- func fixup_rtti_id(rtti_id) = rtti_id.

fixup_rtti_id(ctor_rtti_id(RttiTypeCtor0, RttiName0))
        = ctor_rtti_id(RttiTypeCtor, RttiName) :-
    RttiTypeCtor = fixup_rtti_type_ctor(RttiTypeCtor0),
    RttiName = fixup_rtti_name(RttiName0).
fixup_rtti_id(tc_rtti_id(TCName, TCRttiName)) = tc_rtti_id(TCName, TCRttiName).

    % XXX sometimes earlier stages of the compiler forget to add
    % the appropriate qualifiers for stuff in the `builtin' module;
    % we fix that here.
:- func fixup_rtti_type_ctor(rtti_type_ctor) = rtti_type_ctor.

fixup_rtti_type_ctor(RttiTypeCtor0) = RttiTypeCtor :-
    (
        RttiTypeCtor0 = rtti_type_ctor(ModuleName0, Name, Arity),
        ModuleName0 = unqualified("")
    ->
        ModuleName = unqualified("builtin"),
        RttiTypeCtor = rtti_type_ctor(ModuleName, Name, Arity)
    ;
        RttiTypeCtor = RttiTypeCtor0
    ).

:- func fixup_rtti_name(ctor_rtti_name) = ctor_rtti_name.

fixup_rtti_name(RttiTypeCtor0) = RttiTypeCtor :-
    (
        RttiTypeCtor0 = type_ctor_pseudo_type_info(PseudoTypeInfo)
    ->
        RttiTypeCtor = type_ctor_pseudo_type_info(
            fixup_pseudo_type_info(PseudoTypeInfo))
    ;
        RttiTypeCtor = RttiTypeCtor0
    ).

:- func fixup_pseudo_type_info(rtti_pseudo_type_info) = rtti_pseudo_type_info.
fixup_pseudo_type_info(PseudoTypeInfo0) = PseudoTypeInfo :-
    (
        PseudoTypeInfo0 =
            plain_arity_zero_pseudo_type_info(RttiTypeCtor0)
    ->
        PseudoTypeInfo = plain_arity_zero_pseudo_type_info(
            fixup_rtti_type_ctor(RttiTypeCtor0))
    ;
        PseudoTypeInfo = PseudoTypeInfo0
    ).

%-----------------------------------------------------------------------------%
%
% Symbol tables and other (semi-)global data structures
%

:- type global_info
    --->    global_info(
            type_table :: gcc_type_table,
            global_vars :: symbol_table
        ).

% The type field table records the mapping from MLDS type names
% to the table of field declarations for that type.
:- type gcc_type_table == map(mlds_qualified_entity_name, gcc_type_info).
:- type gcc_type_info ---> gcc_type_info(gcc__type_decl, field_table).

% The field table records the mapping from MLDS field names
% to GCC field declarations.
:- type field_table ==
    map(mlds_fully_qualified_name(mlds_field_name), gcc.field_decl).

% The defn_info holds information used while generating code
% inside a function, or in the initializers for a global variable.
:- type defn_info
    --->    defn_info(
            global_info :: global_info,
            func_name :: mlds_qualified_entity_name,
            local_vars :: symbol_table,
            label_table :: label_table
        ).

% The symbol table records the mapping from MLDS variable names
% to GCC variable declarations.
% We initialize the symbol table with the function parameters,
% and update it whenever we enter a block with local variables.
:- type symbol_table == map(mlds_qualified_entity_name, gcc__var_decl).

% The label table records the mapping from MLDS label names
% to GCC label declaration tree nodes.
% We initialize it using a separate pass over the function body
% before we generate code for the function.
:- type label_table == map(mlds_label, gcc__label).

%-----------------------------------------------------------------------------%
%
% Code to output statements
%

:- pred gen_statements(defn_info, list(statement),
        io__state, io__state).
:- mode gen_statements(in, in, di, uo) is det.

gen_statements(DefnInfo, Statements) -->
    list__foldl(gen_statement(DefnInfo), Statements).

:- pred gen_statement(defn_info, statement,
        io__state, io__state).
:- mode gen_statement(in, in, di, uo) is det.

gen_statement(DefnInfo, statement(Statement, Context)) -->
    gen_context(Context),
    gen_stmt(DefnInfo, Statement, Context).

:- pred gen_stmt(defn_info, mlds_stmt, mlds_context,
        io__state, io__state).
:- mode gen_stmt(in, in, in, di, uo) is det.

    %
    % sequence
    %
gen_stmt(DefnInfo0, ml_stmt_block(Defns, Statements), _Context) -->
    gcc__start_block,
    { FuncName = DefnInfo0 ^ func_name },
    { FuncName = qual(ModuleName, _, _) },
    build_local_defns(Defns, ModuleName, DefnInfo0, DefnInfo),
    gen_statements(DefnInfo, Statements),
    gcc__end_block.

    %
    % iteration
    %
gen_stmt(DefnInfo, ml_stmt_while(Cond, Statement, AtLeastOneIteration),
        _Context) -->
    gcc__gen_start_loop(Loop),
    build_rval(Cond, DefnInfo, GCC_Cond),
    (
        { AtLeastOneIteration = yes },
        % generate the test at the end of the loop
        gen_statement(DefnInfo, Statement),
        gcc__gen_exit_loop_if_false(Loop, GCC_Cond)
    ;
        { AtLeastOneIteration = no },
        % generate the test at the start of the loop
        gcc__gen_exit_loop_if_false(Loop, GCC_Cond),
        gen_statement(DefnInfo, Statement)
    ),
    gcc__gen_end_loop.

    %
    % selection (see also computed_goto)
    %
gen_stmt(DefnInfo, ml_stmt_if_then_else(Cond, Then, MaybeElse), _Context) -->
    build_rval(Cond, DefnInfo, GCC_Cond),
    gcc__gen_start_cond(GCC_Cond),
    gen_statement(DefnInfo, Then),
    (
        { MaybeElse = no }
    ;
        { MaybeElse = yes(Else) },
        gcc__gen_start_else,
        gen_statement(DefnInfo, Else)
    ),
    gcc__gen_end_cond.
gen_stmt(DefnInfo, ml_stmt_switch(Type, Val, Range, Cases, Default), _) -->
    build_type(Type, DefnInfo ^ global_info, GCC_Type),
    ( { Range = mlds_switch_range(Min, Max) } ->
        gcc__build_range_type(GCC_Type, Min, Max, GCC_RangeType)
    ;
        { GCC_RangeType = GCC_Type }
    ),
    build_rval(Val, DefnInfo, GCC_Expr),
    gcc__gen_start_switch(GCC_Expr, GCC_RangeType),
    % we put the default case first, so that if it is unreachable,
    % it will get merged in with the first case.
    gen_default(DefnInfo, Default),
    gen_cases(DefnInfo, Cases),
    gcc__gen_end_switch(GCC_Expr).

    %
    % transfer of control
    %
gen_stmt(DefnInfo, ml_stmt_label(LabelName), _) -->
    { LabelTable = DefnInfo ^ label_table },
    { GCC_Label = map__lookup(LabelTable, LabelName) },
    gcc__gen_label(GCC_Label).
gen_stmt(DefnInfo, ml_stmt_goto(goto_label(LabelName)), _) -->
    { LabelTable = DefnInfo ^ label_table },
    { GCC_Label = map__lookup(LabelTable, LabelName) },
    gcc__gen_goto(GCC_Label).
gen_stmt(_DefnInfo, ml_stmt_goto(goto_break), _) -->
    gcc__gen_break.
gen_stmt(_DefnInfo, ml_stmt_goto(goto_continue), _) -->
    % XXX not yet implemented
    % but we set target_supports_break_and_continue to no
    % for this target, so we shouldn't get any
    { unexpected(this_file, "continue") }.
gen_stmt(_DefnInfo, ml_stmt_computed_goto(_Expr, _Labels), _) -->
    % XXX not yet implemented
    % but we set target_supports_computed_goto to no
    % for this target, so we shouldn't get any
    { unexpected(this_file, "computed goto") }.

    %
    % function call/return
    %
gen_stmt(DefnInfo, Call, _) -->
    { Call = ml_stmt_call(_Signature, FuncRval, MaybeObject, CallArgs,
        Results, CallKind) },
    { expect(unify(MaybeObject, no), this_file, "method call") },
    build_args(CallArgs, DefnInfo, GCC_ArgList),
    build_rval(FuncRval, DefnInfo, GCC_FuncRval),
    {
        CallKind = no_return_call,
        % XXX trying to optimize these leads to
        % problems because we don't mark such calls
        % with __attribute__((__noreturn__)) and so
        % GCC thinks that they are not in a tail position.
        % Marking them as with __attribute__((__noreturn__))
        % doesn't help because GCC (3.3 beta) inhibits tail
        % call optimization for such functions.
        % Also, we can't insert a return statement (below)
        % if the return type for the caller doesn't match
        % that for the callee, but mlds_to_gcc.m currently doesn't
        % pass down the signature of the caller to this point.
        % So for now, treat these as if they were not tail calls.
        IsTailCall = no
    ;
        CallKind = tail_call,
        IsTailCall = yes
    ;
        CallKind = ordinary_call,
        IsTailCall = no
    },
    gcc__build_call_expr(GCC_FuncRval, GCC_ArgList, IsTailCall, GCC_Call),
    ( { Results = [ResultLval] } ->
        ( { IsTailCall = yes } ->
            gcc__gen_return(GCC_Call)
        ;
            build_lval(ResultLval, DefnInfo, GCC_ResultExpr),
            gcc__gen_assign(GCC_ResultExpr, GCC_Call)
        )
    ; { Results = [] } ->
        gcc__gen_expr_stmt(GCC_Call)
    ;
        { sorry(this_file, "call with multiple outputs") }
    ).
gen_stmt(DefnInfo, ml_stmt_return(Results), _) -->
    ( { Results = [] } ->
        % XXX Not yet implemented
        % These are not generated by the current MLDS code
        % generator, so I didn't bother to implement them.
        { sorry(this_file, "gen_stmt: return without return value") }
    ; { Results = [Rval] } ->
        build_rval(Rval, DefnInfo, Expr),
        gcc__gen_return(Expr)
    ;
        { sorry(this_file, "gen_stmt: multiple return values") }
    ).

    %
    % commits
    %
gen_stmt(DefnInfo, ml_stmt_do_commit(Ref), _Context) -->
    % generate `__builtin_longjmp(&<Ref>, 1);'
    { Ref = ml_lval(RefLval0) ->
        RefLval = RefLval0
    ;
        unexpected(this_file, "non-lval argument to do_commit")
    },
    build_call(gcc__longjmp_func_decl,
        [ml_mem_addr(RefLval), ml_const(mlconst_int(1))],
        DefnInfo, GCC_CallLongjmp),
    gcc__gen_expr_stmt(GCC_CallLongjmp).
gen_stmt(DefnInfo, ml_stmt_try_commit(Ref, Stmt, Handler), _) -->
    %
    % Generate the following:
    %
    %   if (__builtin_setjmp(&<Ref>) == 0)
    %               <Stmt>
    %       else
    %               <Handler>
    %
    build_call(gcc__setjmp_func_decl, [ml_mem_addr(Ref)], DefnInfo,
        GCC_CallSetjmp),
    gcc__build_int(0, GCC_Zero),
    gcc__build_binop(gcc__eq_expr, gcc__boolean_type_node,
        GCC_CallSetjmp, GCC_Zero, GCC_SetjmpEqZero),
    gcc__gen_start_cond(GCC_SetjmpEqZero),
    gen_statement(DefnInfo, Stmt),
    gcc__gen_start_else,
    gen_statement(DefnInfo, Handler),
    gcc__gen_end_cond.

    %
    % exception handling
    %
/* XXX MLDS exception handling not yet implemented */

    %
    % atomic statements
    %
gen_stmt(DefnInfo, ml_stmt_atomic(AtomicStatement), Context) -->
    gen_atomic_stmt(DefnInfo, AtomicStatement, Context).

%-----------------------------------------------------------------------------%

%
% Extra code for outputting switch statements
%

:- pred gen_cases(defn_info::in, list(mlds_switch_case)::in,
    io__state::di, io__state::uo) is det.

gen_cases(DefnInfo, Cases) -->
    list__foldl(gen_case(DefnInfo), Cases).

:- pred gen_case(defn_info::in, mlds_switch_case::in,
        io__state::di, io__state::uo) is det.
gen_case(DefnInfo, mlds_switch_case(FirstCond, LaterConds, Code)) -->
    gen_case_label(DefnInfo, FirstCond),
    list__foldl(gen_case_label(DefnInfo), LaterConds),
    gen_statement(DefnInfo, Code),
    gcc__gen_break.

:- pred gen_case_label(defn_info::in, mlds_case_match_cond::in,
        io__state::di, io__state::uo) is det.
gen_case_label(DefnInfo, match_value(Val)) -->
    build_rval(Val, DefnInfo, GCC_Val),
    gcc__build_unnamed_label(Label),
    gcc__gen_case_label(GCC_Val, Label).
gen_case_label(DefnInfo, match_range(Min, Max)) -->
    build_rval(Min, DefnInfo, _GCC_Min),
    build_rval(Max, DefnInfo, _GCC_Max),
    gcc__build_unnamed_label(_Label),
    % the following is not yet implemented
    % (would be easy to do, but not needed so far, since
    % these are not generated by the current MLDS code generator)
    %%% gcc__gen_case_range_label(GCC_Min, GCC_Max, Label).
    { sorry(this_file, "match_range") }.

:- pred gen_default(defn_info::in, mlds_switch_default::in,
        io__state::di, io__state::uo) is det.
gen_default(_, default_do_nothing) --> [].
gen_default(_, default_is_unreachable) -->
    % If the default is unreachable, we just generate a label
    % which will just drop through into the first case.
    % This generally leads to more efficient code than
    % default_do_nothing.
    gcc__build_unnamed_label(Label),
    gcc__gen_default_case_label(Label).
gen_default(DefnInfo, default_case(Statement)) -->
    gcc__build_unnamed_label(Label),
    gcc__gen_default_case_label(Label),
    gen_statement(DefnInfo, Statement),
    gcc__gen_break.

%-----------------------------------------------------------------------------%

/**********
XXX Profiling is not yet implemented for mlds_to_gcc.m.
The following code for handling profiling is copied from
mlds_to_c.m.  It shows what we should generate.

    %
    % If memory profiling is turned on output an instruction to
    % record the heap allocation.
    %
:- pred mlds_maybe_output_heap_profile_instr(mlds_context::in,
        indent::in, list(mlds_rval)::in,
        mlds_qualified_entity_name::in, maybe(ctor_name)::in,
        io__state::di, io__state::uo) is det.

mlds_maybe_output_heap_profile_instr(Context, Indent, Args, FuncName,
        MaybeCtorName) -->
    globals__io_lookup_bool_option(profile_memory, ProfileMem),
    (
        { ProfileMem = yes }
    ->
        mlds_indent(Context, Indent),
        io__write_string("MR_record_allocation("),
        io__write_int(list__length(Args)),
        io__write_string(", "),
        mlds_output_fully_qualified_name(FuncName),
        io__write_string(", """),
        mlds_output_fully_qualified_name(FuncName),
        io__write_string(""", "),
        ( { MaybeCtorName = yes(CtorName) } ->
            io__write_char('"'),
            c_util__output_quoted_string(CtorName),
            io__write_char('"')
        ;
            io__write_string("NULL")
        ),
        io__write_string(");\n")
    ;
        []
    ).

    %
    % If call profiling is turned on output an instruction to record
    % an arc in the call profile between the callee and caller.
    %
:- pred mlds_maybe_output_call_profile_instr(mlds_context::in,
        indent::in, mlds_rval::in, mlds_qualified_entity_name::in,
        io__state::di, io__state::uo) is det.

mlds_maybe_output_call_profile_instr(Context, Indent,
        CalleeFuncRval, CallerName) -->
    globals__io_lookup_bool_option(profile_calls, ProfileCalls),
    ( { ProfileCalls = yes } ->
        mlds_indent(Context, Indent),
        io__write_string("MR_prof_call_profile("),
        mlds_output_bracketed_rval(CalleeFuncRval),
        io__write_string(", "),
        mlds_output_fully_qualified_name(CallerName),
        io__write_string(");\n")
    ;
        []
    ).

    %
    % If time profiling is turned on output an instruction which
    % informs the runtime which procedure we are currently located
    % in.
    %
:- pred mlds_maybe_output_time_profile_instr(mlds_context::in,
        indent::in, mlds_qualified_entity_name::in,
        io__state::di, io__state::uo) is det.

mlds_maybe_output_time_profile_instr(Context, Indent, Name) -->
    globals__io_lookup_bool_option(profile_time, ProfileTime),
    (
        { ProfileTime = yes }
    ->
        mlds_indent(Context, Indent),
        io__write_string("MR_set_prof_current_proc("),
        mlds_output_fully_qualified_name(Name),
        io__write_string(");\n")
    ;
        []
    ).

***************/

%-----------------------------------------------------------------------------%

%
% atomic statements
%

:- pred gen_atomic_stmt(defn_info,
        mlds_atomic_statement, mlds_context, io__state, io__state).
:- mode gen_atomic_stmt(in, in, in, di, uo) is det.

    %
    % comments
    %
gen_atomic_stmt(_DefnInfo, comment(_Comment), _) -->
    % For now, we just ignore the comments.
    % XXX Does gcc provide some way of inserting
    % comments into the generated assembler?
    [].

    %
    % assignment
    %
gen_atomic_stmt(DefnInfo, assign(Lval, Rval), _) -->
    build_lval(Lval, DefnInfo, GCC_Lval),
    build_rval(Rval, DefnInfo, GCC_Rval),
    gcc__gen_assign(GCC_Lval, GCC_Rval).

gen_atomic_stmt(_, assign_if_in_heap(_, _), _) -->
    { sorry(this_file, "gen_atomic_stmt: assign_if_in_heap") }.

    %
    % heap management
    %
gen_atomic_stmt(_DefnInfo, delete_object(_Lval), _) -->
    % XXX not yet implemented
    % we should generate a call to GC_free()
    % (would be easy to do, but not needed so far, since
    % these are not generated by the current MLDS code generator)
    { sorry(this_file, "delete_object") }.

gen_atomic_stmt(DefnInfo, NewObject, Context) -->
    { NewObject = new_object(Target, MaybeTag, _HasSecTag, Type, MaybeSize,
        _MaybeCtorName, Args, ArgTypes, _MayUseAtomic) },

    %
    % Calculate the size that we're going to allocate.
    %
    ( { MaybeSize = yes(SizeInWords) } ->
        globals__io_lookup_int_option(bytes_per_word, BytesPerWord),
        { SizeOfWord = ml_const(mlconst_int(BytesPerWord)) },
        { SizeInBytes = ml_binop(int_mul, SizeInWords, SizeOfWord) }
    ;
        { sorry(this_file, "new_object with unknown size") }
    ),

    %
    % Generate code to allocate the memory and optionally tag the pointer,
    % i.e. `Target = (Type) GC_malloc(SizeInBytes)'
    % or `Target = MR_mkword(Tag, (Type) GC_malloc(SizeInBytes))'.
    %

    % generate `GC_malloc(SizeInBytes)'
    build_call(gcc__alloc_func_decl, [SizeInBytes], DefnInfo, GCC_Call),

    % cast the result to (Type)
    build_type(Type, DefnInfo ^ global_info, GCC_Type),
    gcc__convert_type(GCC_Call, GCC_Type, GCC_CastCall),

    % add a tag to the pointer, if necessary
    ( { MaybeTag = yes(Tag0) } ->
        { Tag = Tag0 },
        gcc__build_int(Tag, GCC_Tag),
        gcc__build_binop(gcc__plus_expr, GCC_Type,
            GCC_CastCall, GCC_Tag, GCC_TaggedCastCall)
    ;
        { Tag = 0 },
        { GCC_TaggedCastCall = GCC_CastCall }
    ),

    % assign it to Target
    build_lval(Target, DefnInfo, GCC_Target),
    gcc__gen_assign(GCC_Target, GCC_TaggedCastCall),

    %
    % Initialize the fields.
    %
    gen_init_args(Args, ArgTypes, Context, 0, Target, Type, Tag,
        DefnInfo).

gen_atomic_stmt(_DefnInfo, gc_check, _) -->
    { sorry(this_file, "gc_check") }.

gen_atomic_stmt(_DefnInfo, mark_hp(_Lval), _) -->
    { sorry(this_file, "mark_hp") }.

gen_atomic_stmt(_DefnInfo, restore_hp(_Rval), _) -->
    { sorry(this_file, "restore_hp") }.

    %
    % trail management
    %
gen_atomic_stmt(_DefnInfo, trail_op(_TrailOp), _) -->
    % Currently trail ops are implemented via calls to
    % impure predicates implemented in C, rather than as
    % MLDS trail ops, so this should never be reached.
    { unexpected(this_file, "trail_op") }.
    % XXX That approach should work OK, but it is not
    % maximally efficient for this back-end, since for
    % this back-end the calls to C will end up as out-of-line
    % calls.  It would be more efficient to recognize
    % the calls to the impure trail predicates and treat them
    % as as builtins, expanding them to MLDS trail ops in
    % ml_code_gen/ml_call_gen, and then generating inline
    % code for them here.

    %
    % foreign language interfacing
    %
gen_atomic_stmt(_DefnInfo, inline_target_code(_TargetLang, _Components),
        _Context) -->
    % XXX we should support inserting inline asm code fragments
    { sorry(this_file, "target_code (for `--target asm')") }.
gen_atomic_stmt(_DefnInfo, outline_foreign_proc(_, _, _, _), _Context) -->
    % XXX I'm not sure if we need to handle this case
    { sorry(this_file, "outline_foreign_proc (for `--target asm')") }.

    %
    % gen_init_args generates code to initialize the fields
    % of an object allocated with a new_object MLDS instruction.
    %
:- pred gen_init_args(list(mlds_rval), list(mlds_type), mlds_context, int,
        mlds_lval, mlds_type, mlds_tag, defn_info,
        io__state, io__state).
:- mode gen_init_args(in, in, in, in, in, in, in, in, di, uo) is det.

gen_init_args([_|_], [], _, _, _, _, _, _) -->
    { unexpected(this_file, "gen_init_args: length mismatch") }.
gen_init_args([], [_|_], _, _, _, _, _, _) -->
    { unexpected(this_file, "gen_init_args: length mismatch") }.
gen_init_args([], [], _, _, _, _, _, _) --> [].
gen_init_args([Arg | Args], [ArgType | ArgTypes], Context,
        ArgNum, Target, Type, Tag, DefnInfo) -->
    %
    % Currently all fields of new_object instructions are
    % represented as MR_Box, so we need to box them if necessary.
    %
    { Lval = ml_field(yes(Tag), ml_lval(Target),
        ml_field_offset(ml_const(mlconst_int(ArgNum))), mlds_generic_type,
            Type) },
    { Rval = ml_unop(box(ArgType), Arg) },
    build_lval(Lval, DefnInfo, GCC_Lval),
    build_rval(Rval, DefnInfo, GCC_Rval),
    gcc__gen_assign(GCC_Lval, GCC_Rval),
    gen_init_args(Args, ArgTypes, Context,
            ArgNum + 1, Target, Type, Tag, DefnInfo).

%-----------------------------------------------------------------------------%
%
% Code to output expressions
%

:- pred build_lval(mlds_lval, defn_info, gcc__expr, io__state, io__state).
:- mode build_lval(in, in, out, di, uo) is det.

build_lval(ml_field(MaybeTag, Rval, ml_field_offset(OffsetRval),
        FieldType, _ClassType), DefnInfo, GCC_FieldRef) -->
    % sanity check (copied from mlds_to_c.m)
    (
        { FieldType = mlds_generic_type
        ; FieldType = mlds__mercury_type(type_variable(_, _), _, _)
        }
    ->
        []
    ;
        % The field type for field(_, _, offset(_), _, _) lvals
        % must be something that maps to MR_Box.
        { unexpected(this_file, "unexpected field type") }
    ),

    % generate the tagged pointer whose field we want to extract
    build_rval(Rval, DefnInfo, GCC_TaggedPointer),

    % subtract or mask out the tag
    ( { MaybeTag = yes(Tag) } ->
        gcc__build_int(Tag, GCC_Tag),
        gcc__build_binop(gcc__minus_expr, gcc__ptr_type_node,
            GCC_TaggedPointer, GCC_Tag, GCC_Pointer)
    ;
        globals__io_lookup_int_option(num_tag_bits, TagBits),
        gcc__build_int(\ ((1 << TagBits) - 1), GCC_Mask),
        gcc__build_binop(gcc__bit_and_expr, gcc__ptr_type_node,
            GCC_TaggedPointer, GCC_Mask, GCC_Pointer)
    ),

    % add the appropriate offset
    build_rval(OffsetRval, DefnInfo, GCC_OffsetInWords),
    globals__io_lookup_int_option(bytes_per_word, BytesPerWord),
    gcc__build_int(BytesPerWord, GCC_BytesPerWord),
    gcc__build_binop(gcc__mult_expr, 'MR_intptr_t',
        GCC_OffsetInWords, GCC_BytesPerWord, GCC_OffsetInBytes),
    gcc__build_binop(gcc__plus_expr, gcc__ptr_type_node,
        GCC_Pointer, GCC_OffsetInBytes, GCC_FieldPointer0),

    % cast the pointer to the right type (XXX is this necessary?)
    build_type(FieldType, DefnInfo ^ global_info, GCC_FieldType),
    gcc__build_pointer_type(GCC_FieldType, GCC_FieldPointerType),
    gcc__convert_type(GCC_FieldPointer0, GCC_FieldPointerType,
        GCC_FieldPointer),

    % deference it
    gcc__build_pointer_deref(GCC_FieldPointer, GCC_FieldRef).

build_lval(ml_field(MaybeTag, PtrRval, ml_field_named(FieldName, CtorType),
        _FieldType, _PtrType), DefnInfo, GCC_Expr) -->
    % generate the tagged pointer whose field we want to extract
    build_rval(PtrRval, DefnInfo, GCC_TaggedPointer),

    % subtract or mask out the tag
    ( { MaybeTag = yes(Tag) } ->
        gcc__build_int(Tag, GCC_Tag),
        gcc__build_binop(gcc__minus_expr, gcc__ptr_type_node,
            GCC_TaggedPointer, GCC_Tag, GCC_Pointer)
    ;
        globals__io_lookup_int_option(num_tag_bits, TagBits),
        gcc__build_int(\ ((1 << TagBits) - 1), GCC_Mask),
        gcc__build_binop(gcc__bit_and_expr, gcc__ptr_type_node,
            GCC_TaggedPointer, GCC_Mask, GCC_Pointer)
    ),

    % cast the pointer to the right type
    build_type(CtorType, DefnInfo ^ global_info, GCC_CtorType),
    gcc__build_pointer_type(GCC_CtorType, GCC_PointerType),
    gcc__convert_type(GCC_Pointer, GCC_PointerType,
        GCC_CastPointer),

    % deference it
    gcc__build_pointer_deref(GCC_CastPointer, GCC_ObjectRef),

    % extract the right field
    { TypeTable = DefnInfo ^ global_info ^ type_table },
    { TypeName = get_class_type_name(CtorType) },
    { gcc_type_info(_, FieldTable) = map__lookup(TypeTable, TypeName) },
    { GCC_FieldDecl = map__lookup(FieldTable, FieldName) },
    gcc__build_component_ref(GCC_ObjectRef, GCC_FieldDecl,
        GCC_Expr).

build_lval(ml_mem_ref(PointerRval, _Type), DefnInfo, Expr) -->
    build_rval(PointerRval, DefnInfo, PointerExpr),
    gcc__build_pointer_deref(PointerExpr, Expr).

build_lval(ml_global_var_ref(_), _DefnInfo, _Expr) -->
    { sorry(this_file, "build_lval: global_var_ref NYI") }.

build_lval(ml_var(qual(ModuleName, QualKind, VarName), _VarType), DefnInfo,
        Expr) -->
    %
    % Look up the variable in the symbol table.
    % We try the symbol table for local vars first,
    % and then if its not there, we look in the global vars
    % symbol table.  If it's not in either of those,
    % we check if its an RTTI enumeration constant.
    %
    { Name = qual(ModuleName, QualKind,
        entity_data(mlds_data_var(VarName))) },
    (
        { map__search(DefnInfo ^ local_vars, Name, LocalVarDecl) }
    ->
        { Expr = gcc__var_expr(LocalVarDecl) }
    ;
        { map__search(DefnInfo ^ global_info ^ global_vars,
            Name, GlobalVarDecl) }
    ->
        { Expr = gcc__var_expr(GlobalVarDecl) }
    ;
        % check if it's in the private_builtin module
        % and is an RTTI enumeration constant
        { PrivateBuiltin = mercury_private_builtin_module },
        { mercury_module_name_to_mlds(PrivateBuiltin) = ModuleName },
        { VarName = mlds_var_name(VarNameBase, _MaybeNum) },
        { rtti_enum_const(VarNameBase, IntVal) }
    ->
        gcc__build_int(IntVal, Expr)
    ;
        % check if it's private_builtin:dummy_var
        { PrivateBuiltin = mercury_private_builtin_module },
        { mercury_module_name_to_mlds(PrivateBuiltin) = ModuleName },
        { VarName = mlds_var_name("dummy_var", _) }
    ->
        % if so, generate an extern declaration for it, and use that.
        { GCC_VarName = build_data_var_name(ModuleName,
            mlds_data_var(VarName)) },
        { Type = 'MR_Word' },
        gcc__build_extern_var_decl(GCC_VarName, Type, Decl),
        { Expr = gcc__var_expr(Decl) }
    ;
        { unexpected(this_file, "undeclared variable: " ++
            build_qualified_name(Name)) }
    ).

:- func get_class_type_name(mlds_type) = mlds_qualified_entity_name.
get_class_type_name(Type) = Name :-
    (
        (
            Type = mlds_class_type(ClassName, Arity, _Kind)
        ;
            Type = mlds_ptr_type(mlds_class_type(ClassName,
                        Arity, _Kind))
        )
    ->
        ClassName = qual(ModuleName, QualKind, UnqualClassName),
        Name = qual(ModuleName, QualKind,
            entity_type(UnqualClassName, Arity))
    ;
        unexpected(this_file, "non-class_type in get_type_name")
    ).

:- pred build_rval(mlds_rval, defn_info, gcc__expr, io__state, io__state).
:- mode build_rval(in, in, out, di, uo) is det.

build_rval(ml_lval(Lval), DefnInfo, Expr) -->
    build_lval(Lval, DefnInfo, Expr).
build_rval(ml_mkword(Tag, Arg), DefnInfo, Expr) -->
    gcc__build_int(Tag, GCC_Tag),
    build_rval(Arg, DefnInfo, GCC_Arg),
    gcc__build_binop(gcc__plus_expr, gcc__ptr_type_node,
        GCC_Arg, GCC_Tag, Expr).
build_rval(ml_const(Const), DefnInfo, Expr) -->
    build_rval_const(Const, DefnInfo ^ global_info, Expr).
build_rval(ml_unop(Op, Rval), DefnInfo, Expr) -->
    build_unop(Op, Rval, DefnInfo, Expr).
build_rval(ml_binop(Op, Rval1, Rval2), DefnInfo, Expr) -->
    build_std_binop(Op, Rval1, Rval2, DefnInfo, Expr).
build_rval(ml_mem_addr(Lval), DefnInfo, AddrExpr) -->
    build_lval(Lval, DefnInfo, Expr),
    gcc__build_addr_expr(Expr, AddrExpr).
build_rval(ml_scalar_common(_), _DefnInfo, _Expr) -->
    { unexpected(this_file, "scalar_common rval") }.
build_rval(ml_vector_common_row(_, _), _DefnInfo, _Expr) -->
    { unexpected(this_file, "vector_common rval") }.
build_rval(ml_self(_), _DefnInfo, _Expr) -->
    { unexpected(this_file, "self rval") }.

:- pred build_unop(mlds_unary_op, mlds_rval, defn_info, gcc__expr,
        io__state, io__state).
:- mode build_unop(in, in, in, out, di, uo) is det.

build_unop(cast(Type), Rval, DefnInfo, GCC_Expr) -->
    build_cast_rval(Type, Rval, DefnInfo, GCC_Expr).
build_unop(box(Type), Rval, DefnInfo, GCC_Expr) -->
    ( { type_is_float(Type) } ->
        build_call(gcc__box_float_func_decl, [Rval], DefnInfo,
            GCC_Expr)
    ; { Type = mlds_array_type(_) } ->
        % When boxing arrays, we need to take the address of the array.
        % This implies that the array must be an lval.
        % But we also allow null arrays as a special case;
        % boxing a null array results in a null pointer.
        ( { Rval = ml_const(mlconst_null(_)) } ->
            { PtrRval = ml_const(mlconst_null(mlds_generic_type)) },
            build_rval(PtrRval, DefnInfo, GCC_Expr)
        ; { Rval = ml_lval(ArrayLval) } ->
            { PtrRval = ml_mem_addr(ArrayLval) },
            build_cast_rval(mlds_generic_type, PtrRval, DefnInfo,
                GCC_Expr)
        ;
            { unexpected(this_file,
                "boxing non-lval, non-null array") }
        )
    ;
        build_cast_rval(mlds_generic_type, Rval, DefnInfo, GCC_Expr)
    ).
build_unop(unbox(Type), Rval, DefnInfo, GCC_Expr) -->
    ( { type_is_float(Type) } ->
        % Generate `*(MR_Float *)<Rval>'
        build_rval(Rval, DefnInfo, GCC_Pointer),
        gcc__build_pointer_type('MR_Float', FloatPointerType),
        gcc__convert_type(GCC_Pointer, FloatPointerType,
            GCC_CastPointer),
        gcc__build_pointer_deref(GCC_CastPointer, GCC_Expr)
    ;
        build_cast_rval(Type, Rval, DefnInfo, GCC_Expr)
    ).
build_unop(std_unop(Unop), Exprn, DefnInfo, GCC_Expr) -->
    build_std_unop(Unop, Exprn, DefnInfo, GCC_Expr).

:- pred type_is_float(mlds_type::in) is semidet.
type_is_float(Type) :-
    ( Type = mlds__mercury_type(builtin_type(builtin_type_float), _, _)
    ; Type = mlds_native_float_type
    ).

:- pred build_cast_rval(mlds_type, mlds_rval, defn_info, gcc__expr,
        io__state, io__state).
:- mode build_cast_rval(in, in, in, out, di, uo) is det.

build_cast_rval(Type, Rval, DefnInfo, GCC_Expr) -->
    build_rval(Rval, DefnInfo, GCC_Rval),
    build_type(Type, DefnInfo ^ global_info, GCC_Type),
    gcc__convert_type(GCC_Rval, GCC_Type, GCC_Expr).

:- pred build_std_unop(builtin_ops__unary_op, mlds_rval, defn_info,
        gcc__expr, io__state, io__state).
:- mode build_std_unop(in, in, in, out, di, uo) is det.

build_std_unop(UnaryOp, Arg, DefnInfo, Expr) -->
    build_rval(Arg, DefnInfo, GCC_Arg),
    build_unop_expr(UnaryOp, GCC_Arg, Expr).

:- pred build_unop_expr(builtin_ops__unary_op, gcc__expr, gcc__expr,
        io__state, io__state).
:- mode build_unop_expr(in, in, out, di, uo) is det.

% We assume that the tag bits are kept on the low bits
% (`--tags low'), not on the high bits (`--tags high').
% XXX we should enforce this in handle_options.m.

build_unop_expr(mktag, Tag, Tag) --> [].
build_unop_expr(tag, Arg, Expr) -->
    globals__io_lookup_int_option(num_tag_bits, TagBits),
    gcc__build_int((1 << TagBits) - 1, Mask),
    gcc__build_binop(gcc__bit_and_expr, 'MR_intptr_t',
        Arg, Mask, Expr).
build_unop_expr(unmktag, Tag, Tag) --> [].
build_unop_expr(mkbody, Arg, Expr) -->
    globals__io_lookup_int_option(num_tag_bits, TagBits),
    gcc__build_int(TagBits, TagBitsExpr),
    gcc__build_binop(gcc__lshift_expr, 'MR_intptr_t',
        Arg, TagBitsExpr, Expr).
build_unop_expr(unmkbody, Arg, Expr) -->
    globals__io_lookup_int_option(num_tag_bits, TagBits),
    gcc__build_int(TagBits, TagBitsExpr),
    gcc__build_binop(gcc__rshift_expr, 'MR_intptr_t',
        Arg, TagBitsExpr, Expr).
build_unop_expr(strip_tag, Arg, Expr) -->
    globals__io_lookup_int_option(num_tag_bits, TagBits),
    gcc__build_int((1 << TagBits) - 1, Mask),
    gcc__build_unop(gcc__bit_not_expr, 'MR_intptr_t',
        Mask, InvertedMask),
    gcc__build_binop(gcc__bit_and_expr, 'MR_intptr_t',
        Arg, InvertedMask, Expr).
build_unop_expr(hash_string, Arg, Expr) -->
    gcc__build_func_addr_expr(gcc__hash_string_func_decl,
        HashStringFuncExpr),
    gcc__empty_arg_list(GCC_ArgList0),
    gcc__cons_arg_list(Arg, GCC_ArgList0, GCC_ArgList),
    { IsTailCall = no },
    gcc__build_call_expr(HashStringFuncExpr, GCC_ArgList, IsTailCall,
        Expr).
build_unop_expr(bitwise_complement, Arg, Expr) -->
    gcc__build_unop(gcc__bit_not_expr, 'MR_Integer', Arg, Expr).
build_unop_expr(logical_not, Arg, Expr) -->
    gcc__build_unop(gcc__truth_not_expr, gcc__boolean_type_node,
        Arg, Expr).

:- pred build_std_binop(builtin_ops__binary_op, mlds_rval, mlds_rval,
        defn_info, gcc__expr, io__state, io__state).
:- mode build_std_binop(in, in, in, in, out, di, uo) is det.

build_std_binop(BinaryOp, Arg1, Arg2, DefnInfo, Expr) -->
    ( { string_compare_op(BinaryOp, CorrespondingIntOp) } ->
        %
        % treat string comparison operators specially:
        % convert "X `str_OP` Y" into "strcmp(X, Y) `OP` 0"
        %
        build_call(gcc__strcmp_func_decl, [Arg1, Arg2], DefnInfo,
            GCC_Call),
        gcc__build_int(0, Zero),
        gcc__build_binop(CorrespondingIntOp, gcc__boolean_type_node,
            GCC_Call, Zero, Expr)
    ; { unsigned_compare_op(BinaryOp, _GCC_BinaryOp) } ->
        % XXX This is not implemented yet, because we don't have
        % 'MR_Unsigned'.  But unsigned_le is only needed for dense
        % (computed_goto) switches, and we set
        % target_supports_computed_goto to no for this target,
        % so we shouldn't get any of these.
        { unexpected(this_file, "unsigned comparison operator") }
        /***
        %
        % Treat unsigned comparison operators specially:
        % convert the arguments to unsigned.
        %
        build_rval(Arg1, DefnInfo, GCC_Arg1),
        build_rval(Arg2, DefnInfo, GCC_Arg2),
        gcc__convert_type(GCC_Arg1, 'MR_Unsigned', GCC_UnsignedArg1),
        gcc__convert_type(GCC_Arg2, 'MR_Unsigned', GCC_UnsignedArg2),
        gcc__build_binop(GCC_BinaryOp, gcc__boolean_type_node,
            GCC_UnsignedArg1, GCC_UnsignedArg2, Expr)
        ***/
    ;
        %
        % the usual case: just build a gcc tree node for the expr.
        %
        build_rval(Arg1, DefnInfo, GCC_Arg1),
        build_rval(Arg2, DefnInfo, GCC_Arg2),
        ( { BinaryOp = array_index(ElemType) } ->
            % for array index operations,
            % we need to convert the element type into a GCC type
            { GCC_BinaryOp = gcc__array_ref },
            { MLDS_Type = ml_gen_array_elem_type(ElemType) },
            build_type(MLDS_Type, DefnInfo ^ global_info,
                GCC_ResultType)
        ;
            { convert_binary_op(BinaryOp, GCC_BinaryOp,
                GCC_ResultType) }
        ),
        gcc__build_binop(GCC_BinaryOp, GCC_ResultType,
            GCC_Arg1, GCC_Arg2, Expr)
    ).

:- pred string_compare_op(builtin_ops__binary_op, gcc__op).
:- mode string_compare_op(in, out) is semidet.
string_compare_op(str_eq, gcc__eq_expr).
string_compare_op(str_ne, gcc__ne_expr).
string_compare_op(str_lt, gcc__lt_expr).
string_compare_op(str_gt, gcc__gt_expr).
string_compare_op(str_le, gcc__le_expr).
string_compare_op(str_ge, gcc__ge_expr).

:- pred unsigned_compare_op(builtin_ops__binary_op, gcc__op).
:- mode unsigned_compare_op(in, out) is semidet.
unsigned_compare_op(unsigned_le, gcc__le_expr).

    % Convert one of our operators to the corresponding
    % gcc operator.  Also compute the gcc return type.
:- pred convert_binary_op(builtin_ops__binary_op, gcc__op, gcc__type).
:- mode convert_binary_op(in, out, out) is det.

        % Operator  GCC operator         GCC result type
convert_binary_op(int_add,  gcc__plus_expr,      'MR_Integer').
convert_binary_op(int_sub,  gcc__minus_expr,     'MR_Integer').
convert_binary_op(int_mul,  gcc__mult_expr,      'MR_Integer').
convert_binary_op(int_div,  gcc__trunc_div_expr, 'MR_Integer').
convert_binary_op(int_mod,  gcc__trunc_mod_expr, 'MR_Integer').
convert_binary_op(unchecked_left_shift, gcc__lshift_expr,    'MR_Integer').
convert_binary_op(unchecked_right_shift,gcc__rshift_expr,    'MR_Integer').
convert_binary_op(bitwise_and,  gcc__bit_and_expr,   'MR_Integer').
convert_binary_op(bitwise_or,   gcc__bit_ior_expr,   'MR_Integer').
convert_binary_op(bitwise_xor,  gcc__bit_xor_expr,   'MR_Integer').
convert_binary_op(logical_and,  gcc__truth_andif_expr, gcc__boolean_type_node).
convert_binary_op(logical_or,   gcc__truth_orif_expr, gcc__boolean_type_node).
convert_binary_op(eq,       gcc__eq_expr,        gcc__boolean_type_node).
convert_binary_op(ne,       gcc__ne_expr,        gcc__boolean_type_node).
convert_binary_op(body,     gcc__minus_expr,     'MR_intptr_t').
convert_binary_op(array_index(_), _, _) :-
                unexpected(this_file, "array_index").
convert_binary_op(str_eq, _, _) :- unexpected(this_file, "str_eq").
convert_binary_op(str_ne, _, _) :- unexpected(this_file, "str_ne").
convert_binary_op(str_lt, _, _) :- unexpected(this_file, "str_lt").
convert_binary_op(str_gt, _, _) :- unexpected(this_file, "str_gt").
convert_binary_op(str_le, _, _) :- unexpected(this_file, "str_le").
convert_binary_op(str_ge, _, _) :- unexpected(this_file, "str_ge").
convert_binary_op(int_lt,   gcc__lt_expr,        gcc__boolean_type_node).
convert_binary_op(int_gt,   gcc__gt_expr,        gcc__boolean_type_node).
convert_binary_op(int_le,   gcc__le_expr,        gcc__boolean_type_node).
convert_binary_op(int_ge,   gcc__ge_expr,        gcc__boolean_type_node).
convert_binary_op(unsigned_le, _, _) :- unexpected(this_file, "unsigned_le").
convert_binary_op(float_plus,   gcc__plus_expr,      'MR_Float').
convert_binary_op(float_minus,  gcc__minus_expr,     'MR_Float').
convert_binary_op(float_times,  gcc__mult_expr,      'MR_Float').
convert_binary_op(float_divide, gcc__rdiv_expr,      'MR_Float').
convert_binary_op(float_eq, gcc__eq_expr,        gcc__boolean_type_node).
convert_binary_op(float_ne, gcc__ne_expr,        gcc__boolean_type_node).
convert_binary_op(float_lt, gcc__lt_expr,        gcc__boolean_type_node).
convert_binary_op(float_gt, gcc__gt_expr,        gcc__boolean_type_node).
convert_binary_op(float_le, gcc__le_expr,        gcc__boolean_type_node).
convert_binary_op(float_ge, gcc__ge_expr,        gcc__boolean_type_node).
convert_binary_op(compound_eq, _, _) :- unexpected(this_file, "compound_eq").
convert_binary_op(compound_lt, _, _) :- unexpected(this_file, "compound_lt").

:- pred build_call(gcc__func_decl::in, list(mlds_rval)::in, defn_info::in,
        gcc__expr::out, io__state::di, io__state::uo) is det.
build_call(FuncDecl, ArgList, DefnInfo, GCC_Call) -->
    gcc__build_func_addr_expr(FuncDecl, FuncExpr),
    build_args(ArgList, DefnInfo, GCC_ArgList),
    { IsTailCall = no },
    gcc__build_call_expr(FuncExpr, GCC_ArgList, IsTailCall, GCC_Call).

:- pred build_args(list(mlds_rval), defn_info, gcc__arg_list,
        io__state, io__state).
:- mode build_args(in, in, out, di, uo) is det.

build_args([], _DefnInfo, EmptyArgList) -->
    gcc__empty_arg_list(EmptyArgList).
build_args([Arg|Args], DefnInfo, GCC_ArgList) -->
    build_rval(Arg, DefnInfo, GCC_Expr),
    build_args(Args, DefnInfo, GCC_ArgList0),
    gcc__cons_arg_list(GCC_Expr, GCC_ArgList0, GCC_ArgList).

%-----------------------------------------------------------------------------%
%
% Code to output constants
%

:- pred build_rval_const(mlds_rval_const, global_info, gcc__expr,
        io__state, io__state).
:- mode build_rval_const(in, in, out, di, uo) is det.

build_rval_const(mlconst_true, _, Expr) -->
    % XXX currently we don't use a separate boolean type
    gcc__build_int(1, Expr).
build_rval_const(mlconst_false, _, Expr) -->
    % XXX currently we don't use a separate boolean type
    gcc__build_int(0, Expr).
build_rval_const(mlconst_int(N), _, Expr) -->
    gcc__build_int(N, Expr).
build_rval_const(mlconst_foreign(_Lang, _Value, _Type), _, _) -->
    { sorry(this_file,
        "foreign tags not yet supported with `--target asm'") }.
build_rval_const(mlconst_float(FloatVal), _, Expr) -->
    gcc__build_float(FloatVal, Expr).
build_rval_const(mlconst_string(String), _, Expr) -->
    gcc__build_string(String, Expr).
build_rval_const(mlconst_multi_string(_Strings), _, _Expr) -->
    % multi-strings are only used for the debugger.
    { sorry(this_file,
        "debugging not yet supported with `--target asm'") }.
build_rval_const(mlconst_named_const(_NamedConst), _, _Expr) -->
    { sorry(this_file,
        "named consts not yet supported with `--target asm'") }.
build_rval_const(mlconst_code_addr(CodeAddr), GlobalInfo, Expr) -->
    build_code_addr(CodeAddr, GlobalInfo, Expr).
build_rval_const(mlconst_data_addr(DataAddr), _, Expr) -->
    build_data_addr(DataAddr, Expr).
build_rval_const(mlconst_null(_Type), _, Expr) -->
    % XXX is it OK to ignore the type here?
    gcc__build_null_pointer(Expr).

:- pred build_code_addr(mlds_code_addr, global_info, gcc__expr,
        io__state, io__state).
:- mode build_code_addr(in, in, out, di, uo) is det.

build_code_addr(CodeAddr, GlobalInfo, Expr) -->
    (
        { CodeAddr = code_addr_proc(Label, Signature) },
        { MaybeSeqNum = no }
    ;
        { CodeAddr = code_addr_internal(Label, SeqNum, Signature) },
        { MaybeSeqNum = yes(SeqNum) }
    ),
    % convert the label into a entity_name,
    % so we can use make_func_decl below
    { Label = qual(ModuleName, QualKind,
        mlds_proc_label(PredLabel, ProcId)) },
    { Name = qual(ModuleName, QualKind, entity_function(PredLabel, ProcId,
        MaybeSeqNum, invalid_pred_id)) },
    % build a function declaration for the function,
    % and take its address.
    make_func_decl(Name, Signature, GlobalInfo, FuncDecl),
    gcc__build_func_addr_expr(FuncDecl, Expr).

:- pred build_data_addr(mlds_data_addr, gcc__expr, io__state, io__state).
:- mode build_data_addr(in, out, di, uo) is det.

build_data_addr(DataAddr, Expr) -->
    build_data_decl(DataAddr, Decl),
    gcc__build_addr_expr(gcc__var_expr(Decl), Expr).

:- pred build_data_decl(mlds_data_addr, gcc__var_decl, io__state, io__state).
:- mode build_data_decl(in, out, di, uo) is det.

build_data_decl(data_addr(ModuleName, DataName), Decl) -->
    % XXX Bug! Type won't always be 'MR_Word'
    % XXX Bug! Shouldn't always be extern
    { VarName = build_data_var_name(ModuleName, DataName) },
    { Type = 'MR_Word' },
    gcc__build_extern_var_decl(VarName, Type, Decl).

:- func build_data_var_name(mlds_module_name, mlds_data_name) = string.

build_data_var_name(ModuleName, DataName) =
        ModuleQualifier ++ build_data_name(DataName) :-
    (
        DataName = mlds_rtti(RttiId),
        module_qualify_name_of_rtti_id(RttiId) = no
    ->
        ModuleQualifier = ""
    ;
        ModuleNameString = get_module_name(
            mlds_module_name_to_sym_name(ModuleName)),
        ModuleQualifier = string__append(ModuleNameString, "__")
    ).

%-----------------------------------------------------------------------------%
%
% Generation of source context info (file name and line number annotations).
%

:- pred set_context(mlds_context::in, io__state::di, io__state::uo) is det.

set_context(MLDS_Context) -->
    { ProgContext = mlds_get_prog_context(MLDS_Context) },
    { FileName = term__context_file(ProgContext) },
    { LineNumber = term__context_line(ProgContext) },
    gcc__set_context(FileName, LineNumber).

:- pred gen_context(mlds_context, io__state, io__state).
:- mode gen_context(in, di, uo) is det.

gen_context(MLDS_Context) -->
    { ProgContext = mlds_get_prog_context(MLDS_Context) },
    { FileName = term__context_file(ProgContext) },
    { LineNumber = term__context_line(ProgContext) },
    gcc__gen_line_note(FileName, LineNumber).

%-----------------------------------------------------------------------------%
%
% "Typedefs", i.e. constants of type `gcc__type'.
%
% We use the same names for types as in the MLDS -> C back-end.
%

:- func 'MR_Box'        = gcc__type.
:- func 'MR_Integer'        = gcc__type.
:- func 'MR_Float'      = gcc__type.
:- func 'MR_Char'       = gcc__type.
:- func 'MR_String'     = gcc__type.
:- func 'MR_ConstString'    = gcc__type.
:- func 'MR_Word'       = gcc__type.
:- func 'MR_bool'       = gcc__type.
:- func 'MR_ProcAddr'       = gcc__type.
:- func 'MR_TypeInfo'       = gcc__type.
:- func 'MR_TypeCtorInfo'   = gcc__type.
:- func 'MR_PseudoTypeInfo' = gcc__type.
:- func 'MR_Sectag_Locn'    = gcc__type.
:- func 'MR_TypeCtorRep'    = gcc__type.
:- func 'MR_Determinism'    = gcc__type.
:- func 'MR_PredFunc'       = gcc__type.

:- func 'MR_int_least8_t'   = gcc__type.
:- func 'MR_int_least16_t'  = gcc__type.
:- func 'MR_int_least32_t'  = gcc__type.
:- func 'MR_int_least64_t'  = gcc__type.
:- func 'MR_intptr_t'       = gcc__type.

'MR_Box'        = gcc__ptr_type_node.
'MR_Integer'        = gcc__intptr_type_node.
'MR_Float'      = gcc__double_type_node.
'MR_Char'       = gcc__char_type_node.
'MR_String'     = gcc__string_type_node.
    % XXX 'MR_ConstString' should really be const
'MR_ConstString'    = gcc__string_type_node.
    % XXX 'MR_Word' should perhaps be unsigned, to match the C back-end
'MR_Word'       = gcc__intptr_type_node.
'MR_bool'       = gcc__integer_type_node. % i.e. typedef int MR_bool
'MR_ProcAddr'       = gcc__ptr_type_node.

'MR_TypeInfo'       = gcc__ptr_type_node.
'MR_TypeCtorInfo'   = gcc__ptr_type_node.
'MR_PseudoTypeInfo' = gcc__ptr_type_node.

    % XXX MR_Sectag_Locn, MR_TypeCtorRep, MR_Determinism and MR_PredFunc
    % are actually enums in the C back-end.  Binary compatibility between
    % this back-end and the C back-end only works if the C compiler
    % represents these enums the same as `int'.
'MR_Sectag_Locn'    = gcc__integer_type_node.
'MR_TypeCtorRep'    = gcc__integer_type_node.
'MR_Determinism'    = gcc__integer_type_node.
'MR_PredFunc'       = gcc__integer_type_node.

'MR_int_least8_t'   = gcc__int8_type_node.
'MR_int_least16_t'  = gcc__int16_type_node.
'MR_int_least32_t'  = gcc__int32_type_node.
'MR_int_least64_t'  = gcc__int64_type_node.
'MR_intptr_t'       = gcc__intptr_type_node.

%-----------------------------------------------------------------------------%

:- func this_file = string.
this_file = "mlds_to_gcc.m".

:- end_module mlds_to_gcc.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%
