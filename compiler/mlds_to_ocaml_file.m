
:- module ml_backend.mlds_to_ocaml_file.
:- interface.

:- import_module hlds.
:- import_module hlds.hlds_module.
:- import_module libs.
:- import_module libs.maybe_succeeded.
:- import_module ml_backend.mlds.

:- import_module io.

%---------------------------------------------------------------------------%

:- pred output_ocaml_mlds(module_info::in, mlds::in, maybe_succeeded::out,
    io::di, io::uo) is det.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

%:- import_module libs.compiler_util.
:- import_module libs.file_util.
:- import_module libs.globals.
:- import_module mdbcomp.
:- import_module mdbcomp.sym_name.
:- import_module ml_backend.ml_global_data.
%:- import_module ml_backend.ml_util.
:- import_module ml_backend.mlds_to_target_util.
:- import_module parse_tree.
:- import_module parse_tree.file_names.
%:- import_module parse_tree.java_names.
%:- import_module parse_tree.prog_data.
:- import_module parse_tree.prog_data_foreign.
:- import_module parse_tree.prog_foreign.
%:- import_module parse_tree.prog_out.

%:- import_module assoc_list.
%:- import_module bool.
%:- import_module cord.
%:- import_module int.
:- import_module list.
:- import_module map.
%:- import_module maybe.
:- import_module pair.
%:- import_module require.
%:- import_module set.
%:- import_module string.
%:- import_module term_context.

%---------------------------------------------------------------------------%

output_ocaml_mlds(ModuleInfo, MLDS, Succeeded, !IO) :-
    module_info_get_globals(ModuleInfo, Globals),
    ModuleName = mlds_get_module_name(MLDS),
    %FIXME: to source_file_name function exists
    module_name_to_file_name(Globals, $pred, do_create_dirs,
        ext_other(other_ext(".ml")), ModuleName, SourceFileName, !IO),
    Indent = 0,
    output_to_file_stream(Globals, ModuleName, SourceFileName,
        output_ocaml_src_file(ModuleInfo, Indent, MLDS), Succeeded, !IO).

:- pred output_ocaml_src_file(module_info::in, indent::in, mlds::in,
    io.text_output_stream::in, list(string)::out, io::di, io::uo) is det.

output_ocaml_src_file(_ModuleInfo, _Indent, MLDS, _Stream, Errors, !IO) :-
    % Run further transformations on the MLDS.
    MLDS = mlds(_ModuleName, _Imports, GlobalData,
        _TypeDefns, _TableStructDefns, _ProcDefns,
        _InitPreds, _FinalPreds, AllForeignCode, _ExportedEnums),
    ml_global_data_get_all_global_defns(GlobalData,
        _ScalarCellGroupMap, _VectorCellGroupMap, _AllocIdMap,
        _RttiDefns, _CellDefns, _ClosureWrapperFuncDefns),

    % Get the foreign code for OCaml.
    % XXX We should not ignore _Imports.
    ForeignCode = mlds_get_ocaml_foreign_code(AllForeignCode),
    ForeignCode = mlds_foreign_code(_ForeignDeclCodes, _ForeignBodyCodes,
        _Imports0, _ExportDefns),

    Errors = []

    .

%---------------------------------------------------------------------------%
%
% Code for working with `foreign_code'.
%

:- func mlds_get_ocaml_foreign_code(map(foreign_language, mlds_foreign_code))
    = mlds_foreign_code.

mlds_get_ocaml_foreign_code(AllForeignCode) = ForeignCode :-
    ( if map.search(AllForeignCode, lang_ocaml, ForeignCode0) then
        ForeignCode = ForeignCode0
    else
        ForeignCode = mlds_foreign_code([], [], [], [])
    ).

%---------------------------------------------------------------------------%
:- end_module ml_backend.mlds_to_ocaml_file.
%---------------------------------------------------------------------------%
