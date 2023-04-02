
:- module ml_backend.mlds_to_ml_file.
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
:- end_module ml_backend.mlds_to_ocaml_file.
%---------------------------------------------------------------------------%
