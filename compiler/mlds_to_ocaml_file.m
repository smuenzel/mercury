
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

%---------------------------------------------------------------------------%

output_ocaml_mlds(ModuleInfo, MLDS, Succeeded, !IO) :-
    module_info_get_globals(ModuleInfo, Globals),
    ModuleName = mlds_get_module_name(MLDS),
    module_name_to_file_name(Globals, $pred, do_create_dirs,
        ext_other(other_ext(".ml")), ModuleName, SourceFileName, !IO),
    Indent = 0,
    output_to_file_stream(Globals, ModuleName, SourceFileName,
        output_csharp_src_file(ModuleInfo, Indent, MLDS), Succeeded, !IO).

%---------------------------------------------------------------------------%
:- end_module ml_backend.mlds_to_ocaml_file.
%---------------------------------------------------------------------------%
