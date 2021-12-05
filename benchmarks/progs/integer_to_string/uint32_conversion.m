%---------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%---------------------------------------------------------------------------%

:- module uint32_conversion.
:- interface.

:- import_module io.

:- pred main(io::di, io::uo) is cc_multi.

%---------------------------------------------------------------------------%
%---------------------------------------------------------------------------%

:- implementation.

:- import_module array.
:- import_module benchmarking.
:- import_module float.
:- import_module list.
:- import_module maybe.
:- import_module random.
:- import_module random.sfc64.
:- import_module random.system_rng.
:- import_module require.
:- import_module string.
:- import_module uint32.
:- import_module unit.

%---------------------------------------------------------------------------%

main(!IO) :-
    NumRepeats = 100,
    NumElements = 10_000_000,
    io.format("n = %d; repeats = %d, grade = %s\n",
        [i(NumElements), i(NumRepeats), s($grade)], !IO),
    randomly_fill_array(NumElements, Array, SeedA, SeedB, SeedC, !IO),
    io.format("seed: a = %u, b = %u, c = %u\n",
        [u64(SeedA), u64(SeedB), u64(SeedC)], !IO),
    benchmark_det_io(run_test(std_uint32_to_string), Array, _, !IO,
        NumRepeats, TimeStd),
    io.format(" Std: %dms\n", [i(TimeStd)], !IO),
    benchmark_det_io(run_test(alt1_uint32_to_string), Array, _, !IO,
        NumRepeats, TimeAlt1),
    io.format("Alt1: %dms ratio: %.2f\n",
        [i(TimeAlt1), f(float(TimeStd) / float(TimeAlt1))], !IO),
    benchmark_det_io(run_test(alt2_uint32_to_string), Array, _, !IO,
        NumRepeats, TimeAlt2),
    io.format("Alt2: %dms ratio: %.2f\n",
        [i(TimeAlt2), f(float(TimeStd) / float(TimeAlt2))], !IO),
    benchmark_det_io(run_test(alt3_uint32_to_string), Array, _, !IO,
        NumRepeats, TimeAlt3),
    io.format("Alt3: %dms ratio: %.2f\n",
        [i(TimeAlt3), f(float(TimeStd) / float(TimeAlt3))], !IO),
    benchmark_det_io(run_test(alt4_uint32_to_string), Array, _, !IO,
        NumRepeats, TimeAlt4),
    io.format("Alt4: %dms ratio: %.2f\n",
        [i(TimeAlt4), f(float(TimeStd) / float(TimeAlt4))], !IO),
    benchmark_det_io(run_test(alt5_uint32_to_string), Array, _, !IO,
        NumRepeats, TimeAlt5),
    io.format("Alt5: %dms ratio: %.2f\n",
        [i(TimeAlt5), f(float(TimeStd) / float(TimeAlt5))], !IO).

%---------------------------------------------------------------------------%

:- pred randomly_fill_array(int::in, array(uint32)::array_uo,
    uint64::out, uint64::out, uint64::out, io::di, io::uo) is det.

randomly_fill_array(Size, Array, A, B, C, !IO) :-
    open_system_rng(MaybeSysRNG, !IO),
    (
        MaybeSysRNG = ok(SysRNG)
    ;
        MaybeSysRNG = error(Error),
        error(string(Error))
    ),
    system_rng.generate_uint64(SysRNG, A, !IO),
    system_rng.generate_uint64(SysRNG, B, !IO),
    system_rng.generate_uint64(SysRNG, C, !IO),
    close_system_rng(SysRNG, !IO),
    sfc64.seed(A, B, C, Params, State0),
    array.generate_foldl(Size, generate_int(Params), Array, State0, _State).

:- pred generate_int(sfc64.params::in, int::in, uint32::out,
    sfc64.ustate::di, sfc64.ustate::uo) is det.

generate_int(Params, _I, N, !State) :-
    random.generate_uint32(Params, N, !State).

%---------------------------------------------------------------------------%

:- pred run_test((func(uint32) = string)::in(func(in) = uo is det),
    array(uint32)::in, unit::out, io::di, io::uo) is det.

run_test(Func, Array, unit, !IO) :-
    array.foldl(do_test(Func), Array, !IO).

%---------------------------------------------------------------------------%

:- pred do_test((func(uint32) = string)::in(func(in) = uo is det),
    uint32::in, io::di, io::uo) is det.

do_test(Func, N, !IO) :-
    S = Func(N),
    consume_string(S, !IO).

%---------------------------------------------------------------------------%

:- pragma no_inline(pred(consume_string/3)).
:- pred consume_string(string::in, io::di, io::uo) is det.
:- pragma foreign_proc("C",
    consume_string(S::in, _IO0::di, _IO::uo),
    [will_not_call_mercury, promise_pure, thread_safe],
"
    // S
").
:- pragma foreign_proc("C#",
    consume_string(S::in, _IO0::di, _IO::uo),
    [will_not_call_mercury, promise_pure, thread_safe],
"
    // S
").
:- pragma foreign_proc("Java",
    consume_string(S::in, _IO0::di, _IO::uo),
    [will_not_call_mercury, promise_pure, thread_safe],
"
    // S
").

%---------------------------------------------------------------------------%
%
% Std implementation using sprintf().
%

:- func std_uint32_to_string(uint32::in) = (string::uo) is det.
:- pragma foreign_proc("C",
    std_uint32_to_string(U32::in) = (S::uo),
    [will_not_call_mercury, promise_pure, thread_safe, will_not_modify_trail],
"
    char buffer[11]; // 10 for digits, 1 for nul.
    sprintf(buffer, ""%"" PRIu32, U32);
    MR_allocate_aligned_string_msg(S, strlen(buffer), MR_ALLOC_ID);
    strcpy(S, buffer);
").

%---------------------------------------------------------------------------%

:- func alt1_uint32_to_string(uint32::in) = (string::uo) is det.
:- pragma foreign_proc("C",
    alt1_uint32_to_string(U::in) = (S::uo),
    [will_not_call_mercury, promise_pure, thread_safe, will_not_modify_trail],
"
    int num_digits;
    if (U < 10) {
        num_digits = 1;
    } else if (U < 100) {
        num_digits = 2;
    } else if (U < 1000) {
        num_digits = 3;
    } else if (U < 10000) {
        num_digits = 4;
    } else if (U < 100000) {
        num_digits = 5;
    } else if (U < 1000000) {
        num_digits = 6;
    } else if (U < 10000000) {
        num_digits = 7;
    } else if (U < 100000000) {
        num_digits = 8;
    } else if (U < 1000000000) {
        num_digits = 9;
    } else {
        num_digits = 10;
    }

    MR_allocate_aligned_string_msg(S, num_digits, MR_ALLOC_ID);
    S[num_digits] = '\\0';
    int i = num_digits - 1;
    do {
        S[i] = \"0123456789\"[U % 10];
        i--;
        U /= 10;
    } while(U > 0);
").

%---------------------------------------------------------------------------%

% Same as alt1 except it uses Andrei Alexandrescu's digit counting method.
% See: <https://www.facebook.com/notes/10158791579037200/>
% This is biased in favour of small numbers, it doesn't really help for
% this benchmark.
%
:- func alt2_uint32_to_string(uint32::in) = (string::uo) is det.
:- pragma foreign_proc("C",
    alt2_uint32_to_string(U::in) = (S::uo),
    [will_not_call_mercury, promise_pure, thread_safe, will_not_modify_trail],
"
    uint32_t v = U;
    int num_digits = 1;
    for (;;) {
        if (v < 10) { break; }
        if (v < 100) { num_digits += 1; break; }
        if (v < 1000) { num_digits +=2; break; }
        if (v < 10000) { num_digits += 3; break; }
        v /= UINT32_C(10000);
        num_digits += 4;
    }

    MR_allocate_aligned_string_msg(S, num_digits, MR_ALLOC_ID);
    S[num_digits] = '\\0';
    int i = num_digits - 1;
    do {
        S[i] = \"0123456789\"[U % 10];
        i--;
        U /= 10;
    } while(U > 0);
").

%---------------------------------------------------------------------------%

% Use addition to compute digit chars instead of an array lookup.

:- func alt3_uint32_to_string(uint32::in) = (string::uo) is det.
:- pragma foreign_proc("C",
    alt3_uint32_to_string(U::in) = (S::uo),
    [will_not_call_mercury, promise_pure, thread_safe, will_not_modify_trail],
"
    int num_digits;
    if (U < 10) {
        num_digits = 1;
    } else if (U < 100) {
        num_digits = 2;
    } else if (U < 1000) {
        num_digits = 3;
    } else if (U < 10000) {
        num_digits = 4;
    } else if (U < 100000) {
        num_digits = 5;
    } else if (U < 1000000) {
        num_digits = 6;
    } else if (U < 10000000) {
        num_digits = 7;
    } else if (U < 100000000) {
        num_digits = 8;
    } else if (U < 1000000000) {
        num_digits = 9;
    } else {
        num_digits = 10;
    }

    MR_allocate_aligned_string_msg(S, num_digits, MR_ALLOC_ID);
    S[num_digits] = '\\0';
    int i = num_digits - 1;
    do {
        S[i] = '0' + (U % 10);
        i--;
        U /= 10;
    } while(U > 0);
").

%---------------------------------------------------------------------------%

% Lookup pairs of digits every iteration.

:- func alt4_uint32_to_string(uint32::in) = (string::uo) is det.
:- pragma foreign_proc("C",
    alt4_uint32_to_string(U::in) = (S::uo),
    [will_not_call_mercury, promise_pure, thread_safe, will_not_modify_trail],
"
    int num_digits;
    if (U < 10) {
        num_digits = 1;
    } else if (U < 100) {
        num_digits = 2;
    } else if (U < 1000) {
        num_digits = 3;
    } else if (U < 10000) {
        num_digits = 4;
    } else if (U < 100000) {
        num_digits = 5;
    } else if (U < 1000000) {
        num_digits = 6;
    } else if (U < 10000000) {
        num_digits = 7;
    } else if (U < 100000000) {
        num_digits = 8;
    } else if (U < 1000000000) {
        num_digits = 9;
    } else {
        num_digits = 10;
    }

    static const char digits[201] =
        \"0001020304050607080910111213141516171819\"
        \"2021222324252627282930313233343536373839\"
        \"4041424344454647484950515253545556575859\"
        \"6061626364656667686970717273747576777879\"
        \"8081828384858687888990919293949596979899\";

    MR_allocate_aligned_string_msg(S, num_digits, MR_ALLOC_ID);
    S[num_digits] = '\\0';
    int next = num_digits - 1;
    while (U >= 100) {
        int i = (U % 100) * 2;
        U /= 100;
        S[next] = digits[i + 1];
        S[next - 1] = digits[i];
        next -= 2;
    }

    if (U < 10) {
        S[next] = '0' + U;
    } else {
        int i = U * 2;
        S[next] = digits[i + 1];
        S[next - 1] = digits[i];
    }
").

%---------------------------------------------------------------------------%

% Lookup pairs of digits every iteration using base 10 integer log
% to compute the number of digits.

:- func alt5_uint32_to_string(uint32::in) = (string::uo) is det.
:- pragma foreign_proc("C",
    alt5_uint32_to_string(U::in) = (S::uo),
    [will_not_call_mercury, promise_pure, thread_safe, will_not_modify_trail],
"
    int num_digits = digit_count(U);

    static const char digits[201] =
        \"0001020304050607080910111213141516171819\"
        \"2021222324252627282930313233343536373839\"
        \"4041424344454647484950515253545556575859\"
        \"6061626364656667686970717273747576777879\"
        \"8081828384858687888990919293949596979899\";

    MR_allocate_aligned_string_msg(S, num_digits, MR_ALLOC_ID);
    S[num_digits] = '\\0';
    int next = num_digits - 1;
    while (U >= 100) {
        uint32_t i = (U % 100) * 2;
        U /= 100;
        S[next] = digits[i + 1];
        S[next - 1] = digits[i];
        next -= 2;
    }

    if (U < 10) {
        S[next] = '0' + U;
    } else {
        uint32_t i = U * 2;
        S[next] = digits[i + 1];
        S[next - 1] = digits[i];
    }
").

:- pragma foreign_decl("C", "

extern int digit_count(uint32_t x);

").

% Integer log base 10: Hacker's Delight 2nd Edition, figure 11-13.
:- pragma foreign_code("C", "

#define ILOG2(N) (31 - __builtin_clz((N) | 1))

int digit_count(uint32_t x) {
  static const uint32_t table[] = {9, 99, 999, 9999, 99999,
    999999, 9999999, 99999999, 999999999};
  int y = (9 * ILOG2(x)) >> 5;
  y += x > table[y];
  return y + 1;
}

").

%---------------------------------------------------------------------------%
:- end_module uint32_conversion.
%---------------------------------------------------------------------------%
