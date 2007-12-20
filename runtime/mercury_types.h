/*
** vim: ts=4 sw=4 expandtab
*/
/*
** Copyright (C) 1995-2007 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_types.h - definitions of some basic types used by the
** code generated by the Mercury compiler and by the Mercury runtime.
*/

/*
** IMPORTANT NOTE:
** This file must not contain any #include statements,
** other than the #include of "mercury_conf.h",
** for reasons explained in mercury_imp.h.
*/

#ifndef MERCURY_TYPES_H
#define MERCURY_TYPES_H

#include "mercury_conf.h"

/*
** MR_VARIABLE_SIZED -- what to put between the []s when declaring
**			a variable length array at the end of a struct.
**
** The preferred values, if the compiler understands them, convey to the
** implementation that the array has a variable length. The default value
** is the maximum length of the variable-length arrays that we construct,
** since giving too small a value may lead the compiler to use inappropriate
** optimizations (e.g. using small offsets to index into the array).
** At the moment, we use variable length arrays that are indexed by
** closure argument numbers or by type parameter numbers. We therefore
** use a default MR_VARIABLE_SIZED value that is at least as big as
** both MR_MAX_VIRTUAL_R_REG and MR_PSEUDOTYPEINFO_MAX_VAR.
*/

#if __STDC_VERSION__ >= 199901	/* January 1999 */
  /* Use C9X-style variable-length arrays. */
  #define	MR_VARIABLE_SIZED	/* nothing */
#elif defined(__GNUC__)
  /* Use GNU-style variable-length arrays */
  #define	MR_VARIABLE_SIZED	0
#else
  /* Just fake it by pretending that the array has a fixed size */
  #define	MR_VARIABLE_SIZED	1024
#endif

/*
** This section defines types similar to C9X's <stdint.h> header.
** We do not use <stdint.h>, or the <inttypes.h> or <sys/types.h> files
** that substitute for it on some systems because (a) some such files
** do not define the types we need, and (b) some such files include
** inline function definitions. The latter is a problem because we want to
** reserve some real machine registers for Mercury abstract machine registers.
** To be effective, the definitions of these global register variables
** must precede all function definitions, and we want to put their
** definitions after mercury_types.h.
*/

typedef unsigned MR_WORD_TYPE           MR_uintptr_t;
typedef MR_WORD_TYPE                    MR_intptr_t;

#ifdef  MR_INT_LEAST64_TYPE
typedef unsigned MR_INT_LEAST64_TYPE    MR_uint_least64_t;
typedef MR_INT_LEAST64_TYPE             MR_int_least64_t;
#endif

typedef unsigned MR_INT_LEAST32_TYPE    MR_uint_least32_t;
typedef MR_INT_LEAST32_TYPE             MR_int_least32_t;
typedef unsigned MR_INT_LEAST16_TYPE    MR_uint_least16_t;
typedef MR_INT_LEAST16_TYPE             MR_int_least16_t;
typedef unsigned char                   MR_uint_least8_t;
typedef signed char                     MR_int_least8_t;

/* 
** This section defines the basic types that we use.
** Note that we require 
**      sizeof(MR_Word) == sizeof(MR_Integer) == sizeof(MR_CodePtr).
*/

typedef MR_uintptr_t            MR_Word;
typedef MR_intptr_t             MR_Integer;
typedef MR_uintptr_t            MR_Unsigned;

/*
** Convert a size in bytes to a size in words, rounding up if necessary.
*/

#define MR_bytes_to_words(x)    (((x) + sizeof(MR_Word) - 1) / sizeof(MR_Word))

/*
** `MR_CodePtr' is used as a generic pointer-to-label type that can point
** to any label defined using the MR_define_* macros in mercury_goto.h.
*/

typedef void                    MR_Code;
typedef MR_Code                 *MR_CodePtr;

/*
** MR_Float64 is required for the bytecode.
** XXX: We should also check for IEEE-754 compliance.
*/

#if     MR_FLOAT_IS_64_BIT
        typedef float                   MR_Float64;
#elif   MR_DOUBLE_IS_64_BIT
        typedef double                  MR_Float64;
#elif   MR_LONG_DOUBLE_IS_64_BIT
        typedef long double             MR_Float64;
#else
        #error  "For Mercury bytecode, we require 64-bit IEEE-754 floating point"
#endif

/*
** The following four typedefs logically belong in mercury_string.h.
** They are defined here to avoid problems with circular #includes.
** If you modify them, you will need to modify mercury_string.h as well.
*/

typedef char            MR_Char;
typedef unsigned char   MR_UnsignedChar;

typedef MR_Char         *MR_String;
typedef const MR_Char   *MR_ConstString;

/*
** Definitions for accessing the representation of the Mercury `array' type.
** Even though array is defined in the library, it is a built in type in the
** sense that mlds_to_c generates references to it. Since mercury.h doesn't
** include mercury_library_types.h, the definition needs to be here, otherwise
** references to arrays in e.g. library/bitmap.m would cause C compiler errors.
**
** Note that arrays should be allocated on the Mercury heap,
** using MR_incr_hp_msg().
*/

typedef struct {
	MR_Integer size;
	MR_Word elements[MR_VARIABLE_SIZED];
} MR_ArrayType;

typedef MR_ArrayType		*MR_ArrayPtr;
typedef const MR_ArrayType	*MR_ConstArrayPtr;

typedef struct {
	MR_Integer num_bits;
	MR_uint_least8_t elements[MR_VARIABLE_SIZED];
} MR_BitmapType;

typedef MR_BitmapType		*MR_BitmapPtr;
typedef const MR_BitmapType	*MR_ConstBitmapPtr;

#ifndef MR_HIGHLEVEL_CODE
  /*
  ** Semidet predicates indicate success or failure by leaving nonzero or zero
  ** respectively in SUCCESS_INDICATOR, which the code generator (code_gen.m,
  ** call_gen.m, pragma_c_gen.m etc) knows to be MR_r1. (Note that
  ** pragma_c_gen.m temporarily redefines SUCCESS_INDICATOR.)
  ** (should this #define go in some other header file?)
  */
  #define SUCCESS_INDICATOR MR_r1
#endif

/*
** The MR_Box type is used for representing polymorphic types.
** Currently this is only used in the MLDS C backend.
**
** Since it is used in some C code fragments, we define it as MR_Word
** in the low-level backend.
*/

#ifdef MR_HIGHLEVEL_CODE
  typedef void      *MR_Box;
#else
  typedef MR_Word   MR_Box;
#endif

/*
** Tuples are always just arrays of polymorphic terms.
*/
#ifdef MR_HIGHLEVEL_CODE
  typedef MR_Box    *MR_Tuple;
#else
  typedef MR_Word   MR_Tuple;
#endif


/*
** These typedefs are forward declarations, used to avoid circular dependencies
** between header files.
*/

typedef struct MR_TypeCtorInfo_Struct                   MR_TypeCtorInfo_Struct;
typedef const struct MR_TypeCtorInfo_Struct             *MR_TypeCtorInfo;
typedef       struct MR_TypeInfo_Almost_Struct          *MR_TypeInfo;
typedef const struct MR_PseudoTypeInfo_Almost_Struct    *MR_PseudoTypeInfo;
typedef       struct MR_PseudoTypeInfo_Almost_Struct    *MR_NCPseudoTypeInfo;
typedef const void                                      *MR_ReservedAddr;

#ifdef  MR_HIGHLEVEL_CODE
  typedef MR_Box                                MR_BaseTypeclassInfo;
#else
  typedef MR_Code                               *MR_BaseTypeclassInfo;
#endif

typedef       struct MR_TypeClassDecl_Struct    MR_TypeClassDeclStruct;
typedef const struct MR_TypeClassDecl_Struct    *MR_TypeClassDecl;
typedef       struct MR_Instance_Struct         MR_InstanceStruct;
typedef const struct MR_Instance_Struct         *MR_Instance;
typedef       struct MR_DictId_Struct           MR_DictIdStruct;
typedef const struct MR_DictId_Struct           *MR_DictId;
typedef       struct MR_Dictionary_Struct       MR_DictionaryStruct;
typedef const struct MR_Dictionary_Struct       *MR_Dictionary;
typedef       struct MR_TypeClassId_Struct      MR_TypeClassId;
typedef       struct MR_TypeClassMethod_Struct  MR_TypeClassMethod;
typedef       struct MR_ClassDict_Struct        MR_ClassDict;

typedef struct MR_TrailEntry_Struct             MR_TrailEntry;
typedef struct MR_TrailEntry_Struct             *MR_TrailEntryPtr;

typedef struct MR_Closure_Struct                MR_Closure;
typedef const MR_Closure                        *MR_ClosurePtr;

typedef struct MR_ClosureId_Struct              MR_ClosureId;
typedef struct MR_UserClosureId_Struct          MR_UserClosureId;
typedef struct MR_UCIClosureId_Struct           MR_UCIClosureId;

typedef struct MR_TypeParamLocns_Struct         MR_TypeParamLocns;

typedef struct MR_UserProcId_Struct             MR_UserProcId;
typedef struct MR_UCIProcId_Struct              MR_UCIProcId;
typedef struct MR_NoProcId_Struct               MR_NoProcId;
typedef union  MR_ProcId_Union                  MR_ProcId;

typedef struct MR_CallSiteStatic_Struct         MR_CallSiteStatic;
typedef struct MR_CallSiteDynamic_Struct        MR_CallSiteDynamic;
typedef struct MR_User_ProcStatic_Struct        MR_User_ProcStatic;
typedef struct MR_UCI_ProcStatic_Struct         MR_UCI_ProcStatic;
typedef struct MR_ProcStatic_Struct             MR_ProcStatic;
typedef struct MR_ProcDynamic_Struct            MR_ProcDynamic;
typedef struct MR_ProfilingMetrics_Struct       MR_ProfilingMetrics;

typedef struct MR_CallSiteDynList_Struct        MR_CallSiteDynList;

typedef struct MR_LongLval_Struct               MR_LongLval;
typedef struct MR_ProcLayout_Struct             MR_ProcLayout;
typedef struct MR_ModuleCommonLayout_Struct     MR_ModuleCommonLayout;
typedef struct MR_ModuleLayout_Struct           MR_ModuleLayout;
typedef struct MR_LabelLayout_Struct            MR_LabelLayout;
typedef struct MR_SynthAttr_Struct              MR_SynthAttr;
typedef struct MR_UserEvent_Struct              MR_UserEvent;
typedef struct MR_UserEventSpec_Struct          MR_UserEventSpec;

typedef union MR_TableNode_Union                MR_TableNode;
typedef MR_TableNode                            *MR_TrieNode;
typedef MR_TrieNode                             *MR_TrieNodePtr;

typedef struct MR_HashTable_Struct              MR_HashTable;
typedef struct MR_MemoNonRecord_Struct          MR_MemoNonRecord;
typedef struct MR_MemoNonRecord_Struct          *MR_MemoNonRecordPtr;
typedef struct MR_AnswerListNode_Struct         MR_AnswerListNode;
typedef struct MR_Subgoal_Struct                MR_Subgoal;
typedef struct MR_SubgoalListNode_Struct        MR_SubgoalListNode;
typedef struct MR_Consumer_Struct               MR_Consumer;
typedef struct MR_ConsumerListNode_Struct       MR_ConsumerListNode;
typedef struct MR_Generator_Struct              MR_Generator;

typedef MR_SubgoalListNode                      *MR_SubgoalList;
typedef MR_AnswerListNode                       *MR_AnswerList;
typedef MR_ConsumerListNode                     *MR_ConsumerList;

typedef struct MR_GenStackFrameStruct           MR_GenStackFrame;
typedef struct MR_CutStackFrameStruct           MR_CutStackFrame;
typedef struct MR_PNegStackFrameStruct          MR_PNegStackFrame;

typedef struct MR_PNegConsumerListNodeStruct    MR_PNegConsumerListNode;
typedef MR_PNegConsumerListNode                 *MR_PNegConsumerList;

typedef struct MR_ConsumerDebug_Struct          MR_ConsumerDebug;
typedef struct MR_SubgoalDebug_Struct           MR_SubgoalDebug;
typedef struct MR_ConsDebug_Struct              MR_ConsDebug;
typedef struct MR_GenDebug_Struct               MR_GenDebug;

typedef	MR_Word		                            *MR_AnswerBlock;
typedef	MR_Subgoal	                            *MR_SubgoalPtr;
typedef	MR_Consumer	                            *MR_ConsumerPtr;
typedef	MR_Generator	                        *MR_GeneratorPtr;

typedef struct MR_TableStepStats_Struct         MR_TableStepStats;
typedef struct MR_ProcTableInfo_Struct          MR_ProcTableInfo;
typedef MR_ProcTableInfo                        *MR_ProcTableInfoPtr;

typedef struct MR_RegionHeader_Struct           MR_RegionHeader;
typedef struct MR_RegionPage_Struct             MR_RegionPage;
typedef struct MR_RegionSnapshot_Struct         MR_RegionSnapshot;
typedef struct MR_RegionIteFixedFrame_Struct    MR_RegionIteFixedFrame;
typedef struct MR_RegionDisjFixedFrame_Struct   MR_RegionDisjFixedFrame;
typedef struct MR_RegionCommitFixedFrame_Struct MR_RegionCommitFixedFrame;
typedef struct MR_RegionIteProtect_Struct       MR_RegionIteProtect;
typedef struct MR_RegionDisjProtect_Struct      MR_RegionDisjProtect;
typedef struct MR_RegionCommitSave_Struct       MR_RegionCommitSave;
typedef struct MR_RegionProfUnit_Struct         MR_RegionProfUnit;

#endif /* not MERCURY_TYPES_H */
