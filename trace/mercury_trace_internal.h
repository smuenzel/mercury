/*
** Copyright (C) 1998-2002, 2005 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

#ifndef	MERCURY_TRACE_INTERNAL_H
#define	MERCURY_TRACE_INTERNAL_H

#include "mercury_types.h"	/* for MR_Code */
#include "mercury_trace.h"	/* for MR_Event_Info, etc. */
#include "mercury_std.h"	/* for MR_bool */
#include "mercury_trace_completion.h"	/* for MR_Make_Completer */

#include <stdio.h>		/* for FILE */

/*
** The following enum gives the possible modes that the declarative
** debugger can be in (see trace/mercury_trace_declarative.{c,h}).
*/

typedef enum {
	MR_TRACE_INTERACTIVE,	 	/* Use internal debugger. */
	MR_TRACE_DECL_DEBUG,		/* Normal declarative debugging. */
	MR_TRACE_DECL_DEBUG_DUMP	/*
					** Output debugging info to a file
					** for separate analysis.
					*/
} MR_Trace_Mode;

/*
** This variable is modified whenever we start or stop collecting
** an execution tree.
*/

extern	MR_Trace_Mode	MR_trace_decl_mode;

extern	MR_Code	*MR_trace_event_internal(MR_Trace_Cmd_Info *cmd,
			MR_bool interactive, MR_Event_Info *event_info);


extern	MR_Code	*MR_trace_event_internal_report(MR_Trace_Cmd_Info *cmd,
			MR_Event_Info *event_info);

/*
** Debugger I/O streams.
** Replacements for stdin/stdout/stderr respectively.
**
** The distinction between MR_mdb_out and MR_mdb_err is analagous to
** the distinction between stdout and stderr: ordinary output, including
** information messages about conditions which are not errors, should
** go to MR_mdb_out, but error messages should go to MR_mdb_err.
*/
extern FILE *MR_mdb_in;
extern FILE *MR_mdb_out;
extern FILE *MR_mdb_err;

/*
** This just prints to MR_mdb_out a message telling the user
** that the debugger caught an interrupt.
*/
extern	void	MR_trace_interrupt_message(void);

extern	char	*MR_trace_getline(const char *prompt, FILE *mdb_in,
				FILE *mdb_out);
extern	char	*MR_trace_get_command(const char *prompt, FILE *mdb_in,
				FILE *mdb_out);

/*
** If word is a valid command, return information about the
** completer for the command.
*/
extern	MR_bool	MR_trace_command_completion_info(const char *word,
				MR_Make_Completer *completer,
				const char *const **fixed_args);

/* A Readline completer for command names. */
extern  MR_Completer_List *MR_trace_command_completer(const char *word,
				size_t word_len);

#endif	/* MERCURY_TRACE_INTERNAL_H */
