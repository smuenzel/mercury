%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 1996-2011 The University of Melbourne.
% This file may only be copied under the terms of the GNU General
% Public License - see the file COPYING in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% File: deps_map.m.
%
% This module contains a data structure for recording module dependencies
% and its access predicates. The module_deps_graph module contains another
% data structure, used for similar purposes, that is built on top of this one.
% XXX Document the exact relationship between the two.
%
%-----------------------------------------------------------------------------%

:- module parse_tree.deps_map.
:- interface.

:- import_module libs.globals.
:- import_module mdbcomp.sym_name.
:- import_module parse_tree.file_names.
:- import_module parse_tree.module_imports.

:- import_module map.
:- import_module io.

% This is the data structure we use to record the dependencies.
% We keep a map from module name to information about the module.

:- type have_processed
    --->    not_yet_processed
    ;       already_processed.

:- type deps_map == map(module_name, deps).
:- type deps
    --->    deps(
                have_processed,
                module_and_imports
            ).

:- type submodule_kind
    --->    toplevel
    ;       nested_submodule
    ;       separate_submodule.

    % Check if a module is a top-level module, a nested sub-module,
    % or a separate sub-module.
    %
:- func get_submodule_kind(module_name, deps_map) = submodule_kind.

%-----------------------------------------------------------------------------%

:- pred generate_deps_map(globals::in, module_name::in, maybe_search::in,
    deps_map::in, deps_map::out, io::di, io::uo) is det.

    % Insert a new entry into the deps_map. If the module already occurred
    % in the deps_map, then we just replace the old entry (presumed to be
    % a dummy entry) with the new one.
    %
    % This can only occur for sub-modules which have been imported before
    % their parent module was imported: before reading a module and
    % inserting it into the deps map, we check if it was already there,
    % but when we read in the module, we try to insert not just that module
    % but also all the nested sub-modules inside that module. If a sub-module
    % was previously imported, then it may already have an entry in the
    % deps_map. However, unless the sub-module is defined both as a separate
    % sub-module and also as a nested sub-module, the previous entry will be
    % a dummy entry that we inserted after trying to read the source file
    % and failing.
    %
    % Note that the case where a module is defined as both a separate
    % sub-module and also as a nested sub-module is caught in
    % split_into_submodules.
    %
    % XXX This shouldn't need to be exported.
    %
:- pred insert_into_deps_map(module_and_imports::in,
    deps_map::in, deps_map::out) is det.

%-----------------------------------------------------------------------------%

:- implementation.

:- import_module libs.globals.
:- import_module libs.timestamp.
:- import_module parse_tree.error_util.
:- import_module parse_tree.file_kind.
:- import_module parse_tree.split_parse_tree_src. % undesirable dependency
:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_io_error.
:- import_module parse_tree.prog_item.
:- import_module parse_tree.read_modules.
:- import_module parse_tree.status.

:- import_module assoc_list.
:- import_module cord.
:- import_module list.
:- import_module pair.
:- import_module require.
:- import_module set.

%-----------------------------------------------------------------------------%

get_submodule_kind(ModuleName, DepsMap) = Kind :-
    Ancestors = get_ancestors(ModuleName),
    ( list.last(Ancestors, Parent) ->
        map.lookup(DepsMap, ModuleName, deps(_, ModuleImports)),
        map.lookup(DepsMap, Parent, deps(_, ParentImports)),
        ModuleFileName = ModuleImports ^ mai_source_file_name,
        ParentFileName = ParentImports ^ mai_source_file_name,
        ( ModuleFileName = ParentFileName ->
            Kind = nested_submodule
        ;
            Kind = separate_submodule
        )
    ;
        Kind = toplevel
    ).

%-----------------------------------------------------------------------------%

generate_deps_map(Globals, ModuleName, Search, !DepsMap, !IO) :-
    generate_deps_map_loop(Globals, set.make_singleton_set(ModuleName), Search,
        !DepsMap, !IO).

:- pred generate_deps_map_loop(globals::in,
    set(module_name)::in, maybe_search::in,
    deps_map::in, deps_map::out, io::di, io::uo) is det.

generate_deps_map_loop(Globals, !.Modules, Search, !DepsMap, !IO) :-
    ( set.remove_least(Module, !Modules) ->
        generate_deps_map_step(Globals, Module, !Modules, Search, !DepsMap,
            !IO),
        generate_deps_map_loop(Globals, !.Modules, Search, !DepsMap, !IO)
    ;
        % If we can't remove the smallest, then the set of modules to be
        % processed is empty.
        true
    ).

:- pred generate_deps_map_step(globals::in, module_name::in,
    set(module_name)::in, set(module_name)::out,
    maybe_search::in, deps_map::in, deps_map::out, io::di, io::uo) is det.

generate_deps_map_step(Globals, Module, !Modules, Search, !DepsMap, !IO) :-
    % Look up the module's dependencies, and determine whether
    % it has been processed yet.
    lookup_dependencies(Globals, Module, Search, Done, !DepsMap,
        ModuleImports, !IO),

    % If the module hadn't been processed yet, then add its imports, parents,
    % and public children to the list of dependencies we need to generate,
    % and mark it as having been processed.
    (
        Done = not_yet_processed,
        map.set(Module, deps(already_processed, ModuleImports), !DepsMap),
        ForeignImportedModules =
            list.map(
                (func(foreign_import_module_info(_, ImportedModule, _))
                    = ImportedModule),
                cord.list(ModuleImports ^ mai_foreign_import_modules)),
        ModulesToAdd = set.union_list(
            [ModuleImports ^ mai_parent_deps,
            ModuleImports ^ mai_int_deps,
            ModuleImports ^ mai_imp_deps,
            ModuleImports ^ mai_public_children, % a.k.a. incl_deps
            set.list_to_set(ForeignImportedModules)]),
        % We could keep a list of the modules we have already processed
        % and subtract it from ModulesToAddSet here, but doing that
        % actually leads to a small slowdown.
        set.union(ModulesToAdd, !Modules)
    ;
        Done = already_processed
    ).

    % Look up a module in the dependency map.
    % If we don't know its dependencies, read the module and
    % save the dependencies in the dependency map.
    %
:- pred lookup_dependencies(globals::in, module_name::in, maybe_search::in,
    have_processed::out, deps_map::in, deps_map::out, module_and_imports::out,
    io::di, io::uo) is det.

lookup_dependencies(Globals, Module, Search, Done, !DepsMap, ModuleImports,
        !IO) :-
    ( map.search(!.DepsMap, Module, deps(DonePrime, ModuleImportsPrime)) ->
        Done = DonePrime,
        ModuleImports = ModuleImportsPrime
    ;
        read_dependencies(Globals, Module, Search, ModuleImportsList, !IO),
        list.foldl(insert_into_deps_map, ModuleImportsList, !DepsMap),
        map.lookup(!.DepsMap, Module, deps(Done, ModuleImports))
    ).

insert_into_deps_map(ModuleImports, !DepsMap) :-
    module_and_imports_get_module_name(ModuleImports, ModuleName),
    map.set(ModuleName, deps(not_yet_processed, ModuleImports), !DepsMap).

    % Read a module to determine the (direct) dependencies of that module
    % and any nested sub-modules it contains.
    %
:- pred read_dependencies(globals::in, module_name::in, maybe_search::in,
    list(module_and_imports)::out, io::di, io::uo) is det.

read_dependencies(Globals, ModuleName, Search, ModuleAndImportsList, !IO) :-
    % XXX If _SrcSpecs contains error messages, the parse tree may not be
    % complete, and the rest of this predicate may work on incorrect data.
    read_module_src(Globals, "Getting dependencies for module",
        ignore_errors, Search, ModuleName, FileName0,
        always_read_module(dont_return_timestamp), _,
        ParseTreeSrc0, _SrcSpecs, Errors, !IO),
    ParseTreeSrc0 = parse_tree_src(_, _, ModuleComponentCord0),
    (
        cord.is_empty(ModuleComponentCord0),
        set.intersect(Errors, fatal_read_module_errors, FatalErrors),
        set.is_non_empty(FatalErrors)
    ->
        read_module_int(Globals, "Getting dependencies for module interface",
            ignore_errors, Search, ModuleName, ifk_int, FileName,
            always_read_module(dont_return_timestamp), _,
            ParseTreeInt, _IntSpecs, _Errors, !IO),
        ParseTreeInt = parse_tree_int(_, _, ModuleContext,
            _MaybeVersionNumbers, IntIncl, ImpIncls, IntAvails, ImpAvails,
            IntItems, ImpItems),
        int_imp_items_to_item_blocks(ModuleContext,
            ms_interface, ms_implementation, IntIncl, ImpIncls,
            IntAvails, ImpAvails, IntItems, ImpItems, RawItemBlocks),
        RawCompUnits =
            [raw_compilation_unit(ModuleName, ModuleContext, RawItemBlocks)]
    ;
        FileName = FileName0,
        split_into_compilation_units_perform_checks(ParseTreeSrc0,
            RawCompUnits, [], Specs),
        write_error_specs(Specs, Globals, 0, _NumWarnings, 0, _NumErrors, !IO)
    ),
    NestedModuleNames = set.list_to_set(
        list.map(raw_compilation_unit_project_name, RawCompUnits)),
    list.map(
        init_module_and_imports(Globals, FileName, ModuleName,
            NestedModuleNames, [], Errors),
        RawCompUnits, ModuleAndImportsList).

%-----------------------------------------------------------------------------%
:- end_module parse_tree.deps_map.
%-----------------------------------------------------------------------------%
